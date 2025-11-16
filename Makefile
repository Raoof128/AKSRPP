.PHONY: help setup test lint format validate deploy clean

# Default target
.DEFAULT_GOAL := help

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

##@ General

help: ## Display this help message
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make $(BLUE)<target>$(NC)\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  $(BLUE)%-15s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

setup: ## Install development dependencies
	@echo "$(BLUE)Installing development dependencies...$(NC)"
	@command -v python3 >/dev/null 2>&1 && pip3 install -e ".[dev]" || echo "Python not found, skipping Python deps"
	@command -v go >/dev/null 2>&1 && cd runtime-security/response-automation/operator && go mod download || echo "Go not found, skipping Go deps"
	@command -v helm >/dev/null 2>&1 && helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts || true
	@command -v helm >/dev/null 2>&1 && helm repo add falcosecurity https://falcosecurity.github.io/charts || true
	@command -v helm >/dev/null 2>&1 && helm repo update || echo "Helm not found"
	@echo "$(GREEN)✓ Setup complete$(NC)"

##@ Development

lint: lint-yaml lint-go lint-python lint-shell ## Run all linters
	@echo "$(GREEN)✓ All linting complete$(NC)"

lint-yaml: ## Lint YAML files
	@echo "$(BLUE)Linting YAML files...$(NC)"
	@if command -v yamllint >/dev/null 2>&1; then \
		yamllint .; \
		echo "$(GREEN)✓ YAML linting passed$(NC)"; \
	else \
		echo "$(YELLOW)⚠ yamllint not installed, skipping$(NC)"; \
	fi

lint-go: ## Lint Go code
	@echo "$(BLUE)Linting Go code...$(NC)"
	@if command -v golangci-lint >/dev/null 2>&1; then \
		cd runtime-security/response-automation/operator && golangci-lint run; \
		echo "$(GREEN)✓ Go linting passed$(NC)"; \
	else \
		echo "$(YELLOW)⚠ golangci-lint not installed, using go vet$(NC)"; \
		cd runtime-security/response-automation/operator && go vet ./...; \
	fi

lint-python: ## Lint Python code
	@echo "$(BLUE)Linting Python code...$(NC)"
	@if command -v pylint >/dev/null 2>&1; then \
		find . -name "*.py" -not -path "*/venv/*" -exec pylint {} + || true; \
		echo "$(GREEN)✓ Python linting complete$(NC)"; \
	else \
		echo "$(YELLOW)⚠ pylint not installed, using basic syntax check$(NC)"; \
		find . -name "*.py" -not -path "*/venv/*" -exec python3 -m py_compile {} \;; \
	fi

lint-shell: ## Lint shell scripts
	@echo "$(BLUE)Linting shell scripts...$(NC)"
	@if command -v shellcheck >/dev/null 2>&1; then \
		find . -name "*.sh" -exec shellcheck {} + || true; \
		echo "$(GREEN)✓ Shell linting complete$(NC)"; \
	else \
		echo "$(YELLOW)⚠ shellcheck not installed, using bash -n$(NC)"; \
		find . -name "*.sh" -exec bash -n {} \;; \
	fi

format: format-go format-python ## Format all code
	@echo "$(GREEN)✓ All formatting complete$(NC)"

format-go: ## Format Go code
	@echo "$(BLUE)Formatting Go code...$(NC)"
	@cd runtime-security/response-automation/operator && go fmt ./...
	@echo "$(GREEN)✓ Go formatting complete$(NC)"

format-python: ## Format Python code with black
	@echo "$(BLUE)Formatting Python code...$(NC)"
	@if command -v black >/dev/null 2>&1; then \
		find . -name "*.py" -not -path "*/venv/*" -exec black {} + ; \
		echo "$(GREEN)✓ Python formatting complete$(NC)"; \
	else \
		echo "$(YELLOW)⚠ black not installed, skipping$(NC)"; \
	fi

##@ Testing

test: test-policies test-go test-python ## Run all tests
	@echo "$(GREEN)✓ All tests complete$(NC)"

