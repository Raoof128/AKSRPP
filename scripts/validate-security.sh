#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    ((PASSED_CHECKS++))
    ((TOTAL_CHECKS++))
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
    ((WARNING_CHECKS++))
    ((TOTAL_CHECKS++))
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    ((FAILED_CHECKS++))
    ((TOTAL_CHECKS++))
}

# Check if namespace exists
check_namespace() {
    local ns=$1
    if kubectl get namespace "$ns" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Check if pods are running in namespace
check_pods_running() {
    local ns=$1
    local label=$2
    local min_count=${3:-1}

    local ready_count
    ready_count=$(kubectl get pods -n "$ns" -l "$label" \
        -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null | wc -w)

    if [ "$ready_count" -ge "$min_count" ]; then
        return 0
    else
        return 1
    fi
}

# Validate Phase 1: OPA Gatekeeper
validate_phase1() {
    log_info "========================================="
    log_info "PHASE 1: Admission Control Validation"
    log_info "========================================="
    echo

    # Check Gatekeeper namespace
    if check_namespace "gatekeeper-system"; then
        log_success "Gatekeeper namespace exists"
    else
        log_error "Gatekeeper namespace not found"
        return
    fi

    # Check Gatekeeper pods
    if check_pods_running "gatekeeper-system" "control-plane=controller-manager" 1; then
        log_success "Gatekeeper controller is running"
    else
        log_error "Gatekeeper controller not running"
    fi

    if check_pods_running "gatekeeper-system" "control-plane=audit-controller" 1; then
        log_success "Gatekeeper audit controller is running"
    else
        log_warning "Gatekeeper audit controller not running"
    fi

    # Check policy templates
    local template_count
    template_count=$(kubectl get constrainttemplates 2>/dev/null | grep -c "k8s" || echo 0)
    if [ "$template_count" -ge 20 ]; then
        log_success "Policy templates deployed ($template_count found)"
    elif [ "$template_count" -gt 0 ]; then
        log_warning "Some policy templates deployed ($template_count/22)"
    else
        log_error "No policy templates found"
    fi

    # Test policy enforcement
    log_info "Testing policy enforcement..."
    if kubectl apply -f - --dry-run=server <<EOF &>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: test-privileged
  namespace: default
spec:
  containers:
  - name: test
    image: nginx:latest
    securityContext:
      privileged: true
EOF
    then
        log_warning "Privileged pod NOT blocked (policies may not be enforced)"
    else
        log_success "Privileged pod correctly blocked by policy"
    fi

    echo
}

# Validate Phase 2: Runtime Security
validate_phase2() {
    log_info "========================================="
    log_info "PHASE 2: Runtime Security Validation"
    log_info "========================================="
    echo

    # Check Falco namespace
    if check_namespace "falco"; then
        log_success "Falco namespace exists"
    else
        log_warning "Falco namespace not found (may use different namespace)"
    fi

    # Check Falco pods
    if check_pods_running "falco" "app.kubernetes.io/name=falco" 1; then
        log_success "Falco pods are running"
    else
        log_warning "Falco pods not found or not running"
    fi

    # Check security namespace
    if check_namespace "security"; then
        log_success "Security namespace exists"
    else
        log_warning "Security namespace not found"
    fi

    # Check remediation operator
    if check_pods_running "security" "app=remediation-operator" 1; then
        log_success "Remediation operator is running"

        # Check operator replicas
        local replica_count
        replica_count=$(kubectl get pods -n security -l app=remediation-operator \
            -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | wc -w)
        if [ "$replica_count" -ge 2 ]; then
            log_success "Operator running with HA ($replica_count replicas)"
        else
            log_warning "Operator running with single replica (HA recommended)"
        fi
    else
        log_warning "Remediation operator not running"
    fi

    # Check Falco rules configmap
    if kubectl get configmap -n falco | grep -q "falco"; then
        log_success "Falco rules configmap found"
    else
        log_warning "Falco rules configmap not found"
    fi

    echo
}

# Validate Phase 3: Network Security
validate_phase3() {
    log_info "========================================="
    log_info "PHASE 3: Network Security Validation"
    log_info "========================================="
    echo

    # Check for Cilium
    if check_pods_running "kube-system" "k8s-app=cilium" 1; then
        log_success "Cilium CNI is running"

        # Check Hubble
        if check_pods_running "kube-system" "k8s-app=hubble-relay" 1; then
            log_success "Hubble relay is running"
        else
            log_warning "Hubble relay not found (optional)"
        fi
    else
        log_warning "Cilium not detected (may be using different CNI)"
    fi

    # Check for network policies
    local netpol_count
    netpol_count=$(kubectl get networkpolicies --all-namespaces 2>/dev/null | tail -n +2 | wc -l)
    if [ "$netpol_count" -gt 0 ]; then
        log_success "Network policies deployed ($netpol_count found)"
    else
        log_warning "No network policies found"
    fi

    # Check for supply chain tools
    if command -v trivy &> /dev/null; then
        log_success "Trivy scanner available"
    else
        log_warning "Trivy not installed (optional for local scanning)"
    fi

    if command -v syft &> /dev/null; then
        log_success "Syft SBOM generator available"
    else
        log_warning "Syft not installed (optional for local SBOM generation)"
    fi

    echo
}

# Validate Phase 4: Monitoring
validate_phase4() {
    log_info "========================================="
    log_info "PHASE 4: Monitoring Validation"
    log_info "========================================="
    echo

    # Check monitoring namespace
    if check_namespace "monitoring"; then
        log_success "Monitoring namespace exists"
    else
        log_warning "Monitoring namespace not found"
        return
    fi

    # Check Prometheus
    if check_pods_running "monitoring" "app.kubernetes.io/name=prometheus" 1; then
        log_success "Prometheus is running"
    else
        log_warning "Prometheus not running"
    fi

    # Check Grafana
    if check_pods_running "monitoring" "app.kubernetes.io/name=grafana" 1; then
        log_success "Grafana is running"
    else
        log_warning "Grafana not running"
    fi

    # Check Alertmanager
    if check_pods_running "monitoring" "app.kubernetes.io/name=alertmanager" 1; then
        log_success "Alertmanager is running"
    else
        log_warning "Alertmanager not running"
    fi

    # Check for PrometheusRule
    local rule_count
    rule_count=$(kubectl get prometheusrules -n monitoring 2>/dev/null | tail -n +2 | wc -l || echo 0)
    if [ "$rule_count" -gt 0 ]; then
        log_success "Prometheus rules configured ($rule_count found)"
    else
        log_warning "No custom Prometheus rules found"
    fi

    echo
}

# Security posture summary
display_summary() {
    log_info "========================================="
    log_info "SECURITY POSTURE SUMMARY"
    log_info "========================================="
    echo

    local pass_rate=0
    if [ "$TOTAL_CHECKS" -gt 0 ]; then
        pass_rate=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
    fi

    echo "  Total Checks: $TOTAL_CHECKS"
    echo -e "  ${GREEN}Passed: $PASSED_CHECKS${NC}"
    echo -e "  ${YELLOW}Warnings: $WARNING_CHECKS${NC}"
    echo -e "  ${RED}Failed: $FAILED_CHECKS${NC}"
    echo
    echo "  Overall Score: $pass_rate%"
    echo

    if [ "$FAILED_CHECKS" -eq 0 ] && [ "$WARNING_CHECKS" -eq 0 ]; then
        log_success "Security platform is fully operational!"
    elif [ "$FAILED_CHECKS" -eq 0 ]; then
        log_warning "Security platform is operational with minor warnings"
    else
        log_error "Security platform has critical issues"
    fi

    echo
    log_info "Recommendations:"

    if [ "$FAILED_CHECKS" -gt 0 ]; then
        echo "  • Review failed checks above"
        echo "  • Run './scripts/deploy-all.sh' to deploy missing components"
    fi

    if [ "$WARNING_CHECKS" -gt 0 ]; then
        echo "  • Review warnings for optional improvements"
        echo "  • Consider enabling HA for production environments"
    fi

    echo "  • Test policy enforcement: kubectl apply -f admission-controller/policy-tests/"
    echo "  • View metrics: kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
    echo "  • Check logs: kubectl logs -n security -l app=remediation-operator"
    echo
}

# Main validation flow
main() {
    log_info "AKSRPP Security Platform Validation"
    log_info "Checking deployment status and configuration..."
    echo

    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    log_success "Connected to cluster: $(kubectl config current-context)"
    echo

    validate_phase1
    validate_phase2
    validate_phase3
    validate_phase4
    display_summary
}

# Run main function
main "$@"
