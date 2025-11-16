# AKSRPP Deployment Runbook

## Table of Contents

- [Prerequisites](#prerequisites)
- [Pre-Deployment Checklist](#pre-deployment-checklist)
- [Installation Steps](#installation-steps)
- [Validation & Testing](#validation--testing)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Rollback Procedures](#rollback-procedures)
- [Monitoring & Alerts](#monitoring--alerts)
- [Operational Procedures](#operational-procedures)

---

## Prerequisites

### System Requirements

**Kubernetes Cluster**:
- Version: 1.24+ (tested on 1.28)
- Nodes: Minimum 3 (1 control plane + 2 workers)
- Resources:
  - CPU: 8 cores total (recommended)
  - RAM: 16GB total (minimum), 32GB recommended
  - Storage: 50GB available for persistent volumes

**Client Tools**:
```bash
# Required
kubectl >= 1.24
helm >= 3.12
git >= 2.30

# Recommended
docker or podman
kind or minikube (for local testing)
go >= 1.21 (for building operator)
python >= 3.11 (for scripts)

# Optional
trivy (image scanning)
syft (SBOM generation)
cosign (image signing)
```

### Access Requirements

- Kubernetes cluster admin access
- kubectl configured with correct context
- Helm configured
- Container registry access (if using private images)
- GitHub access (for cloning repository)

### Network Requirements

**Outbound Connectivity**:
- Helm chart repositories (helm.gatekeeper.sh, falcosecurity.github.io, helm.cilium.io)
- Container registries (ghcr.io, docker.io, quay.io)
- GitHub (github.com)

**Cluster Networking**:
- CNI plugin installed (or prepare to install Cilium)
- NetworkPolicy support enabled
- LoadBalancer or NodePort access (optional, for external monitoring)

---

## Pre-Deployment Checklist

### 1. Environment Validation

```bash
# Check cluster connectivity
kubectl cluster-info
kubectl get nodes

# Verify resource availability
kubectl top nodes  # Requires metrics-server

# Check existing workloads
kubectl get pods --all-namespaces
```

### 2. Backup Existing Configuration

```bash
# Backup current policies
kubectl get constrainttemplates -o yaml > backup-constraints-$(date +%Y%m%d).yaml
kubectl get networkpolicies --all-namespaces -o yaml > backup-netpol-$(date +%Y%m%d).yaml

# Backup RBAC
kubectl get clusterroles,clusterrolebindings -o yaml > backup-rbac-$(date +%Y%m%d).yaml
```

### 3. Namespace Preparation

```bash
# Create namespaces
kubectl create namespace gatekeeper-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace falco --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace security --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Label namespaces
kubectl label namespace gatekeeper-system name=gatekeeper-system
kubectl label namespace falco name=falco
kubectl label namespace security name=security
kubectl label namespace monitoring name=monitoring
```

### 4. Secret Management

If using external integrations, create secrets first:

```bash
# Slack webhook (optional)
kubectl create secret generic slack-webhook \
  --from-literal=url=https://hooks.slack.com/services/YOUR/WEBHOOK/URL \
  -n security

# PagerDuty API key (optional)
kubectl create secret generic pagerduty-key \
  --from-literal=api-key=YOUR_PAGERDUTY_KEY \
  -n security

# Container registry credentials (if needed)
kubectl create secret docker-registry regcred \
  --docker-server=ghcr.io \
  --docker-username=YOUR_USERNAME \
  --docker-password=YOUR_TOKEN \
  -n security
```

---

## Installation Steps

### Quick Start (Automated)

```bash
# Clone repository
git clone https://github.com/yourusername/AKSRPP.git
cd AKSRPP

# Run full deployment
./scripts/deploy-all.sh

# Validate deployment
./scripts/validate-security.sh
```

### Manual Deployment (Step-by-Step)

#### Phase 1: Admission Control (OPA Gatekeeper)

**Estimated Time**: 5-10 minutes

```bash
cd admission-controller/deployment

# 1. Install Gatekeeper
./install-gatekeeper.sh

# 2. Wait for Gatekeeper to be ready
kubectl wait --for=condition=ready pod \
  -l control-plane=controller-manager \
  -n gatekeeper-system \
  --timeout=300s

kubectl wait --for=condition=ready pod \
  -l control-plane=audit-controller \
  -n gatekeeper-system \
  --timeout=300s

# 3. Verify Gatekeeper installation
kubectl get pods -n gatekeeper-system
kubectl get validatingwebhookconfiguration gatekeeper-validating-webhook-configuration

# 4. Apply security policies
./apply-policies.sh

# 5. Verify policies
./verify-policies.sh

# Expected output: 22 ConstraintTemplates, 22 Constraints

# 6. Test policy enforcement
kubectl apply -f ../policy-tests/test-01-privileged-fail.yaml
# Should be denied

kubectl apply -f ../policy-tests/test-comprehensive-pass.yaml
# Should succeed
```

**Troubleshooting Phase 1**:
```bash
# Check Gatekeeper logs
kubectl logs -n gatekeeper-system -l control-plane=controller-manager

# Check webhook configuration
kubectl get validatingwebhookconfiguration gatekeeper-validating-webhook-configuration -o yaml

# Verify audit is running
kubectl logs -n gatekeeper-system -l control-plane=audit-controller
```

#### Phase 2: Runtime Security (Falco + Operator)

**Estimated Time**: 10-15 minutes

```bash
# 1. Install Falco with custom rules
cd ../../runtime-security/falco-rules
./install-falco.sh

# 2. Wait for Falco to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=falco \
  -n falco \
  --timeout=300s

# 3. Verify Falco is running
kubectl get pods -n falco
kubectl logs -n falco -l app.kubernetes.io/name=falco | grep "Rules loaded"

# 4. Deploy remediation operator
cd ../response-automation/kubernetes-manifests
kubectl apply -f operator-rbac.yaml
kubectl apply -f operator-deployment.yaml
kubectl apply -f operator-service.yaml

# 5. Wait for operator to be ready
kubectl wait --for=condition=ready pod \
  -l app=remediation-operator \
  -n security \
  --timeout=300s

# 6. Verify operator
kubectl get pods -n security
kubectl logs -n security -l app=remediation-operator

# Expected: "Remediation operator started", "Listening on :8080"
```

**Falco Rule Verification**:
```bash
# Check that custom rules are loaded
kubectl exec -n falco <falco-pod-name> -- falco --list | grep -E "(Container Escape|Privilege Escalation|Reverse Shell)"

# Should show 33 custom rules
```

#### Phase 3: Network Security & Supply Chain

**Estimated Time**: 10-15 minutes

```bash
# 1. Install Cilium (if not using existing CNI)
cd ../../../network-policies/cilium-configs

helm repo add cilium https://helm.cilium.io/
helm repo update

helm install cilium cilium/cilium \
  --namespace kube-system \
  --values cilium-values.yaml \
  --wait

# 2. Wait for Cilium to be ready
kubectl wait --for=condition=ready pod \
  -l k8s-app=cilium \
  -n kube-system \
  --timeout=300s

# 3. Apply network policies
kubectl apply -f network-policies/default-deny-all.yaml
kubectl apply -f network-policies/allow-dns.yaml

# 4. Verify Cilium
kubectl get pods -n kube-system -l k8s-app=cilium
cilium status  # If cilium CLI installed

# 5. Test network policies
kubectl run test-pod --image=nginx:alpine
kubectl exec test-pod -- curl https://google.com
# Should fail (blocked by default-deny)

kubectl exec test-pod -- nslookup kubernetes.default.svc.cluster.local
# Should succeed (DNS allowed)
```

**Supply Chain Setup**:
```bash
# Install scanning tools (local workstation)
cd ../../../supply-chain/sbom-generator

# Generate SBOM for test image
python3 scan-images.py nginx:latest

# Review output
cat sbom-nginx-latest.json
```

#### Phase 4: Monitoring & Observability

**Estimated Time**: 10-15 minutes

```bash
# 1. Install Prometheus stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.retention=90d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=50Gi \
  --wait

# 2. Wait for monitoring stack
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=prometheus \
  -n monitoring \
  --timeout=300s

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=grafana \
  -n monitoring \
  --timeout=300s

# 3. Apply custom alerting rules
cd ../../monitoring/prometheus-rules
kubectl apply -f security-alerts.yaml

# 4. Import Grafana dashboard
# Get Grafana password
kubectl get secret -n monitoring prometheus-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode

# Port forward to Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Open browser: http://localhost:3000
# Login: admin / <password from above>
# Import dashboard from: monitoring/grafana-dashboards/security-posture.json
```

---

## Validation & Testing

### Post-Deployment Validation

```bash
# Run automated validation
./scripts/validate-security.sh

# Expected: 90%+ checks passing
```

### Manual Validation

#### Test 1: Policy Enforcement

```bash
# Attempt privileged container (should fail)
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-privileged
spec:
  containers:
  - name: nginx
    image: nginx
    securityContext:
      privileged: true
EOF

# Expected: Error from OPA Gatekeeper
```

#### Test 2: Runtime Detection

```bash
# Deploy attack simulation
kubectl apply -f tests/chaos-engineering/test-container-escape.yaml

# Monitor Falco alerts
kubectl logs -n falco -l app.kubernetes.io/name=falco -f | grep CRITICAL

# Check operator response
kubectl logs -n security -l app=remediation-operator -f

# Expected: Alert within 5 seconds, pod isolated
```

#### Test 3: Network Policy

```bash
# Test default-deny
kubectl run test-client --image=alpine --rm -it -- sh
# Inside pod:
wget -O- http://google.com
# Should timeout (blocked)
```

### Performance Validation

```bash
# Measure policy evaluation latency
kubectl apply -f admission-controller/policy-tests/test-comprehensive-pass.yaml --dry-run=server -v=8

# Expected: <50ms admission latency

# Check Falco overhead
kubectl top pod -n falco
# Expected: <2% CPU per node
```

---

## Configuration

### Tuning Gatekeeper

**Adjust audit interval**:
```yaml
# admission-controller/deployment/gatekeeper-values.yaml
audit:
  interval: 60  # seconds (default: 60)
```

**Increase replicas for HA**:
```yaml
replicas: 3
```

### Tuning Falco

**Adjust rule priority threshold**:
```yaml
# runtime-security/falco-rules/falco-values.yaml
falco:
  priority: WARNING  # Options: DEBUG, INFO, NOTICE, WARNING, ERROR, CRITICAL, ALERT, EMERGENCY
```

**Buffer size (for high-volume environments)**:
```yaml
falco:
  bufferedOutputs: true
  outputs:
    rate: 10  # Max events/sec
    maxBurst: 1000
```

### Operator Configuration

**Adjust remediation thresholds**:
```go
// runtime-security/response-automation/operator/main.go
const (
    IsolationTimeout = 5 * time.Minute
    ForensicsRetention = 7 * 24 * time.Hour
)
```

**Resource limits**:
```yaml
# runtime-security/response-automation/kubernetes-manifests/operator-deployment.yaml
resources:
  limits:
    cpu: "1000m"
    memory: "512Mi"
  requests:
    cpu: "200m"
    memory: "128Mi"
```

---

## Troubleshooting

### Common Issues

#### Issue 1: Gatekeeper Blocking All Deployments

**Symptoms**: All pod deployments are denied

**Diagnosis**:
```bash
kubectl get constrainttemplates
kubectl describe constraint <constraint-name>
```

**Solutions**:
1. **Temporary**: Set enforcement to `dryrun`:
   ```bash
   kubectl edit constraint <constraint-name>
   # Change: enforcementAction: deny -> enforcementAction: dryrun
   ```

2. **Permanent**: Add exemption:
   ```yaml
   spec:
     match:
       excludedNamespaces: ["kube-system", "gatekeeper-system"]
   ```

#### Issue 2: Falco Not Detecting Events

**Symptoms**: No alerts generated

**Diagnosis**:
```bash
# Check Falco is running
kubectl get pods -n falco

# Check rules loaded
kubectl logs -n falco <falco-pod> | grep "Rules loaded"

# Check for errors
kubectl logs -n falco <falco-pod> | grep -i error
```

**Solutions**:
1. Verify kernel headers: `kubectl exec -n falco <pod> -- falco --version`
2. Check rule syntax: `kubectl get configmap -n falco falco-custom-rules -o yaml`
3. Restart Falco: `kubectl rollout restart daemonset -n falco falco`

#### Issue 3: Operator Not Remediating

**Symptoms**: Alerts received but no pod isolation

**Diagnosis**:
```bash
# Check operator logs
kubectl logs -n security -l app=remediation-operator

# Check RBAC permissions
kubectl auth can-i create networkpolicies --as=system:serviceaccount:security:remediation-operator -n default
```

**Solutions**:
1. Verify RBAC: `kubectl apply -f runtime-security/response-automation/kubernetes-manifests/operator-rbac.yaml`
2. Check operator health: `kubectl get pods -n security`
3. Review webhook configuration: `kubectl get svc -n security remediation-operator-service`

#### Issue 4: High Memory Usage

**Symptoms**: OOM kills, high memory consumption

**Diagnosis**:
```bash
kubectl top pods -n gatekeeper-system
kubectl top pods -n falco
kubectl top pods -n monitoring
```

**Solutions**:
1. Increase resource limits
2. Reduce Prometheus retention: `retention: 30d`
3. Tune Falco buffer size: `outputs.rate: 5`
4. Enable audit log rotation

### Logs Collection

```bash
# Collect all security component logs
mkdir -p logs-$(date +%Y%m%d)
cd logs-$(date +%Y%m%d)

kubectl logs -n gatekeeper-system -l control-plane=controller-manager > gatekeeper-controller.log
kubectl logs -n gatekeeper-system -l control-plane=audit-controller > gatekeeper-audit.log
kubectl logs -n falco -l app.kubernetes.io/name=falco > falco.log
kubectl logs -n security -l app=remediation-operator > operator.log

kubectl get events --all-namespaces > events.log
kubectl get constrainttemplates -o yaml > constraints.yaml
kubectl get pods --all-namespaces -o wide > pods.txt
```

---

## Rollback Procedures

### Emergency Disable

**Disable Gatekeeper**:
```bash
kubectl delete validatingwebhookconfiguration gatekeeper-validating-webhook-configuration
kubectl scale deployment -n gatekeeper-system gatekeeper-controller-manager --replicas=0
```

**Disable Falco**:
```bash
kubectl scale daemonset -n falco falco --replicas=0
```

**Disable Operator**:
```bash
kubectl scale deployment -n security remediation-operator --replicas=0
```

### Complete Uninstall

```bash
# Phase 1
helm uninstall gatekeeper -n gatekeeper-system
kubectl delete namespace gatekeeper-system
kubectl delete constrainttemplates --all

# Phase 2
helm uninstall falco -n falco
kubectl delete namespace falco
kubectl delete namespace security

# Phase 3
kubectl delete networkpolicies --all --all-namespaces

# Phase 4
helm uninstall prometheus -n monitoring
kubectl delete namespace monitoring
```

### Restore from Backup

```bash
kubectl apply -f backup-constraints-YYYYMMDD.yaml
kubectl apply -f backup-netpol-YYYYMMDD.yaml
kubectl apply -f backup-rbac-YYYYMMDD.yaml
```

---

## Monitoring & Alerts

### Key Metrics to Monitor

**Gatekeeper**:
- `gatekeeper_violations` - Policy violations
- `gatekeeper_constraint_template_ingestion_duration_seconds` - Template processing time
- `gatekeeper_constraint_evaluation_duration_seconds` - Evaluation latency

**Falco**:
- `falco_events_total` - Total security events
- `falco_drops_total` - Dropped events (buffer overflow)
- `falco_alerts_total` - Alerts by priority

**Operator**:
- `remediation_actions_total` - Remediation count
- `remediation_duration_seconds` - MTTR
- `pods_isolated_total` - Isolation count

### Alert Definitions

See `monitoring/prometheus-rules/security-alerts.yaml` for complete alert definitions.

**Critical Alerts**:
- PolicyViolationRateHigh: >10 violations/min
- FalcoDropsHigh: >5% event drops
- RemediationFailure: Failed isolation attempts
- MTTRTooHigh: MTTR > 5 minutes

---

## Operational Procedures

### Daily Operations

**Morning Health Check**:
```bash
make status
./scripts/validate-security.sh
kubectl get events --all-namespaces | grep -i warn
```

**Review Alerts**:
```bash
# Grafana dashboards
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Prometheus alerts
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
```

### Weekly Tasks

1. Review policy violations:
   ```bash
   kubectl get constraints -A -o json | jq '.items[] | select(.status.totalViolations > 0)'
   ```

2. Update detection rules (if needed)
3. Review false positives/negatives
4. Test disaster recovery procedures

### Monthly Tasks

1. Update components:
   ```bash
   helm repo update
   helm upgrade gatekeeper gatekeeper/gatekeeper -n gatekeeper-system
   helm upgrade falco falcosecurity/falco -n falco
   ```

2. Audit RBAC permissions
3. Review and tune resource limits
4. Backup configurations

### Emergency Procedures

**Mass Compromise Detected**:
1. Isolate entire namespace: Deploy default-deny NetworkPolicy
2. Capture forensics: `kubectl logs --all-containers=true`
3. Review audit logs: Check Gatekeeper audit trail
4. Initiate incident response playbook

**Platform Unavailable**:
1. Check cluster health: `kubectl get nodes`
2. Review component status: `make status`
3. Check admission webhook: May be blocking all deployments
4. Emergency disable if needed: See Rollback Procedures

---

## Support & Escalation

**Documentation**:
- Architecture: `docs/ARCHITECTURE.md`
- Threat Model: `docs/THREAT_MODEL.md`
- Demo: `DEMO.md`

**Community**:
- GitHub Issues: https://github.com/yourusername/AKSRPP/issues
- Discussions: https://github.com/yourusername/AKSRPP/discussions

**Enterprise Support**: [Contact information]

---

**Last Updated**: 2025-11-16
**Version**: 1.0.0