test-policies: ## Run OPA policy tests
	@echo "$(BLUE)Testing OPA policies...$(NC)"
	@cd admission-controller/policy-tests && ./run-tests.sh
	@echo "$(GREEN)✓ Policy tests complete$(NC)"

test-go: ## Run Go tests
	@echo "$(BLUE)Testing Go code...$(NC)"
	@cd runtime-security/response-automation/operator && go test -v -race -coverprofile=coverage.out ./...
	@echo "$(GREEN)✓ Go tests complete$(NC)"

test-python: ## Run Python tests
	@echo "$(BLUE)Testing Python code...$(NC)"
	@if command -v pytest >/dev/null 2>&1; then \
		pytest tests/ -v || true; \
	else \
		echo "$(YELLOW)⚠ pytest not installed, skipping$(NC)"; \
	fi

test-chaos: ## Run chaos engineering tests
	@echo "$(BLUE)Running chaos engineering tests...$(NC)"
	@cd tests/chaos-engineering && ./run-chaos-tests.sh
	@echo "$(GREEN)✓ Chaos tests complete$(NC)"

coverage: ## Generate test coverage reports
	@echo "$(BLUE)Generating coverage reports...$(NC)"
	@cd runtime-security/response-automation/operator && go test -coverprofile=coverage.out ./... && go tool cover -html=coverage.out -o coverage.html
	@echo "$(GREEN)✓ Coverage report generated: runtime-security/response-automation/operator/coverage.html$(NC)"

##@ Security

security-scan: security-scan-go security-scan-python security-scan-images ## Run all security scans
	@echo "$(GREEN)✓ Security scanning complete$(NC)"

security-scan-go: ## Scan Go code for vulnerabilities
	@echo "$(BLUE)Scanning Go code for vulnerabilities...$(NC)"
	@if command -v gosec >/dev/null 2>&1; then \
		cd runtime-security/response-automation/operator && gosec ./...; \
	else \
		echo "$(YELLOW)⚠ gosec not installed, skipping$(NC)"; \
	fi

security-scan-python: ## Scan Python dependencies for vulnerabilities
	@echo "$(BLUE)Scanning Python dependencies...$(NC)"
	@if command -v safety >/dev/null 2>&1; then \
		safety check || true; \
	else \
		echo "$(YELLOW)⚠ safety not installed, skipping$(NC)"; \
	fi

security-scan-images: ## Scan container images with Trivy
	@echo "$(BLUE)Scanning container images...$(NC)"
	@if command -v trivy >/dev/null 2>&1; then \
		trivy fs --severity HIGH,CRITICAL .; \
	else \
		echo "$(YELLOW)⚠ trivy not installed, skipping$(NC)"; \
	fi

secret-scan: ## Scan for committed secrets
	@echo "$(BLUE)Scanning for secrets...$(NC)"
	@if command -v gitleaks >/dev/null 2>&1; then \
		gitleaks detect --source . --verbose; \
	else \
		echo "$(YELLOW)⚠ gitleaks not installed, skipping$(NC)"; \
	fi

##@ Deployment

cluster-setup: ## Create local Kubernetes cluster
	@echo "$(BLUE)Setting up local cluster...$(NC)"
	@./scripts/setup-cluster.sh
	@echo "$(GREEN)✓ Cluster setup complete$(NC)"

deploy: ## Deploy full security platform
	@echo "$(BLUE)Deploying security platform...$(NC)"
	@./scripts/deploy-all.sh
	@echo "$(GREEN)✓ Deployment complete$(NC)"

validate: ## Validate deployment
	@echo "$(BLUE)Validating deployment...$(NC)"
	@./scripts/validate-security.sh
	@echo "$(GREEN)✓ Validation complete$(NC)"

deploy-phase1: ## Deploy Phase 1: Admission Control
	@echo "$(BLUE)Deploying Phase 1: Admission Control...$(NC)"
	@cd admission-controller/deployment && ./install-gatekeeper.sh && ./apply-policies.sh

deploy-phase2: ## Deploy Phase 2: Runtime Security
	@echo "$(BLUE)Deploying Phase 2: Runtime Security...$(NC)"
	@cd runtime-security/falco-rules && ./install-falco.sh
	@kubectl apply -f runtime-security/response-automation/kubernetes-manifests/

