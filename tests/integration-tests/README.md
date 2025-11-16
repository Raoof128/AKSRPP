# Integration Tests

Integration tests verify the complete AKSRPP security platform functionality across all phases.

## Test Scenarios

### 1. End-to-End Policy Enforcement
- Deploy compliant workload → Verify admission
- Deploy non-compliant workload → Verify rejection
- Check policy audit logs

### 2. Runtime Detection & Response
- Trigger security event → Verify Falco alert
- Verify operator remediation → Check pod isolation
- Verify forensics capture

### 3. Network Policy Enforcement
- Test pod-to-pod communication
- Verify default-deny enforcement
- Test DNS resolution (should work)
- Test external access (should be blocked)

### 4. Supply Chain Integration
- Scan image for vulnerabilities
- Generate SBOM
- Verify signature enforcement

## Running Tests

```bash
cd tests/integration-tests
./run-integration-tests.sh
```

## Prerequisites

- Kubernetes cluster running
- AKSRPP platform fully deployed
- kubectl configured
- Test tools: curl, jq, python3

## Test Structure

```
integration-tests/
├── README.md                    # This file
├── run-integration-tests.sh     # Main test runner
├── test-admission-control.sh    # Phase 1 tests
├── test-runtime-security.sh     # Phase 2 tests
├── test-network-policies.sh     # Phase 3 tests
└── test-supply-chain.sh         # Supply chain tests
```

## Expected Results

All tests should pass with:
- Policy enforcement: 100% non-compliant pods blocked
- Detection time: <5 seconds
- Remediation time: <10 seconds
- Network isolation: Effective

## CI/CD Integration

These tests run automatically on:
- Pull requests to main
- Nightly builds
- Pre-release validation
