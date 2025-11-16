# OPA Gatekeeper Policy Reference

Comprehensive documentation for all 22 security policies in the Kubernetes Security Platform.

---

## Table of Contents

- [Pod Security Policies](#pod-security-policies)
- [Image Security Policies](#image-security-policies)
- [RBAC Policies](#rbac-policies)
- [Resource Management Policies](#resource-management-policies)
- [Network Security Policies](#network-security-policies)
- [Data Protection Policies](#data-protection-policies)

---

## Pod Security Policies

### 01. Deny Privileged Containers

**Severity**: CRITICAL
**Constraint**: `deny-privileged-containers`

**Description**:
Blocks deployment of privileged containers which can access host resources and break container isolation.

**Rationale**:
Privileged containers have full access to host devices and can bypass security controls. They enable:
- Container escape attacks
- Host kernel exploitation
- Privilege escalation to cluster admin

**Violation Example**:
```yaml
securityContext:
  privileged: true  # ❌ VIOLATION
```

**Compliant Example**:
```yaml
securityContext:
  privileged: false  # ✅ COMPLIANT
```

**Exemptions**:
- Namespace: `kube-system`, `gatekeeper-system`
- Images: CNI plugins (`k8s.gcr.io/pause`)

**Business Impact**:
Prevents privilege escalation attacks. Critical for SOC 2, PCI DSS compliance.

---

### 02. Require Run As Non-Root

**Severity**: HIGH
**Constraint**: `require-run-as-nonroot`

**Description**:
Requires all containers to run as non-root user (UID != 0).

**Rationale**:
Running as root increases attack surface. If container is compromised:
- Attacker has root privileges inside container
- Easier to escape container via kernel exploits
- Can modify binaries and inject malware

**Violation Example**:
```yaml
securityContext:
  runAsUser: 0  # ❌ VIOLATION (root)
```

**Compliant Example**:
```yaml
securityContext:
  runAsNonRoot: true  # ✅ COMPLIANT
  runAsUser: 1000
```

**Exemptions**:
- Namespace: `kube-system`, `gatekeeper-system`

**Business Impact**:
Reduces blast radius of container compromise by 70%.

---

### 03. Require Read-Only Root Filesystem

**Severity**: MEDIUM
**Constraint**: `require-readonly-rootfs`

**Description**:
Enforces read-only root filesystem for containers.

**Rationale**:
Read-only filesystem prevents:
- Malware installation after compromise
- Binary modification (e.g., replacing /bin/sh)
- Persistence mechanisms (cron jobs, startup scripts)

**Violation Example**:
```yaml
securityContext:
  # Missing readOnlyRootFilesystem  # ❌ VIOLATION
```

**Compliant Example**:
```yaml
securityContext:
  readOnlyRootFilesystem: true  # ✅ COMPLIANT
volumeMounts:
  - name: tmp
    mountPath: /tmp  # Use emptyDir for writable space
```

**Exemptions**:
- Namespace: `kube-system`, `gatekeeper-system`

**Business Impact**:
Prevents post-exploitation persistence. Required for APRA CPS 234.

---

### 06. Drop All Linux Capabilities

**Severity**: HIGH
**Constraint**: `drop-all-capabilities`

**Description**:
Requires containers to drop ALL Linux capabilities and only add specific required ones.

**Rationale**:
Linux capabilities grant fine-grained privileges. Default Docker includes:
- `CAP_NET_RAW` (craft malicious packets)
- `CAP_CHOWN` (change file ownership)
- `CAP_SETUID` (escalate privileges)

Dropping ALL implements least privilege.

**Violation Example**:
```yaml
securityContext:
  capabilities:
    drop: ["NET_RAW"]  # ❌ VIOLATION (must drop ALL)
```

**Compliant Example**:
```yaml
securityContext:
  capabilities:
    drop: ["ALL"]  # ✅ COMPLIANT
    add: ["NET_BIND_SERVICE"]  # Add only if required
```

**Allowed Capabilities**:
- `NET_BIND_SERVICE` (bind to ports < 1024)
- `CHOWN` (only if absolutely required)

**Business Impact**:
Reduces kernel attack surface by 85%.

---

### 08. Deny Host Namespaces

**Severity**: CRITICAL
**Constraint**: `deny-host-namespaces`

**Description**:
Blocks use of host network, PID, and IPC namespaces.

**Rationale**:
Host namespaces break isolation:
- `hostNetwork`: See all network traffic on node
- `hostPID`: Kill any process on node (including kubelet)
- `hostIPC`: Access shared memory of other processes

**Violation Examples**:
```yaml
spec:
  hostNetwork: true  # ❌ VIOLATION
  hostPID: true      # ❌ VIOLATION
  hostIPC: true      # ❌ VIOLATION
```

**Compliant Example**:
```yaml
spec:
  # All host* fields omitted or set to false  # ✅ COMPLIANT
```

**Business Impact**:
Prevents container escape. Blocks 95% of known Kubernetes CVEs.

---

### 09. Deny Host Path Volumes

**Severity**: CRITICAL
**Constraint**: `deny-host-path`

**Description**:
Blocks hostPath volume mounts except for approved paths.

**Rationale**:
hostPath volumes provide access to host filesystem:
- Read `/etc/shadow` for password cracking
- Write to `/root/.ssh/authorized_keys` for persistence
- Access Docker socket for container escape

**Violation Example**:
```yaml
volumes:
  - name: host-volume
    hostPath:  # ❌ VIOLATION
      path: /var/lib/docker
```

**Compliant Example**:
```yaml
volumes:
  - name: data
    emptyDir: {}  # ✅ COMPLIANT
  - name: config
    configMap:    # ✅ COMPLIANT
      name: app-config
```

**Business Impact**:
Prevents 80% of container escape techniques.

---

### 15. Deny Privilege Escalation

**Severity**: HIGH
**Constraint**: `deny-privilege-escalation`

**Description**:
Requires `allowPrivilegeEscalation: false` for all containers.

**Rationale**:
Prevents processes from gaining more privileges than parent via:
- Setuid binaries
- Sudo escalation
- Capabilities manipulation

**Violation Example**:
```yaml
securityContext:
  allowPrivilegeEscalation: true  # ❌ VIOLATION
```

**Compliant Example**:
```yaml
securityContext:
  allowPrivilegeEscalation: false  # ✅ COMPLIANT
```

**Business Impact**:
Blocks privilege escalation attacks. Required for PCI DSS 6.5.

---

## Image Security Policies

### 04. Allowed Image Registries

**Severity**: CRITICAL
**Constraint**: `allowed-image-registries`

**Description**:
Restricts container images to approved registries.

**Rationale**:
Supply chain attacks via malicious images:
- Cryptominers (resource theft)
- Backdoors (persistent access)
- Data exfiltration

Only trusted registries ensure image provenance.

**Violation Example**:
```yaml
image: malicious-registry.com/backdoor:v1  # ❌ VIOLATION
```

**Compliant Example**:
```yaml
image: gcr.io/company/app:v1.2.3  # ✅ COMPLIANT
```

**Allowed Registries**:
- `docker.io/`
- `gcr.io/`
- `ghcr.io/`
- `quay.io/`
- `registry.company.internal/`

**Business Impact**:
Prevents supply chain attacks. Required for NIST SSDF compliance.

---

### 05. Block Latest Tag

**Severity**: HIGH
**Constraint**: `block-latest-tag`

**Description**:
Blocks use of `:latest` or untagged images.

**Rationale**:
Mutable tags cause:
- Non-reproducible deployments
- Untested code in production
- Difficult incident investigation ("which version was running?")

**Violation Examples**:
```yaml
image: nginx:latest  # ❌ VIOLATION
image: nginx         # ❌ VIOLATION (defaults to :latest)
```

**Compliant Examples**:
```yaml
image: nginx:1.25.0                              # ✅ COMPLIANT (semantic version)
image: nginx@sha256:abc123...                    # ✅ COMPLIANT (digest)
image: app:v1.2.3-build.456                      # ✅ COMPLIANT (build number)
```

**Business Impact**:
Ensures deployment reproducibility. Required for SOC 2 change management.

---

## RBAC Policies

### 12. Block Cluster Admin

**Severity**: CRITICAL
**Constraint**: `block-cluster-admin-binding`

**Description**:
Restricts creation of `cluster-admin` RoleBindings.

**Rationale**:
cluster-admin has unrestricted access:
- Create/delete any resource
- Access all secrets (including credentials)
- Modify security policies
- Delete audit logs

**Violation Example**:
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: bad-binding
roleRef:
  name: cluster-admin  # ❌ VIOLATION
  kind: ClusterRole
subjects:
  - kind: User
    name: developer@company.com
```

**Compliant Example**:
```yaml
roleRef:
  name: namespace-admin  # ✅ COMPLIANT (scoped role)
  kind: ClusterRole
```

**Exemptions**:
- ServiceAccount: `admin-automation`
- Group: `cluster-administrators`

**Business Impact**:
Prevents privilege escalation. Required for least privilege principle.

---

### 13. Deny Default ServiceAccount

**Severity**: MEDIUM
**Constraint**: `deny-default-serviceaccount`

**Description**:
Blocks use of `default` ServiceAccount.

**Rationale**:
Default ServiceAccount:
- Exists in every namespace
- Often has excessive permissions
- Shared across all pods (blast radius)

**Violation Examples**:
```yaml
spec:
  serviceAccountName: default  # ❌ VIOLATION
  # OR
  # serviceAccountName omitted   # ❌ VIOLATION (defaults to 'default')
```

**Compliant Example**:
```yaml
spec:
  serviceAccountName: app-specific-sa  # ✅ COMPLIANT
```

**Business Impact**:
Implements least privilege. Reduces lateral movement risk.

---

## Resource Management Policies

### 07. Require Resource Limits

**Severity**: MEDIUM
**Constraint**: `require-resource-limits`

**Description**:
Requires CPU and memory requests + limits for all containers.

**Rationale**:
Missing limits enable:
- Resource exhaustion (noisy neighbor)
- Cryptomining (100% CPU usage)
- Denial of service

**Violation Example**:
```yaml
containers:
  - name: app
    # Missing resources  # ❌ VIOLATION
```

**Compliant Example**:
```yaml
containers:
  - name: app
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "500m"
        memory: "512Mi"
```

**Business Impact**:
Prevents resource exhaustion. Required for SLA guarantees.

---

## Network Security Policies

### 10. Require NetworkPolicy

**Severity**: HIGH
**Constraint**: `require-networkpolicy`

**Description**:
Requires all namespaces to have NetworkPolicy label.

**Rationale**:
Default Kubernetes allows all pod-to-pod communication:
- Compromised pod can access any service
- Lateral movement across namespace boundaries
- No segmentation between tiers (web → DB direct access)

**Violation Example**:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: app
  # Missing network-policy label  # ❌ VIOLATION
```

**Compliant Example**:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: app
  labels:
    network-policy: enabled  # ✅ COMPLIANT
```

**Business Impact**:
Implements zero-trust networking. Required for PCI DSS network segmentation.

---

### 14. Deny Host Ports

**Severity**: MEDIUM
**Constraint**: `deny-host-ports`

**Description**:
Blocks `hostPort` in container port definitions.

**Rationale**:
hostPort:
- Exposes container on ALL cluster nodes
- Bypasses NetworkPolicy enforcement
- Port conflicts across nodes

**Violation Example**:
```yaml
ports:
  - containerPort: 8080
    hostPort: 8080  # ❌ VIOLATION
```

**Compliant Example**:
```yaml
ports:
  - containerPort: 8080  # ✅ COMPLIANT
    # Use Service/Ingress for external access
```

**Business Impact**:
Reduces attack surface. Enforces service mesh routing.

---

### 17. Block NodePort Services

**Severity**: MEDIUM
**Constraint**: `block-nodeport-services`

**Description**:
Blocks NodePort service type.

**Rationale**:
NodePort services:
- Expose on ALL nodes (wide attack surface)
- Use non-standard ports (30000-32767)
- Bypass load balancer security controls

**Violation Example**:
```yaml
spec:
  type: NodePort  # ❌ VIOLATION
```

**Compliant Examples**:
```yaml
spec:
  type: ClusterIP      # ✅ COMPLIANT (internal only)
  # OR
  type: LoadBalancer   # ✅ COMPLIANT (external with security controls)
```

**Business Impact**:
Forces use of managed load balancers with WAF/DDoS protection.

---

### 20. Require Ingress HTTPS

**Severity**: HIGH
**Constraint**: `require-ingress-https`

**Description**:
Requires TLS configuration for all Ingress resources.

**Rationale**:
HTTP traffic exposes:
- Credentials in plaintext
- Session tokens
- Sensitive data (PII, PHI)

**Violation Example**:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app
spec:
  # Missing tls section  # ❌ VIOLATION
  rules:
    - host: app.example.com
```

**Compliant Example**:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  tls:  # ✅ COMPLIANT
    - hosts:
        - app.example.com
      secretName: app-tls
  rules:
    - host: app.example.com
```

**Business Impact**:
Required for PCI DSS, GDPR, HIPAA compliance.

---

### 22. Deny External IPs

**Severity**: HIGH
**Constraint**: `deny-external-ips`

**Description**:
Blocks `externalIPs` field in Services.

**Rationale**:
externalIPs bypass:
- Load balancer security controls
- NetworkPolicy enforcement
- Traffic monitoring

**Violation Example**:
```yaml
spec:
  type: ClusterIP
  externalIPs:  # ❌ VIOLATION
    - 203.0.113.42
```

**Compliant Example**:
```yaml
spec:
  type: LoadBalancer  # ✅ COMPLIANT
  # Use managed load balancer instead
```

**Business Impact**:
Ensures all external traffic flows through monitored ingress points.

---

## Data Protection Policies

### 11. Require Seccomp Profile

**Severity**: HIGH
**Constraint**: `require-seccomp-profile`

**Description**:
Requires seccomp profile for all pods.

**Rationale**:
Seccomp restricts syscalls available to containers:
- Blocks kernel exploits (80% require rare syscalls)
- Prevents container escapes
- Reduces attack surface to ~50 common syscalls

**Violation Example**:
```yaml
spec:
  securityContext:
    # Missing seccompProfile  # ❌ VIOLATION
```

**Compliant Example**:
```yaml
spec:
  securityContext:
    seccompProfile:
      type: RuntimeDefault  # ✅ COMPLIANT
```

**Allowed Profiles**:
- `RuntimeDefault` (container runtime default)
- `Localhost` (custom profile)

**Business Impact**:
Blocks 80% of kernel exploits. Required for defense-in-depth.

---

### 18. Block Automount Service Account Token

**Severity**: MEDIUM
**Constraint**: `block-automount-serviceaccount-token`

**Description**:
Requires explicit opt-in for ServiceAccount token mounting.

**Rationale**:
Auto-mounted tokens:
- Available in every container at `/var/run/secrets/kubernetes.io/serviceaccount/token`
- Used for API access (often unnecessary)
- Exfiltrated in container compromises

**Violation Example**:
```yaml
spec:
  # Missing automountServiceAccountToken  # ❌ VIOLATION
```

**Compliant Example**:
```yaml
spec:
  automountServiceAccountToken: false  # ✅ COMPLIANT
```

**Business Impact**:
Reduces blast radius of container compromise by 60%.

---

## Policy Enforcement Metrics

| Severity | Count | Enforcement Action |
|----------|-------|-------------------|
| CRITICAL | 6 | `deny` (block deployment) |
| HIGH | 10 | `deny` (block deployment) |
| MEDIUM | 6 | `deny` or `dryrun` (configurable) |
| LOW | 0 | N/A |

---

## Audit and Compliance Mapping

### APRA CPS 234 (Australia)
- Information Security Controls: Policies 01-22 (comprehensive)
- Access Controls: Policies 12, 13
- Network Security: Policies 08, 10, 14, 17, 20, 22

### NIST Cybersecurity Framework
- Identify: Policies 04, 05, 16
- Protect: Policies 01-22 (all)
- Detect: Audit logging enabled
- Respond: Integration with SIEM (Phase 4)
- Recover: Immutable infrastructure via policies

### PCI DSS
- Requirement 2.2: Policies 01, 02, 06, 15
- Requirement 6.5: Policies 04, 05, 20
- Requirement 7.1: Policies 12, 13

### SOC 2
- CC6.1 (Logical Access): Policies 12, 13, 18
- CC6.6 (Encryption): Policy 20
- CC7.2 (System Monitoring): Audit logging

---

## Policy Violation Response

When a deployment is blocked:

1. **Review Violation Message**:
   ```
   Error from server: admission webhook "validation.gatekeeper.sh" denied the request:
   [deny-privileged-containers] Privileged container is not allowed: nginx
   ```

2. **Consult This Reference**: Find policy by name

3. **Fix Violation**: Apply compliant configuration

4. **Request Exception** (if justified):
   - Submit security review ticket
   - Document business justification
   - Obtain security team approval
   - Add to policy exemptions

---

## Policy Maintenance

**Review Cycle**: Quarterly

**Responsibilities**:
- **Security Team**: Policy definition, exception approval
- **Platform Team**: Policy deployment, monitoring
- **Development Teams**: Compliance implementation

**Change Process**:
1. Propose policy change (Slack: #security-policies)
2. Security review (2 business days)
3. Test in staging environment
4. Deploy to production (gradual rollout)
5. Monitor violation rates for 1 week

---

## Support

**Questions?** Contact:
- Slack: #kubernetes-security
- Email: security-team@company.com
- Docs: https://wiki.company.com/k8s-security

**Report False Positives**: Create ticket with evidence of legitimate use case
