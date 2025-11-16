#!/bin/bash

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    local missing_tools=()

    if ! command -v cosign &> /dev/null; then
        missing_tools+=("cosign")
    fi

    if ! command -v docker &> /dev/null && ! command -v podman &> /dev/null; then
        missing_tools+=("docker or podman")
    fi

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Install cosign: go install github.com/sigstore/cosign/v2/cmd/cosign@latest"
        exit 1
    fi
}

# Generate signing key pair
generate_keys() {
    log_info "Generating signing key pair..."

    if [ -f cosign.key ] && [ -f cosign.pub ]; then
        log_info "Keys already exist, skipping generation"
        return
    fi

    # Generate key pair with password
    cosign generate-key-pair

    log_success "Key pair generated: cosign.key (private), cosign.pub (public)"
    log_info "⚠️  Store cosign.key securely and never commit to git!"
}

# Sign container image
sign_image() {
    local image=$1

    log_info "Signing image: $image"

    # Sign with private key
    cosign sign --key cosign.key "$image"

    log_success "Image signed: $image"
}

# Verify image signature
verify_image() {
    local image=$1

    log_info "Verifying signature for: $image"

    # Verify with public key
    if cosign verify --key cosign.pub "$image"; then
        log_success "Signature verified: $image"
        return 0
    else
        log_error "Signature verification failed: $image"
        return 1
    fi
}

# Sign image using keyless mode (Sigstore)
sign_keyless() {
    local image=$1

    log_info "Signing image with keyless mode (Sigstore): $image"
    log_info "This requires OIDC authentication (GitHub, Google, Microsoft)"

    # Sign using OIDC identity
    cosign sign "$image"

    log_success "Image signed with keyless mode: $image"
}

# Generate SBOM and sign it
sign_sbom() {
    local image=$1

    log_info "Generating and signing SBOM for: $image"

    # Check for syft
    if ! command -v syft &> /dev/null; then
        log_error "syft not installed, cannot generate SBOM"
        return 1
    fi

    # Generate SBOM
    local sbom_file="sbom-$(echo "$image" | tr '/:' '-').json"
    syft "$image" -o cyclonedx-json > "$sbom_file"

    log_success "SBOM generated: $sbom_file"

    # Attach SBOM to image
    cosign attach sbom --sbom "$sbom_file" "$image"

    # Sign SBOM
    cosign sign --key cosign.key "$image"

    log_success "SBOM attached and signed for: $image"
}

# Batch sign images from file
batch_sign() {
    local image_list=$1

    if [ ! -f "$image_list" ]; then
        log_error "Image list file not found: $image_list"
        exit 1
    fi

    log_info "Batch signing images from: $image_list"

    while IFS= read -r image; do
        # Skip empty lines and comments
        [[ -z "$image" || "$image" =~ ^# ]] && continue

        sign_image "$image"
    done < "$image_list"

    log_success "Batch signing complete"
}

# Create Kubernetes admission policy for signature verification
create_admission_policy() {
    log_info "Creating Kubernetes admission policy for signature verification..."

    cat > image-signature-policy.yaml <<'EOF'
apiVersion: policy.sigstore.dev/v1beta1
kind: ClusterImagePolicy
metadata:
  name: require-signed-images
spec:
  images:
  - glob: "**"  # Apply to all images
  authorities:
  - key:
      data: |
        -----BEGIN PUBLIC KEY-----
        # Replace with your cosign.pub content
        -----END PUBLIC KEY-----
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: cosign-public-key
  namespace: security
data:
  cosign.pub: |
    # Replace with your cosign.pub content
EOF

    log_success "Policy template created: image-signature-policy.yaml"
    log_info "Update the policy with your public key from cosign.pub"
}

# Display usage
usage() {
    cat <<EOF
Usage: $0 <command> [options]

Commands:
  generate-keys              Generate signing key pair
  sign <image>               Sign a container image
  verify <image>             Verify image signature
  sign-keyless <image>       Sign using keyless mode (Sigstore)
  sign-sbom <image>          Generate SBOM and sign
  batch-sign <file>          Sign multiple images from file
  create-policy              Create admission policy template

Examples:
  $0 generate-keys
  $0 sign ghcr.io/user/app:v1.0.0
  $0 verify ghcr.io/user/app:v1.0.0
  $0 sign-keyless ghcr.io/user/app:v1.0.0
  $0 sign-sbom nginx:latest
  $0 batch-sign images.txt

Environment Variables:
  COSIGN_PASSWORD            Password for private key
  COSIGN_YES                 Skip confirmation prompts

EOF
}

# Main
main() {
    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi

    check_prerequisites

    case "$1" in
        generate-keys)
            generate_keys
            ;;
        sign)
            if [ -z "${2:-}" ]; then
                log_error "Image name required"
                usage
                exit 1
            fi
            sign_image "$2"
            ;;
        verify)
            if [ -z "${2:-}" ]; then
                log_error "Image name required"
                usage
                exit 1
            fi
            verify_image "$2"
            ;;
        sign-keyless)
            if [ -z "${2:-}" ]; then
                log_error "Image name required"
                usage
                exit 1
            fi
            sign_keyless "$2"
            ;;
        sign-sbom)
            if [ -z "${2:-}" ]; then
                log_error "Image name required"
                usage
                exit 1
            fi
            sign_sbom "$2"
            ;;
        batch-sign)
            if [ -z "${2:-}" ]; then
                log_error "Image list file required"
                usage
                exit 1
            fi
            batch_sign "$2"
            ;;
        create-policy)
            create_admission_policy
            ;;
        *)
            log_error "Unknown command: $1"
            usage
            exit 1
            ;;
    esac
}

main "$@"
