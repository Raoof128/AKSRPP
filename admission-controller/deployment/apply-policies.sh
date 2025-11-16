#!/bin/bash
# Apply all OPA policies to Kubernetes cluster
# Creates ConstraintTemplates and Constraints

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

POLICY_DIR="../opa-policies"

echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Applying OPA Security Policies           ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""

# Check if Gatekeeper is installed
if ! kubectl get deployment -n gatekeeper-system gatekeeper-controller-manager &> /dev/null; then
    echo -e "${RED}✗ Gatekeeper not found. Run install-gatekeeper.sh first.${NC}"
    exit 1
fi

echo -e "${YELLOW}[1/3]${NC} Applying ConstraintTemplates..."

# Apply all constraint templates
template_count=0
for template in ${POLICY_DIR}/*-template.yaml; do
    if [ -f "$template" ]; then
        echo -e "  Applying: $(basename $template)"
        kubectl apply -f "$template"
        ((template_count++))
    fi
done

echo -e "${GREEN}✓ Applied ${template_count} ConstraintTemplates${NC}"

# Wait for templates to be ready
echo -e "${YELLOW}[2/3]${NC} Waiting for ConstraintTemplates to be ready..."
sleep 5

# Apply all constraints
echo -e "${YELLOW}[3/3]${NC} Applying Constraints..."

constraint_count=0
for constraint in ${POLICY_DIR}/*-constraint.yaml; do
    if [ -f "$constraint" ]; then
        echo -e "  Applying: $(basename $constraint)"
        kubectl apply -f "$constraint"
        ((constraint_count++))
    fi
done

echo -e "${GREEN}✓ Applied ${constraint_count} Constraints${NC}"
echo ""
echo -e "${GREEN}Policy deployment complete!${NC}"
echo ""
echo "Verify with: ./verify-policies.sh"
echo "Test with: kubectl apply -f ../policy-tests/"