deploy-monitoring: ## Deploy monitoring stack
	@echo "$(BLUE)Deploying monitoring stack...$(NC)"
	@helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	@helm upgrade --install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace

##@ Build

build: build-operator ## Build all components
	@echo "$(GREEN)✓ All builds complete$(NC)"

build-operator: ## Build remediation operator
	@echo "$(BLUE)Building remediation operator...$(NC)"
	@cd runtime-security/response-automation/operator && \
		CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o bin/remediation-operator .
	@echo "$(GREEN)✓ Operator built$(NC)"

docker-build: ## Build Docker images
	@echo "$(BLUE)Building Docker images...$(NC)"
	@cd runtime-security/response-automation/operator && \
		docker build -t remediation-operator:latest .
	@echo "$(GREEN)✓ Docker images built$(NC)"

##@ Cleanup

clean: ## Clean build artifacts
	@echo "$(BLUE)Cleaning build artifacts...$(NC)"
	@find . -type f -name "*.pyc" -delete
	@find . -type d -name "__pycache__" -delete
	@find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
	@rm -f runtime-security/response-automation/operator/bin/remediation-operator
	@rm -f runtime-security/response-automation/operator/coverage.out
	@rm -f runtime-security/response-automation/operator/coverage.html
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

clean-cluster: ## Delete local cluster
	@echo "$(BLUE)Deleting local cluster...$(NC)"
	@kind delete cluster --name aksrpp-test 2>/dev/null || echo "Cluster not found"
	@echo "$(GREEN)✓ Cluster deleted$(NC)"

##@ Documentation

docs: ## Generate documentation
	@echo "$(BLUE)Documentation available in docs/ directory$(NC)"
	@echo "  - ARCHITECTURE.md: System architecture"
	@echo "  - THREAT_MODEL.md: MITRE ATT&CK mapping"
	@echo "  - DEMO.md: Demonstration guide"

docs-metrics: ## Display project metrics
	@echo "$(BLUE)Project Metrics:$(NC)"
	@echo "  Files: $$(git ls-files | wc -l)"
	@echo "  Lines of Code: $$(git ls-files | xargs wc -l | tail -1)"
	@echo "  OPA Policies: $$(find admission-controller/opa-policies -name '*-template.yaml' | wc -l)"
	@echo "  Falco Rules: $$(grep -c '^- rule:' runtime-security/falco-rules/custom-*.yaml)"
	@echo "  Test Cases: $$(find admission-controller/policy-tests -name 'test-*.yaml' | wc -l)"

##@ Utilities

version: ## Display version information
	@echo "$(BLUE)AKSRPP Version 1.0.0$(NC)"
	@echo "Component versions:"
	@echo "  Kubernetes: $$(kubectl version --short 2>/dev/null | head -2 || echo 'Not available')"
	@echo "  Helm: $$(helm version --short 2>/dev/null || echo 'Not available')"
	@echo "  Go: $$(go version 2>/dev/null || echo 'Not available')"
	@echo "  Python: $$(python3 --version 2>/dev/null || echo 'Not available')"

status: ## Display cluster status
	@echo "$(BLUE)Cluster Status:$(NC)"
	@kubectl cluster-info 2>/dev/null || echo "Not connected to cluster"
	@echo "\n$(BLUE)Security Components:$(NC)"
	@kubectl get pods -n gatekeeper-system 2>/dev/null || echo "Gatekeeper not deployed"
	@kubectl get pods -n falco 2>/dev/null || echo "Falco not deployed"
	@kubectl get pods -n security 2>/dev/null || echo "Operator not deployed"
	@kubectl get pods -n monitoring 2>/dev/null || echo "Monitoring not deployed"

logs-operator: ## View operator logs
	@kubectl logs -n security -l app=remediation-operator -f

logs-falco: ## View Falco logs
	@kubectl logs -n falco -l app.kubernetes.io/name=falco -f

logs-gatekeeper: ## View Gatekeeper logs
	@kubectl logs -n gatekeeper-system -l control-plane=controller-manager -f
