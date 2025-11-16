#!/bin/bash

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test metrics
TESTS_RUN=0
TESTS_DETECTED=0
TESTS_REMEDIATED=0
DETECTION_TIMES=()

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Run single chaos test
run_test() {
    local test_file=$1
    local test_name=$(basename "$test_file" .yaml)

    log_info "============================================"
    log_info "Running: $test_name"
    log_info "============================================"

    # Deploy attack pod
    log_info "Deploying attack scenario..."
    kubectl apply -f "$test_file"

    # Wait for pod to start
    local pod_name
    pod_name=$(kubectl get pods -l "test-type=$(echo $test_name | sed 's/test-//')" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$pod_name" ]; then
        log_error "Failed to find test pod"
        return 1
    fi

    log_info "Test pod: $pod_name"

    # Monitor for Falco alerts (wait up to 30 seconds)
    log_info "Monitoring for Falco alerts..."
    local start_time=$(date +%s)
    local alert_detected=false
    local detection_time=0

    for i in {1..30}; do
        # Check Falco logs
        if kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50 2>/dev/null | grep -q "$pod_name"; then
            alert_detected=true
            detection_time=$(($(date +%s) - start_time))
            log_success "Alert detected in ${detection_time}s"
            DETECTION_TIMES+=($detection_time)
            ((TESTS_DETECTED++))
            break
        fi
        sleep 1
    done

    if [ "$alert_detected" = false ]; then
        log_warning "No alert detected within 30 seconds"
    fi

    # Check for remediation (NetworkPolicy creation)
    log_info "Checking for automated remediation..."
    sleep 5
    if kubectl get networkpolicy -n default | grep -q "isolate-$pod_name"; then
        log_success "Pod isolated via NetworkPolicy"
        ((TESTS_REMEDIATED++))
    else
        log_warning "No isolation NetworkPolicy found"
    fi

    # Cleanup
    log_info "Cleaning up test resources..."
    kubectl delete -f "$test_file" --ignore-not-found=true
    kubectl delete networkpolicy -n default -l test=chaos --ignore-not-found=true

    ((TESTS_RUN++))
    echo ""
}

# Generate test report
generate_report() {
    log_info "============================================"
    log_info "CHAOS ENGINEERING TEST REPORT"
    log_info "============================================"
    echo ""

    echo "Summary:"
    echo "  Tests Run: $TESTS_RUN"
    echo "  Alerts Detected: $TESTS_DETECTED"
    echo "  Remediation Successful: $TESTS_REMEDIATED"
    echo ""

    if [ ${#DETECTION_TIMES[@]} -gt 0 ]; then
        local total=0
        local max=0
        local min=999999

        for time in "${DETECTION_TIMES[@]}"; do
            total=$((total + time))
            [ $time -gt $max ] && max=$time
            [ $time -lt $min ] && min=$time
        done

        local avg=$((total / ${#DETECTION_TIMES[@]}))

        echo "Detection Time Metrics:"
        echo "  Average: ${avg}s"
        echo "  Min: ${min}s"
        echo "  Max: ${max}s"
        echo ""
    fi

    local detection_rate=0
    local remediation_rate=0

    if [ $TESTS_RUN -gt 0 ]; then
        detection_rate=$((TESTS_DETECTED * 100 / TESTS_RUN))
        remediation_rate=$((TESTS_REMEDIATED * 100 / TESTS_RUN))
    fi

    echo "Success Rates:"
    echo "  Detection Rate: ${detection_rate}%"
    echo "  Remediation Rate: ${remediation_rate}%"
    echo ""

    # Overall assessment
    if [ $detection_rate -ge 90 ] && [ $remediation_rate -ge 80 ]; then
        log_success "Platform security response: EXCELLENT"
    elif [ $detection_rate -ge 70 ] && [ $remediation_rate -ge 60 ]; then
        log_warning "Platform security response: GOOD (room for improvement)"
    else
        log_error "Platform security response: NEEDS IMPROVEMENT"
    fi

    echo ""
    log_info "Expected Metrics:"
    echo "  Detection Time: <5 seconds (actual avg: ${avg:-N/A}s)"
    echo "  Detection Rate: >95% (actual: ${detection_rate}%)"
    echo "  Remediation Rate: >90% (actual: ${remediation_rate}%)"
}

# Main execution
main() {
    log_info "AKSRPP Chaos Engineering Test Suite"
    log_info "Testing platform resilience against attacks"
    echo ""

    # Check prerequisites
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    if ! kubectl get namespace falco &> /dev/null; then
        log_warning "Falco namespace not found - alerts may not be detected"
    fi

    if ! kubectl get namespace security &> /dev/null; then
        log_warning "Security namespace not found - remediation may not work"
    fi

    log_info "Prerequisites checked"
    echo ""

    # Run all tests
    for test_file in test-*.yaml; do
        if [ -f "$test_file" ]; then
            run_test "$test_file"
        fi
    done

    # Generate report
    generate_report

    log_info "Chaos testing complete!"
}

main "$@"
