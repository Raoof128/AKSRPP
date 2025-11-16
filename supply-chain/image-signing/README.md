# Container Image Signing

This directory contains tools for signing and verifying container images using Cosign (Sigstore).

## Why Sign Images?

Image signing provides:
- **Supply chain integrity**: Verify images haven't been tampered with
- **Provenance tracking**: Confirm who built and published the image
- **Compliance**: Meet regulatory requirements (APRA CPS 234, NIST SSDF)
- **Attack prevention**: Prevent malicious image injection

## Prerequisites

```bash
# Install Cosign
go install github.com/sigstore/cosign/v2/cmd/cosign@latest

# Or via package manager
brew install cosign       # macOS
apt install cosign        # Ubuntu/Debian
```

## Quick Start

### 1. Generate Signing Keys

```bash
./sign-images.sh generate-keys

# Enter password when prompted
# This creates:
#   - cosign.key (private key) - KEEP SECRET!
#   - cosign.pub (public key) - Share this
```

**Security**: Store `cosign.key` in a secure location:
- Kubernetes Secret (for CI/CD)
- HashiCorp Vault
- AWS Secrets Manager / Azure Key Vault
- Hardware Security Module (HSM)

### 2. Sign an Image

```bash
# Sign with private key
./sign-images.sh sign ghcr.io/yourusername/app:v1.0.0

# Keyless signing (uses OIDC)
./sign-images.sh sign-keyless ghcr.io/yourusername/app:v1.0.0
```

### 3. Verify Signature

```bash
./sign-images.sh verify ghcr.io/yourusername/app:v1.0.0
```

### 4. Sign with SBOM

```bash
# Generates SBOM and attaches to image
./sign-images.sh sign-sbom nginx:latest
```

## Advanced Usage

### Batch Signing

Create a file `images.txt`:
```
ghcr.io/user/app:v1.0.0
ghcr.io/user/api:v2.1.3
ghcr.io/user/worker:latest
```

Sign all images:
```bash
./sign-images.sh batch-sign images.txt
```

### CI/CD Integration

**GitHub Actions**:
```yaml
name: Build and Sign
on: push

jobs:
  build-sign:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      id-token: write  # For keyless signing

    steps:
      - uses: actions/checkout@v4

      - name: Install Cosign
        uses: sigstore/cosign-installer@v3

      - name: Login to Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build Image
        run: docker build -t ghcr.io/${{ github.repository }}:${{ github.sha }} .

      - name: Push Image
        run: docker push ghcr.io/${{ github.repository }}:${{ github.sha }}

      - name: Sign Image (Keyless)
        run: cosign sign ghcr.io/${{ github.repository }}:${{ github.sha }}

      # OR with private key
      - name: Sign Image (Private Key)
        env:
          COSIGN_PASSWORD: ${{ secrets.COSIGN_PASSWORD }}
        run: |
          echo "${{ secrets.COSIGN_PRIVATE_KEY }}" > cosign.key
          cosign sign --key cosign.key ghcr.io/${{ github.repository }}:${{ github.sha }}
```

### Kubernetes Policy Enforcement

Use Sigstore Policy Controller or Kyverno to enforce signature verification:

**Install Policy Controller**:
```bash
kubectl apply -f https://github.com/sigstore/policy-controller/releases/latest/download/policy-controller.yaml
```

**Create Policy**:
```bash
./sign-images.sh create-policy

# Edit image-signature-policy.yaml with your public key
kubectl apply -f image-signature-policy.yaml
```

Now all pods must use signed images:
```bash
# This will be blocked if image is not signed
kubectl run test --image=unsigned:latest
```

## Keyless Signing (Recommended)

Keyless signing uses OIDC providers (GitHub, Google, Microsoft) instead of managing private keys.

**Advantages**:
- No key management
- Automatic rotation
- Audit trail
- Integration with existing identity providers

**Sign with GitHub**:
```bash
# Login via OIDC
cosign sign ghcr.io/user/app:v1.0.0

# Browser opens for authentication
# Signature is bound to your GitHub identity
```

**Verify**:
```bash
cosign verify \
  --certificate-identity=user@example.com \
  --certificate-oidc-issuer=https://github.com/login/oauth \
  ghcr.io/user/app:v1.0.0
```

## SBOM Attestation

Attach Software Bill of Materials (SBOM) to images:

```bash
# Generate and sign SBOM
syft ghcr.io/user/app:v1.0.0 -o cyclonedx-json > sbom.json
cosign attach sbom --sbom sbom.json ghcr.io/user/app:v1.0.0
cosign sign ghcr.io/user/app:v1.0.0

# Verify and download SBOM
cosign verify-attestation ghcr.io/user/app:v1.0.0
cosign download sbom ghcr.io/user/app:v1.0.0
```

## Security Best Practices

### Key Management

1. **Never commit private keys** to Git
   - Add to `.gitignore`: `*.key`
   - Use `.gitignore` patterns: `cosign.key`

2. **Rotate keys regularly**
   ```bash
   # Generate new keys
   cosign generate-key-pair -new

   # Re-sign all images
   ./sign-images.sh batch-sign images.txt
   ```

3. **Use hardware keys** for production
   ```bash
   # Sign with Yubikey
   cosign sign --key yubikey ghcr.io/user/app:v1.0.0
   ```

### Access Control

- Limit who can sign images (CI/CD service accounts only)
- Separate signing keys per environment (dev, staging, prod)
- Audit signature operations
- Monitor for unsigned image deployments

### Verification

Always verify signatures before deployment:

```bash
# In deployment pipeline
cosign verify --key cosign.pub "$IMAGE" || exit 1
kubectl set image deployment/app app="$IMAGE"
```

## Compliance Mapping

| Standard | Requirement | How We Address |
|----------|-------------|----------------|
| APRA CPS 234 | Software integrity | Image signatures verify integrity |
| NIST SSDF | Provenance tracking | Keyless signatures provide identity |
| SLSA Level 3 | Build provenance | SBOM attestations |
| PCI DSS 6.2 | Secure SDLC | Signed images prevent tampering |

## Troubleshooting

### Signature Verification Failed

```bash
# Check signature exists
cosign verify --key cosign.pub ghcr.io/user/app:v1.0.0

# Common issues:
# 1. Wrong public key
# 2. Image was re-pushed without signing
# 3. Registry transparency log issues
```

### Permission Denied

```bash
# Ensure you're logged in to registry
docker login ghcr.io

# Check credentials
cosign login ghcr.io
```

### OIDC Authentication Failed

```bash
# Set environment for GitHub Actions
export COSIGN_EXPERIMENTAL=1
export GITHUB_TOKEN=${{ secrets.GITHUB_TOKEN }}
```

## References

- [Cosign Documentation](https://docs.sigstore.dev/cosign/overview)
- [Sigstore](https://www.sigstore.dev/)
- [SLSA Framework](https://slsa.dev/)
- [Software Supply Chain Security](https://www.cisa.gov/sbom)

---

**Security Note**: This implementation uses Cosign for cryptographic signing. Always validate signatures before deploying to production.
