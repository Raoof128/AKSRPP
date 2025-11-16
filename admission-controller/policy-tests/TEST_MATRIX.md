# OPA Policy Test Matrix

This document outlines all 100+ test scenarios for the 22 security policies.

## Test Coverage Summary

| Policy ID | Policy Name | PASS Tests | FAIL Tests | Total Tests |
|-----------|-------------|------------|------------|-------------|
| 01 | Deny Privileged Containers | 5 | 8 | 13 |
| 02 | Require Run As Non-Root | 3 | 6 | 9 |
| 03 | Require Read-Only RootFS | 2 | 4 | 6 |
| 04 | Allowed Image Registries | 4 | 5 | 9 |
| 05 | Block Latest Tag | 3 | 6 | 9 |
| 06 | Drop All Capabilities | 3 | 4 | 7 |
| 07 | Require Resource Limits | 2 | 6 | 8 |
| 08 | Deny Host Namespaces | 2 | 6 | 8 |
| 09 | Deny Host Path | 2 | 4 | 6 |
| 10 | Require NetworkPolicy | 2 | 3 | 5 |
| 11 | Require Seccomp | 2 | 3 | 5 |
| 12 | Block Cluster Admin | 1 | 4 | 5 |
| 13 | Deny Default ServiceAccount | 2 | 3 | 5 |
| 14 | Deny Host Ports | 2 | 3 | 5 |
| 15 | Deny Privilege Escalation | 2 | 3 | 5 |
| 16 | Require Labels | 3 | 4 | 7 |
| 17 | Block NodePort | 2 | 3 | 5 |
| 18 | Block Automount SA Token | 2 | 3 | 5 |
| 19 | Require AppArmor | 1 | 2 | 3 |
| 20 | Require Ingress HTTPS | 2 | 4 | 6 |
| 21 | Block Pod Exec | 1 | 2 | 3 |
| 22 | Deny External IPs | 2 | 3 | 5 |
| **TOTAL** | | **48** | **85** | **133** |

## Detailed Test Scenarios

### Policy 01: Deny Privileged Containers

#### PASS Tests (5)
- ✅ Pod with non-privileged container
- ✅ Deployment with non-privileged containers
- ✅ StatefulSet with non-privileged containers
- ✅ DaemonSet with non-privileged init containers
- ✅ Multi-container pod (all non-privileged)

#### FAIL Tests (8)
- ❌ Pod with privileged: true
- ❌ Deployment with privileged container
- ❌ StatefulSet with privileged init container
- ❌ DaemonSet with privileged sidecar
- ❌ Multi-container pod (one privileged)
- ❌ Job with privileged container
- ❌ CronJob with privileged container
- ❌ Pod with exempt image but privileged

---

### Policy 02: Require Run As Non-Root

#### PASS Tests (3)
- ✅ Pod with runAsNonRoot: true and runAsUser: 1000
- ✅ Deployment with pod-level runAsNonRoot
- ✅ StatefulSet with container-level runAsNonRoot

#### FAIL Tests (6)
- ❌ Pod with runAsUser: 0
- ❌ Pod with runAsNonRoot: false
- ❌ Pod missing runAsNonRoot
- ❌ Deployment with root user
- ❌ Container-level override to root
- ❌ Init container running as root

---

### Policy 03: Require Read-Only RootFS

#### PASS Tests (2)
- ✅ Pod with readOnlyRootFilesystem: true
- ✅ Deployment with all containers having read-only FS

#### FAIL Tests (4)
- ❌ Pod missing readOnlyRootFilesystem
- ❌ Pod with readOnlyRootFilesystem: false
- ❌ Deployment with one writable container
- ❌ Init container with writable filesystem

---

### Policy 04: Allowed Image Registries

#### PASS Tests (4)
- ✅ Image from docker.io
- ✅ Image from gcr.io
- ✅ Image from ghcr.io
- ✅ Image from private registry (configured)

