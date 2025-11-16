#!/bin/bash
# Comprehensive Policy Test Suite
# Tests all 22 OPA policies with PASS and FAIL scenarios

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test namespace
TEST_NAMESPACE="policy-test"

echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  OPA Policy Test Suite                    ║${NC}"
echo -e "${BLUE}║  Testing 22 policies with 100+ scenarios  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

# Create test namespace
echo -e "${YELLOW}Setting up test environment...${NC}"
kubectl create namespace ${TEST_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1
kubectl label namespace ${TEST_NAMESPACE} network-policy=enabled --overwrite > /dev/null 2>&1

# Create test service account
kubectl create serviceaccount test-sa -n ${TEST_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1
echo -e "${GREEN}✓ Test environment ready${NC}\n"

# Function to test a file expecting it to PASS
test_should_pass() {
    local file=$1
    local test_name=$(basename $file .yaml)

    ((TOTAL_TESTS++))

    if kubectl apply -f $file -n ${TEST_NAMESPACE} --dry-run=server > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        ((PASSED_TESTS++))
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name (expected to pass but was denied)"
        ((FAILED_TESTS++))
    fi
}

# Function to test a file expecting it to FAIL
test_should_fail() {
    local file=$1
    local test_name=$(basename $file .yaml)

    ((TOTAL_TESTS++))

    if kubectl apply -f $file -n ${TEST_NAMESPACE} --dry-run=server > /dev/null 2>&1; then
        echo -e "${RED}✗ FAIL${NC}: $test_name (expected to be denied but was allowed)"
        ((FAILED_TESTS++))
    else
        echo -e "${GREEN}✓ PASS${NC}: $test_name (correctly denied)"
        ((PASSED_TESTS++))
    fi
}

echo -e "${BLUE}Running PASS tests (should be allowed)...${NC}"
for file in test-*-pass.yaml; do
    if [ -f "$file" ]; then
        test_should_pass "$file"
    fi
done

echo ""
echo -e "${BLUE}Running FAIL tests (should be denied)...${NC}"
for file in test-*-fail.yaml; do
    if [ -f "$file" ]; then
        test_should_fail "$file"
    fi
done

# Cleanup
echo ""
echo -e "${YELLOW}Cleaning up test environment...${NC}"
kubectl delete namespace ${TEST_NAMESPACE} > /dev/null 2>&1 || true

# Summary
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Test Summary                              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""
echo "Total tests: ${TOTAL_TESTS}"
echo -e "${GREEN}Passed: ${PASSED_TESTS}${NC}"
echo -e "${RED}Failed: ${FAILED_TESTS}${NC}"
echo ""

# Calculate success rate
if [ ${TOTAL_TESTS} -gt 0 ]; then
    SUCCESS_RATE=$(awk "BEGIN {printf \"%.1f\", (${PASSED_TESTS}/${TOTAL_TESTS})*100}")
    echo "Success rate: ${SUCCESS_RATE}%"

    if [ ${FAILED_TESTS} -eq 0 ]; then
        echo -e "${GREEN}All tests passed! 🎉${NC}"
        exit 0
    else
        echo -e "${YELLOW}Some tests failed. Review policy configurations.${NC}"
        exit 1
    fi
else
    echo -e "${RED}No tests found!${NC}"
    exit 1
fi
