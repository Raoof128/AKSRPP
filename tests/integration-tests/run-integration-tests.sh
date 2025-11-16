#!/bin/bash

set -euo pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    ((TESTS_PASSED++))
    ((TESTS_RUN++))
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    ((TESTS_FAILED++))
    ((TESTS_RUN++))
}

# Test 1: Admission Control
test_admission_control() {
    log_info "Testing admission control..."

    # Try to create privileged pod (should fail)
    if kubectl apply -f - <<EOF 2>&1 | grep -q "denied"; then
apiVersion: v1
kind: Pod
metadata:
  name: test-privileged-integration
spec:
  containers:
  - name: test
    image: nginx
    securityContext:
      privileged: true
EOF
        log_success "Privileged pod correctly blocked"
    else
        log_error "Privileged pod was not blocked!"
    fi
}

# Test 2: Network Policies
test_network_policies() {
    log_info "Testing network policies..."

    # Deploy test pod
    kubectl run test-netpol --image=alpine:3.18 --rm -it --restart=Never -- /bin/sh -c "echo test" &>/dev/null || true

    # Test DNS (should work)
    if kubectl run test-dns --image=alpine:3.18 --rm -it --restart=Never -- nslookup kubernetes.default 2>&1 | grep -q "Address"; then
        log_success "DNS resolution works"
    else
        log_error "DNS resolution failed"
    fi
}

# Test 3: Platform Components
test_platform_health() {
    log_info "Testing platform component health..."

    # Check Gatekeeper
    if kubectl get pods -n gatekeeper-system -l control-plane=controller-manager 2>/dev/null | grep -q "Running"; then
        log_success "Gatekeeper is running"
    else
        log_error "Gatekeeper is not running"
    fi

    # Check operator
    if kubectl get pods -n security -l app=remediation-operator 2>/dev/null | grep -q "Running"; then
        log_success "Remediation operator is running"
    else
        log_error "Remediation operator is not running"
    fi
}

# Main
main() {
    log_info "AKSRPP Integration Tests"
    log_info "========================="
    echo

    test_platform_health
    test_admission_control
    test_network_policies

    echo
    log_info "Test Summary"
    log_info "============"
    echo "Tests Run: $TESTS_RUN"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"

    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "All tests passed!"
        exit 0
    else
        log_error "Some tests failed"
        exit 1
    fi
}

main "$@"