#### FAIL Tests (5)
- ❌ Image from unknown registry
- ❌ Image from public but unapproved registry
- ❌ Image from localhost
- ❌ Multi-container with one bad registry
- ❌ Init container from disallowed registry

---

### Policy 05: Block Latest Tag

#### PASS Tests (3)
- ✅ Image with semantic version (v1.2.3)
- ✅ Image with SHA digest
- ✅ Image with build number tag

#### FAIL Tests (6)
- ❌ Image with :latest tag
- ❌ Image with no tag (nginx)
- ❌ Image with :stable tag (treated as mutable)
- ❌ Multi-container with one :latest
- ❌ Init container with :latest
- ❌ Image name only (no tag, no digest)

---

### Policy 06: Drop All Capabilities

#### PASS Tests (3)
- ✅ Container dropping ALL capabilities
- ✅ Container dropping ALL and adding NET_BIND_SERVICE
- ✅ All containers in pod drop ALL

#### FAIL Tests (4)
- ❌ Container not dropping ALL
- ❌ Container dropping only specific capabilities
- ❌ Container adding disallowed capability
- ❌ One container in pod missing drop ALL

---

### Policy 07: Require Resource Limits

#### PASS Tests (2)
- ✅ Container with CPU and memory requests+limits
- ✅ All containers in pod have resources

#### FAIL Tests (6)
- ❌ Missing CPU limits
- ❌ Missing memory limits
- ❌ Missing CPU requests
- ❌ Missing memory requests
- ❌ One container missing resources
- ❌ Init container missing resources

---

### Policy 08: Deny Host Namespaces

#### PASS Tests (2)
- ✅ Pod without host namespaces
- ✅ Deployment with all host* set to false

#### FAIL Tests (6)
- ❌ Pod with hostNetwork: true
- ❌ Pod with hostPID: true
- ❌ Pod with hostIPC: true
- ❌ Pod with multiple host namespaces
- ❌ Deployment with hostNetwork
- ❌ DaemonSet with hostPID

---

### Policy 09: Deny Host Path

#### PASS Tests (2)
- ✅ Pod with emptyDir volumes
- ✅ Pod with configMap and secret volumes

#### FAIL Tests (4)
- ❌ Pod with hostPath volume
- ❌ Deployment with hostPath
- ❌ Pod with multiple volumes (one hostPath)
- ❌ StatefulSet with hostPath

---

### Policy 10: Require NetworkPolicy

#### PASS Tests (2)
- ✅ Namespace with network-policy: enabled label
- ✅ Namespace with custom NetworkPolicy

#### FAIL Tests (3)
- ❌ Namespace without network-policy label
- ❌ Namespace with network-policy: disabled
- ❌ New namespace missing label

---

### Policy 11: Require Seccomp

#### PASS Tests (2)
- ✅ Pod with RuntimeDefault seccomp
- ✅ Pod with Localhost seccomp profile

#### FAIL Tests (3)
- ❌ Pod missing seccomp profile
- ❌ Pod with Unconfined seccomp
- ❌ Container-level seccomp override to Unconfined

---

### Policy 12: Block Cluster Admin

#### PASS Tests (1)
- ✅ RoleBinding to non-cluster-admin role

#### FAIL Tests (4)
- ❌ ClusterRoleBinding to cluster-admin
- ❌ RoleBinding to cluster-admin
- ❌ Binding to cluster-admin for non-exempt user
- ❌ Binding to cluster-admin for non-exempt group

---

### Policy 13: Deny Default ServiceAccount

#### PASS Tests (2)
- ✅ Pod with custom ServiceAccount
- ✅ Pod with SA and automountSAToken: false

#### FAIL Tests (3)
- ❌ Pod using default ServiceAccount
- ❌ Pod with no serviceAccountName (defaults to default)
- ❌ Pod with default SA and automount enabled

---

### Policy 14: Deny Host Ports

#### PASS Tests (2)
- ✅ Pod with containerPort only
- ✅ Multi-container pod without hostPort

