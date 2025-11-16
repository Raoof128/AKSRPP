#!/bin/bash
# Kubernetes Security Platform - Cluster Setup
# Creates local Kind cluster for testing security platform

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-k8s-security-platform}"
K8S_VERSION="${K8S_VERSION:-v1.28.0}"

echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Kubernetes Security Platform Setup       ║${NC}"
echo -e "${BLUE}║  Creating Kind Cluster                     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}[1/5]${NC} Checking prerequisites..."

if ! command -v kind &> /dev/null; then
    echo -e "${RED}✗ kind not found. Installing...${NC}"
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl not found. Installing...${NC}"
    curl -LO "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/kubectl
fi

if ! command -v helm &> /dev/null; then
    echo -e "${RED}✗ helm not found. Installing...${NC}"
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

echo -e "${GREEN}✓ Prerequisites installed${NC}"

# Create Kind cluster
echo -e "${YELLOW}[2/5]${NC} Creating Kind cluster: ${CLUSTER_NAME}..."

# Delete existing cluster if present
kind delete cluster --name ${CLUSTER_NAME} 2>/dev/null || true

# Create cluster with custom configuration
cat <<EOF | kind create cluster --name ${CLUSTER_NAME} --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    image: kindest/node:${K8S_VERSION}
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
  - role: worker
    image: kindest/node:${K8S_VERSION}
  - role: worker
    image: kindest/node:${K8S_VERSION}
EOF

echo -e "${GREEN}✓ Kind cluster created${NC}"

# Configure kubectl context
echo -e "${YELLOW}[3/5]${NC} Configuring kubectl context..."
kubectl cluster-info --context kind-${CLUSTER_NAME}
echo -e "${GREEN}✓ kubectl configured${NC}"

# Create namespaces
echo -e "${YELLOW}[4/5]${NC} Creating namespaces..."
kubectl create namespace production --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace staging --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace development --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Label namespaces for NetworkPolicy requirement
kubectl label namespace production network-policy=enabled --overwrite
kubectl label namespace staging network-policy=enabled --overwrite
kubectl label namespace development network-policy=enabled --overwrite

echo -e "${GREEN}✓ Namespaces created${NC}"

# Display cluster info
echo -e "${YELLOW}[5/5]${NC} Cluster information..."

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Cluster Ready!                            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""
echo "Cluster Name: ${CLUSTER_NAME}"
echo "Kubernetes Version: ${K8S_VERSION}"
echo ""
echo "Nodes:"
kubectl get nodes
echo ""
echo "Namespaces:"
kubectl get namespaces
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "  1. Deploy OPA Gatekeeper:"
echo "     cd admission-controller/deployment && ./install-gatekeeper.sh"
echo ""
echo "  2. Apply security policies:"
echo "     ./apply-policies.sh"
echo ""
echo "  3. Run policy tests:"
echo "     cd ../policy-tests && ./run-tests.sh"
echo ""
