# Chaos Engineering Tests

This directory contains chaos engineering tests to validate the resilience and security response capabilities of the AKSRPP platform.

## Purpose

Chaos engineering tests simulate real-world attack scenarios to verify:
- Detection accuracy (true positives)
- Response time (MTTR)
- Platform stability under attack
- False positive rates
- Recovery capabilities

## Test Scenarios

### 1. Container Escape Attempts

**File**: `test-container-escape.yaml`

Simulates container breakout techniques:
- /proc filesystem access
- cgroup manipulation
- Device mounting
- nsenter usage

**Expected Behavior**:
- Falco alert within <5 seconds
- Remediation operator isolates pod
- Forensics captured
- PagerDuty incident created

### 2. Privilege Escalation

**File**: `test-privilege-escalation.yaml`

Simulates privilege escalation attacks:
- SUID binary execution
- Capability abuse
- ServiceAccount token theft
- Kubernetes API privilege escalation

**Expected Behavior**:
- Falco alert triggered
- Pod isolated
- Security team notified via Slack

### 3. Reverse Shell Establishment

**File**: `test-reverse-shell.yaml`

Simulates C2 communication:
- netcat reverse shells
- bash/python shells
- Encrypted tunnels

**Expected Behavior**:
- Immediate detection (<3s)
- Network isolation
- Process tree captured

### 4. Cryptocurrency Mining

**File**: `test-cryptominer.yaml`

Simulates cryptominer deployment:
- xmrig execution
- High CPU usage patterns
- Pool connection attempts

**Expected Behavior**:
- Mining process detected
- Pod terminated
- Resource metrics logged

### 5. Policy Bypass Attempts

**File**: `test-policy-bypass.yaml`

Tests admission control resilience:
- Privileged container deployment
- Host namespace access
- Latest tag usage
- Missing security context

**Expected Behavior**:
- All attempts blocked by OPA Gatekeeper
- Audit log entries created
- Zero successful bypasses

## Running Tests

### Individual Test

```bash
# Deploy attack pod
kubectl apply -f test-container-escape.yaml

# Monitor for alerts (in separate terminal)
kubectl logs -n security -l app=remediation-operator -f

# Check Falco alerts
kubectl logs -n falco -l app.kubernetes.io/name=falco | grep -i "critical"

# Verify isolation
kubectl get networkpolicy -n default

# Clean up
kubectl delete -f test-container-escape.yaml
```

### Full Test Suite

```bash
./run-chaos-tests.sh
```

This script:
1. Deploys each attack scenario
2. Waits for detection
3. Verifies remediation
4. Collects metrics
5. Generates report

## Metrics Collected

- **Detection Time**: Time from attack start to first alert
- **Remediation Time**: Time from alert to pod isolation
- **MTTR**: Mean time to full recovery
- **False Positives**: Legitimate operations flagged as threats
- **False Negatives**: Attacks not detected

## Expected Results

| Test Scenario | Detection Time | Remediation Time | Success Rate |
|---------------|----------------|------------------|--------------|
| Container Escape | <5s | <10s | 100% |
| Privilege Escalation | <5s | <10s | 100% |
| Reverse Shell | <3s | <8s | 100% |
| Cryptominer | <10s | <15s | 100% |
| Policy Bypass | Immediate | N/A (blocked) | 100% |

## Safety Considerations

⚠️ **WARNING**: These tests simulate real attacks. Only run in:
- Isolated test clusters
- Non-production environments
- Clusters you own or have permission to test

**DO NOT** run these tests on:
- Production clusters
- Shared environments
- Clusters without proper isolation

## Troubleshooting

### Test Not Detected

1. Check Falco is running: `kubectl get pods -n falco`
2. Verify rules are loaded: `kubectl logs -n falco -l app.kubernetes.io/name=falco | grep "Rules loaded"`
3. Check operator logs: `kubectl logs -n security -l app=remediation-operator`

### False Positives

1. Review Falco rule conditions
2. Add application to exemption list
3. Tune rule sensitivity
4. Update rule with more specific conditions

### Operator Not Responding

1. Check operator health: `kubectl get pods -n security`
2. Review operator logs for errors
3. Verify RBAC permissions
4. Check network connectivity to Kubernetes API

## Continuous Testing

Integrate with CI/CD:

```yaml
# .github/workflows/chaos-tests.yml
name: Weekly Chaos Tests
on:
  schedule:
    - cron: '0 2 * * 0'  # Every Sunday at 2 AM
jobs:
  chaos:
    runs-on: ubuntu-latest
    steps:
      - name: Setup cluster
        run: ./scripts/setup-cluster.sh
      - name: Deploy platform
        run: ./scripts/deploy-all.sh
      - name: Run chaos tests
        run: cd tests/chaos-engineering && ./run-chaos-tests.sh
      - name: Upload results
        uses: actions/upload-artifact@v3
        with:
          name: chaos-test-results
          path: tests/chaos-engineering/results/
```

## References

- [Falco Rules Documentation](https://falco.org/docs/rules/)
- [MITRE ATT&CK Framework](https://attack.mitre.org/)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)
- [Chaos Engineering Principles](https://principlesofchaos.org/)
