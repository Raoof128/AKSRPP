#!/bin/bash
# Falco Runtime Security Installation Script
# Deploys Falco with custom rules and sidekick integration

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

NAMESPACE="security"
RELEASE_NAME="falco"
CHART_VERSION="3.8.4"
VALUES_FILE="falco-values.yaml"

echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Falco Runtime Security Installation      ║${NC}"
echo -e "${GREEN}║  eBPF-based Threat Detection              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}[1/7]${NC} Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl not found${NC}"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo -e "${RED}✗ helm not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites validated${NC}"

# Create namespace
echo -e "${YELLOW}[2/7]${NC} Creating namespace: ${NAMESPACE}..."
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace ${NAMESPACE} network-policy=enabled pod-security.kubernetes.io/enforce=privileged --overwrite
echo -e "${GREEN}✓ Namespace ready${NC}"

# Add Falco Helm repository
echo -e "${YELLOW}[3/7]${NC} Adding Falco Helm repository..."
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update
echo -e "${GREEN}✓ Helm repository added${NC}"

# Create ConfigMap with custom rules
echo -e "${YELLOW}[4/7]${NC} Creating custom Falco rules ConfigMap..."

kubectl create configmap falco-custom-rules \
  --from-file=custom-container-escape.yaml \
  --from-file=custom-privilege-escalation.yaml \
  --from-file=custom-reverse-shells.yaml \
  -n ${NAMESPACE} \
  --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}✓ Custom rules ConfigMap created${NC}"

# Install Falco
echo -e "${YELLOW}[5/7]${NC} Installing Falco ${CHART_VERSION}..."

helm upgrade --install ${RELEASE_NAME} falcosecurity/falco \
  --namespace ${NAMESPACE} \
  --version ${CHART_VERSION} \
  --values ${VALUES_FILE} \
  --set falcosidekick.enabled=true \
  --wait \
  --timeout 5m

echo -e "${GREEN}✓ Falco installed${NC}"

# Wait for pods
echo -e "${YELLOW}[6/7]${NC} Waiting for Falco pods to be ready..."
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=falco \
  -n ${NAMESPACE} \
  --timeout=300s

echo -e "${GREEN}✓ Falco pods ready${NC}"

# Verify installation
echo -e "${YELLOW}[7/7]${NC} Verifying installation..."

# Check DaemonSet
if kubectl get daemonset -n ${NAMESPACE} ${RELEASE_NAME} &> /dev/null; then
    DESIRED=$(kubectl get daemonset -n ${NAMESPACE} ${RELEASE_NAME} -o jsonpath='{.status.desiredNumberScheduled}')
    READY=$(kubectl get daemonset -n ${NAMESPACE} ${RELEASE_NAME} -o jsonpath='{.status.numberReady}')
    echo -e "${GREEN}  ✓ Falco DaemonSet: ${READY}/${DESIRED} pods ready${NC}"
else
    echo -e "${RED}  ✗ Falco DaemonSet not found${NC}"
    exit 1
fi

# Check Falcosidekick
if kubectl get deployment -n ${NAMESPACE} ${RELEASE_NAME}-falcosidekick &> /dev/null; then
    echo -e "${GREEN}  ✓ Falcosidekick deployed${NC}"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Falco Installation Complete!             ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo "Deployment Information:"
echo "  Namespace: ${NAMESPACE}"
echo "  Release: ${RELEASE_NAME}"
echo "  Version: ${CHART_VERSION}"
echo ""
echo "Custom Rules Loaded:"
echo "  - Container escape detection"
echo "  - Privilege escalation detection"
echo "  - Reverse shell & C2 detection"
echo ""
echo "Check status:"
echo "  kubectl get pods -n ${NAMESPACE}"
echo "  kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=falco --tail=50"
echo ""
echo "Test detection:"
echo "  kubectl run test --rm -it --image=busybox -- sh -c 'cat /etc/shadow'"
echo "  (Expected: Falco alert for sensitive file access)"
echo ""