#### FAIL Tests (3)
- ❌ Pod with hostPort
- ❌ One container using hostPort
- ❌ Deployment with hostPort

---

### Policy 15: Deny Privilege Escalation

#### PASS Tests (2)
- ✅ Pod with allowPrivilegeEscalation: false
- ✅ All containers have allowPrivilegeEscalation: false

#### FAIL Tests (3)
- ❌ Pod with allowPrivilegeEscalation: true
- ❌ Pod missing allowPrivilegeEscalation
- ❌ One container allowing privilege escalation

---

### Policy 16: Require Labels

#### PASS Tests (3)
- ✅ Pod with app, owner, environment labels
- ✅ Deployment with all required labels
- ✅ Service with required labels

#### FAIL Tests (4)
- ❌ Pod missing app label
- ❌ Pod missing owner label
- ❌ Pod missing environment label
- ❌ Pod missing multiple labels

---

### Policy 17: Block NodePort

#### PASS Tests (2)
- ✅ ClusterIP service
- ✅ LoadBalancer service

#### FAIL Tests (3)
- ❌ NodePort service
- ❌ Service changing from ClusterIP to NodePort
- ❌ Multi-port service with NodePort

---

### Policy 18: Block Automount SA Token

#### PASS Tests (2)
- ✅ Pod with automountServiceAccountToken: false
- ✅ Deployment with automount disabled

#### FAIL Tests (3)
- ❌ Pod with automountServiceAccountToken: true
- ❌ Pod missing automountServiceAccountToken
- ❌ Pod with default SA and automount

---

### Policy 19: Require AppArmor

#### PASS Tests (1)
- ✅ Pod with AppArmor annotation

#### FAIL Tests (2)
- ❌ Pod without AppArmor annotation
- ❌ Pod with disallowed AppArmor profile

---

### Policy 20: Require Ingress HTTPS

#### PASS Tests (2)
- ✅ Ingress with TLS configured
- ✅ Ingress with SSL redirect annotation

#### FAIL Tests (4)
- ❌ Ingress without TLS
- ❌ Ingress without SSL redirect
- ❌ Ingress missing both TLS and annotation
- ❌ Ingress with empty TLS array

---

### Policy 21: Block Pod Exec

#### PASS Tests (1)
- ✅ Exec in non-production namespace

#### FAIL Tests (2)
- ❌ Exec in production namespace
- ❌ Exec in prod namespace

---

### Policy 22: Deny External IPs

#### PASS Tests (2)
- ✅ Service without externalIPs
- ✅ Service with LoadBalancer (no externalIPs)

#### FAIL Tests (3)
- ❌ Service with externalIPs
- ❌ Service with multiple externalIPs
- ❌ Service adding externalIPs on update

---

## Running Tests

### Quick Start
```bash
cd admission-controller/policy-tests
./run-tests.sh
```

### Run Specific Test
```bash
kubectl apply -f test-01-privileged-fail.yaml -n policy-test --dry-run=server
```

### Expected Results
- **PASS tests**: Should be admitted (kubectl apply succeeds)
- **FAIL tests**: Should be denied (kubectl apply fails with policy violation)

## Test Metrics

- **Total Test Cases**: 133
- **Coverage**: 100% of 22 policies
- **Automation**: Fully automated via run-tests.sh
- **Execution Time**: ~2-3 minutes for full suite
- **Success Criteria**: 100% pass rate (all PASS tests succeed, all FAIL tests blocked)

## Continuous Integration

The test suite is designed for CI/CD integration:

```yaml
# .github/workflows/policy-tests.yml
- name: Run OPA Policy Tests
  run: |
    cd admission-controller/policy-tests
    ./run-tests.sh
```

## Test Maintenance

When adding new policies:
1. Create policy template and constraint
2. Add PASS test scenarios (minimum 2)
3. Add FAIL test scenarios (minimum 3)
4. Update this matrix
5. Run full test suite
6. Verify 100% pass rate
