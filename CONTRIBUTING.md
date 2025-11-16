# Contributing to AKSRPP

Thank you for your interest in contributing to the Advanced Kubernetes Security & Runtime Protection Platform!

## Project Purpose

This is a **portfolio project** designed to demonstrate enterprise-grade Kubernetes security engineering capabilities for Australian SOC/CloudSecOps roles. While primarily built for showcase purposes, contributions that enhance the platform's educational value are welcome.

## How to Contribute

### Reporting Issues

Found a bug or security vulnerability?

1. **Security Issues**: Please report security vulnerabilities privately via the [SECURITY.md](SECURITY.md) process
2. **Bug Reports**: Open an issue with:
   - Clear description of the problem
   - Steps to reproduce
   - Expected vs actual behavior
   - Environment details (Kubernetes version, OS, etc.)

### Suggesting Enhancements

We welcome ideas that improve the platform's demonstration value:

- Additional OPA policies for common security scenarios
- New Falco rules for emerging threat patterns
- Enhanced monitoring dashboards
- Documentation improvements
- Integration examples with cloud providers (AWS/Azure/GCP)

Please open an issue first to discuss major changes.

### Development Process

#### 1. Fork & Clone

```bash
git clone https://github.com/yourusername/AKSRPP.git
cd AKSRPP
```

#### 2. Create a Feature Branch

```bash
git checkout -b feature/your-feature-name
```

#### 3. Make Your Changes

- Follow existing code style and structure
- Add tests for new functionality
- Update documentation as needed
- Ensure all existing tests pass

#### 4. Test Your Changes

```bash
# Run policy tests
cd admission-controller/policy-tests
./run-tests.sh

# Validate YAML syntax
yamllint .

# Test Go code
cd runtime-security/response-automation/operator
go test ./...
go vet ./...

# Test Python scripts
cd supply-chain/sbom-generator
python3 -m py_compile *.py
```

#### 5. Commit Your Changes

Follow conventional commits format:

```bash
git commit -m "feat: add new OPA policy for secret detection"
git commit -m "fix: correct Falco rule syntax for container escape"
git commit -m "docs: update deployment guide with troubleshooting"
```

Commit types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `test`: Adding or updating tests
- `refactor`: Code refactoring
- `perf`: Performance improvements
- `chore`: Maintenance tasks

#### 6. Push and Create Pull Request

```bash
git push origin feature/your-feature-name
```

Then open a pull request with:
- Clear description of changes
- Reference to related issues
- Screenshots/logs if applicable

## Code Style Guidelines

### Rego (OPA Policies)

- Use `future.keywords` import
- Include descriptive `msg` outputs
- Add business rationale in comments
- Test both PASS and FAIL scenarios

```rego
# Good
package k8srequiredlabels

import future.keywords.contains
import future.keywords.if

violation[{"msg": msg, "details": {"missing_labels": missing}}] if {
    provided := {label | input.review.object.metadata.labels[label]}
    required := {"app", "owner", "environment"}
    missing := required - provided
    count(missing) > 0
    msg := sprintf("Missing required labels: %v", [missing])
}
```

### Go (Remediation Operator)

- Follow standard Go formatting (`gofmt`)
- Use meaningful variable names
- Add error handling for all operations
- Include structured logging

```go
// Good
func (r *RemediationController) isolatePod(ctx context.Context, podName, namespace string) error {
    log.Printf("Isolating pod %s/%s", namespace, podName)

    np := &networkingv1.NetworkPolicy{
        ObjectMeta: metav1.ObjectMeta{
            Name:      fmt.Sprintf("isolate-%s", podName),
            Namespace: namespace,
        },
        Spec: networkingv1.NetworkPolicySpec{
            PodSelector: metav1.LabelSelector{
                MatchLabels: map[string]string{"pod": podName},
            },
            PolicyTypes: []networkingv1.PolicyType{
                networkingv1.PolicyTypeIngress,
                networkingv1.PolicyTypeEgress,
            },
        },
    }

    _, err := r.clientset.NetworkingV1().NetworkPolicies(namespace).Create(ctx, np, metav1.CreateOptions{})
    if err != nil {
        return fmt.Errorf("failed to create isolation policy: %w", err)
    }

    return nil
}
```

### Python (Alert Integrations)

- Follow PEP 8 style guide
- Use type hints
- Include docstrings for functions
- Handle exceptions gracefully

```python
# Good
import logging
from typing import Dict, Optional

def send_slack_alert(webhook_url: str, alert: Dict[str, str]) -> bool:
    """
    Send Falco alert to Slack webhook.

    Args:
        webhook_url: Slack incoming webhook URL
        alert: Alert data from Falco

    Returns:
        True if successful, False otherwise
    """
    try:
        payload = {
            "text": f"🚨 Security Alert: {alert.get('rule', 'Unknown')}",
            "attachments": [{
                "color": "danger",
                "fields": [
                    {"title": "Priority", "value": alert.get("priority", "N/A"), "short": True},
                    {"title": "Container", "value": alert.get("container", "N/A"), "short": True}
                ]
            }]
        }
        response = requests.post(webhook_url, json=payload, timeout=10)
        response.raise_for_status()
        return True
    except requests.exceptions.RequestException as e:
        logging.error(f"Failed to send Slack alert: {e}")
        return False
```

### YAML (Policies & Configs)

- Use 2-space indentation
- Add comments explaining complex configurations
- Validate with `yamllint`
- Group related resources

## Testing Requirements

### OPA Policies

Every new policy must include:
- At least 2 PASS test cases
- At least 2 FAIL test cases
- Edge cases documentation
- Performance validation (<50ms)

### Falco Rules

Every new rule must include:
- Clear `desc` field
- `output` with relevant context variables
- MITRE ATT&CK tags
- Priority classification

### Go Code

- Unit tests for all functions
- Integration tests for API endpoints
- Minimum 80% code coverage
- Error case testing

## Documentation Standards

- Update README.md if adding major features
- Add inline comments for complex logic
- Create separate markdown files for new components
- Include MITRE ATT&CK mapping for security rules
- Provide real-world attack scenario examples

## Pull Request Review Process

1. **Automated Checks**: CI/CD must pass
2. **Code Review**: Maintainer review within 48 hours
3. **Testing**: All tests must pass
4. **Documentation**: Must be complete and accurate
5. **Merge**: Squash and merge to main

## Community Guidelines

- Be respectful and constructive
- Focus on learning and knowledge sharing
- Credit sources and prior art
- Follow the [Code of Conduct](CODE_OF_CONDUCT.md)

## Questions?

- Open an issue for general questions
- Tag issues with `question` label
- Check [docs/](docs/) for architecture details

## Attribution

When contributing, you agree that your contributions will be licensed under the MIT License.

---

**Built with 🔒 for enterprise Kubernetes security**
