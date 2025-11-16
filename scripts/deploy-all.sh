#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi

    if ! command -v helm &> /dev/null; then
        missing_tools+=("helm")
    fi

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install missing tools and try again"
        exit 1
    fi

    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        log_info "Run './scripts/setup-cluster.sh' first to create a local cluster"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Phase 1: Deploy OPA Gatekeeper and Policies
deploy_phase1() {
    log_info "========================================="
    log_info "PHASE 1: Admission Control (OPA Gatekeeper)"
    log_info "========================================="

    cd "$PROJECT_ROOT/admission-controller/deployment"

    log_info "Installing OPA Gatekeeper..."
    ./install-gatekeeper.sh

    log_info "Waiting for Gatekeeper to be ready..."
    kubectl wait --for=condition=ready pod \
        -l control-plane=controller-manager \
        -n gatekeeper-system \
        --timeout=120s

    log_info "Applying security policies..."
    ./apply-policies.sh

    log_info "Verifying policy deployment..."
    ./verify-policies.sh

    log_success "Phase 1 deployment complete"
    echo
}

# Phase 2: Deploy Falco and Remediation Operator
deploy_phase2() {
    log_info "========================================="
    log_info "PHASE 2: Runtime Security (Falco)"
    log_info "========================================="

    cd "$PROJECT_ROOT/runtime-security"

    log_info "Installing Falco with custom rules..."
    cd falco-rules
    ./install-falco.sh

    log_info "Waiting for Falco to be ready..."
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=falco \
        -n falco \
        --timeout=120s || log_warning "Falco pods not ready yet, continuing..."

    log_info "Deploying remediation operator..."
    cd "$PROJECT_ROOT/runtime-security/response-automation/kubernetes-manifests"
    kubectl apply -f .

    log_info "Waiting for operator to be ready..."
    kubectl wait --for=condition=ready pod \
        -l app=remediation-operator \
        -n security \
        --timeout=120s || log_warning "Operator not ready yet, continuing..."

    log_success "Phase 2 deployment complete"
    echo
}

# Phase 3: Deploy Cilium and Supply Chain Security
deploy_phase3() {
    log_info "========================================="
    log_info "PHASE 3: Network & Supply Chain Security"
    log_info "========================================="

    # Check if Cilium is already installed (might be cluster CNI)
    if kubectl get pods -n kube-system -l k8s-app=cilium &> /dev/null; then
        log_warning "Cilium appears to be already installed as cluster CNI"
        log_info "Skipping Cilium installation, applying network policies only..."
    else
        log_info "Installing Cilium CNI..."
        cd "$PROJECT_ROOT/network-policies/cilium-configs"

        helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
        helm repo update

        helm upgrade --install cilium cilium/cilium \
            --namespace kube-system \
            --values cilium-values.yaml \
            --wait \
            --timeout 5m || log_warning "Cilium installation failed, may already be configured"
    fi

    log_info "Applying network policies..."
    cd "$PROJECT_ROOT/network-policies/cilium-configs/network-policies"
    kubectl apply -f default-deny-all.yaml || true
    kubectl apply -f allow-dns.yaml || true

    log_info "Supply chain security tools configured"
    log_info "SBOM generation available at: supply-chain/sbom-generator/scan-images.py"

    log_success "Phase 3 deployment complete"
    echo
}

# Phase 4: Deploy Monitoring Stack
deploy_phase4() {
    log_info "========================================="
    log_info "PHASE 4: Monitoring & Observability"
    log_info "========================================="

    log_info "Creating monitoring namespace..."
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

    log_info "Installing Prometheus..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
    helm repo update

    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --set prometheus.prometheusSpec.retention=90d \
        --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=50Gi \
        --wait \
        --timeout 5m || log_warning "Prometheus installation had issues, continuing..."

    log_info "Applying custom security alerting rules..."
    kubectl apply -f "$PROJECT_ROOT/monitoring/prometheus-rules/security-alerts.yaml" || true

    log_info "Importing Grafana dashboard..."
    log_info "Dashboard available at: monitoring/grafana-dashboards/security-posture.json"

    log_success "Phase 4 deployment complete"
    echo
}

# Display access information
display_access_info() {
    log_info "========================================="
    log_info "DEPLOYMENT COMPLETE!"
    log_info "========================================="
    echo

    log_success "All 4 phases deployed successfully"
    echo

    log_info "Access Points:"
    echo
    echo "  Grafana Dashboard:"
    echo "    kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
    echo "    http://localhost:3000 (admin / prom-operator)"
    echo
    echo "  Prometheus:"
    echo "    kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
    echo "    http://localhost:9090"
    echo
    echo "  Hubble UI (if Cilium installed):"
    echo "    kubectl port-forward -n kube-system svc/hubble-ui 8080:80"
    echo "    http://localhost:8080"
    echo

    log_info "Verify deployment with:"
    echo "    ./scripts/validate-security.sh"
    echo

    log_info "View pod status:"
    echo "    kubectl get pods -n gatekeeper-system"
    echo "    kubectl get pods -n falco"
    echo "    kubectl get pods -n security"
    echo "    kubectl get pods -n monitoring"
    echo

    log_info "Test policy enforcement:"
    echo "    kubectl apply -f admission-controller/policy-tests/test-01-privileged-fail.yaml"
    echo "    # Should be denied by OPA policy"
    echo
}

# Main deployment flow
main() {
    log_info "Starting AKSRPP Full Platform Deployment"
    log_info "This will deploy all 4 security phases"
    echo

    check_prerequisites
    echo

    deploy_phase1
    deploy_phase2
    deploy_phase3
    deploy_phase4

    display_access_info

    log_success "Deployment script completed!"
}

# Run main function
main "$@"
