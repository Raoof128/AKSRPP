#!/bin/bash
# OPA Gatekeeper Installation Script
# Deploys Gatekeeper with production-grade configuration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="gatekeeper-system"
RELEASE_NAME="gatekeeper"
CHART_VERSION="3.15.0"
VALUES_FILE="gatekeeper-values.yaml"

echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  OPA Gatekeeper Installation              ║${NC}"
echo -e "${GREEN}║  Production Security Policy Enforcement   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}[1/6]${NC} Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl not found. Please install kubectl.${NC}"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo -e "${RED}✗ helm not found. Please install Helm 3.${NC}"
    exit 1
fi

# Verify cluster connection
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}✗ Cannot connect to Kubernetes cluster.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites validated${NC}"

# Add Gatekeeper Helm repository
echo -e "${YELLOW}[2/6]${NC} Adding Gatekeeper Helm repository..."
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update
echo -e "${GREEN}✓ Helm repository added${NC}"

# Create namespace
echo -e "${YELLOW}[3/6]${NC} Creating namespace: ${NAMESPACE}..."
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✓ Namespace ready${NC}"

# Install Gatekeeper
echo -e "${YELLOW}[4/6]${NC} Installing Gatekeeper ${CHART_VERSION}..."
helm upgrade --install ${RELEASE_NAME} gatekeeper/gatekeeper \
    --namespace ${NAMESPACE} \
    --version ${CHART_VERSION} \
    --values ${VALUES_FILE} \
    --wait \
    --timeout 5m

echo -e "${GREEN}✓ Gatekeeper installed${NC}"

# Wait for Gatekeeper to be ready
echo -e "${YELLOW}[5/6]${NC} Waiting for Gatekeeper pods to be ready..."
kubectl wait --for=condition=ready pod \
    -l app=gatekeeper \
    -n ${NAMESPACE} \
    --timeout=300s

echo -e "${GREEN}✓ Gatekeeper pods ready${NC}"

# Verify installation
echo -e "${YELLOW}[6/6]${NC} Verifying installation..."

# Check CRDs
EXPECTED_CRDS=(
    "constrainttemplates.templates.gatekeeper.sh"
    "configs.config.gatekeeper.sh"
)

for crd in "${EXPECTED_CRDS[@]}"; do
    if kubectl get crd ${crd} &> /dev/null; then
        echo -e "${GREEN}  ✓ CRD ${crd} installed${NC}"
    else
        echo -e "${RED}  ✗ CRD ${crd} missing${NC}"
        exit 1
    fi
done

# Check webhook configuration
if kubectl get validatingwebhookconfigurations.admissionregistration.k8s.io gatekeeper-validating-webhook-configuration &> /dev/null; then
    echo -e "${GREEN}  ✓ Validating webhook configured${NC}"
else
    echo -e "${RED}  ✗ Validating webhook missing${NC}"
    exit 1
fi

# Display deployment info
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Gatekeeper Installation Complete!        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo "Deployment Information:"
echo "  Namespace: ${NAMESPACE}"
echo "  Release: ${RELEASE_NAME}"
echo "  Version: ${CHART_VERSION}"
echo ""
echo "Check status:"
echo "  kubectl get pods -n ${NAMESPACE}"
echo "  kubectl get constrainttemplates"
echo ""
echo "Next steps:"
echo "  1. Apply constraint templates: ./apply-policies.sh"
echo "  2. Verify policies: ./verify-policies.sh"
echo "  3. Test enforcement: kubectl apply -f ../policy-tests/"
echo ""
