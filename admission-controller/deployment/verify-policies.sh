#!/bin/bash
# Verify OPA policies are active and working
# Checks ConstraintTemplates and Constraints status

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  OPA Policy Verification                   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""

# Check Gatekeeper health
echo -e "${YELLOW}[1/4]${NC} Checking Gatekeeper status..."

if ! kubectl get deployment -n gatekeeper-system gatekeeper-controller-manager &> /dev/null; then
    echo -e "${RED}✗ Gatekeeper not found${NC}"
    exit 1
fi

ready_replicas=$(kubectl get deployment -n gatekeeper-system gatekeeper-controller-manager -o jsonpath='{.status.readyReplicas}')
desired_replicas=$(kubectl get deployment -n gatekeeper-system gatekeeper-controller-manager -o jsonpath='{.spec.replicas}')

if [ "$ready_replicas" == "$desired_replicas" ]; then
    echo -e "${GREEN}✓ Gatekeeper healthy (${ready_replicas}/${desired_replicas} replicas ready)${NC}"
else
    echo -e "${RED}✗ Gatekeeper unhealthy (${ready_replicas}/${desired_replicas} replicas ready)${NC}"
    exit 1
fi

# Check ConstraintTemplates
echo -e "${YELLOW}[2/4]${NC} Checking ConstraintTemplates..."

templates=$(kubectl get constrainttemplates --no-headers 2>/dev/null | wc -l)
if [ "$templates" -gt 0 ]; then
    echo -e "${GREEN}✓ Found ${templates} ConstraintTemplates:${NC}"
    kubectl get constrainttemplates -o custom-columns=NAME:.metadata.name,CREATED:.metadata.creationTimestamp --no-headers | \
        while read -r line; do
            echo -e "  ${BLUE}→${NC} $line"
        done
else
    echo -e "${RED}✗ No ConstraintTemplates found${NC}"
    exit 1
fi

# Check Constraints
echo -e "${YELLOW}[3/4]${NC} Checking Constraints..."

constraint_types=$(kubectl get constrainttemplates -o jsonpath='{.items[*].metadata.name}')
total_constraints=0

for ct in $constraint_types; do
    count=$(kubectl get ${ct} --all-namespaces --no-headers 2>/dev/null | wc -l)
    if [ "$count" -gt 0 ]; then
        echo -e "${GREEN}  ✓ ${ct}: ${count} instance(s)${NC}"
        ((total_constraints+=count))
    fi
done

if [ "$total_constraints" -gt 0 ]; then
    echo -e "${GREEN}✓ Total active constraints: ${total_constraints}${NC}"
else
    echo -e "${YELLOW}⚠ No constraints applied yet${NC}"
fi

# Check recent audit violations
echo -e "${YELLOW}[4/4]${NC} Checking recent policy violations..."

violations=0
for ct in $constraint_types; do
    ct_violations=$(kubectl get ${ct} --all-namespaces -o json 2>/dev/null | \
        jq -r '.items[].status.totalViolations // 0' | \
        awk '{sum+=$1} END {print sum}')

    if [ ! -z "$ct_violations" ] && [ "$ct_violations" -gt 0 ]; then
        violations=$((violations + ct_violations))
    fi
done

if [ "$violations" -gt 0 ]; then
    echo -e "${YELLOW}⚠ Found ${violations} policy violation(s) in cluster${NC}"
    echo -e "  View details: kubectl get constraints --all-namespaces"
else
    echo -e "${GREEN}✓ No policy violations detected${NC}"
fi

# Summary
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Verification Complete                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo "Summary:"
echo "  Gatekeeper: Healthy"
echo "  ConstraintTemplates: ${templates}"
echo "  Active Constraints: ${total_constraints}"
echo "  Policy Violations: ${violations}"
echo ""

if [ "$total_constraints" -eq 0 ]; then
    echo -e "${YELLOW}Next step: Apply constraints with ./apply-policies.sh${NC}"
else
    echo -e "${GREEN}Policies are active and enforcing!${NC}"
fi
