#!/usr/bin/env python3
"""
Container Image Scanner
Scans images for vulnerabilities and generates SBOM
"""

import subprocess
import json
import sys
from pathlib import Path


def scan_with_trivy(image: str) -> dict:
    """Scan image with Trivy"""
    print(f"Scanning {image} with Trivy...")

    cmd = [
        "trivy",
        "image",
        "--format", "json",
        "--severity", "CRITICAL,HIGH,MEDIUM",
        image
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)
    return json.loads(result.stdout) if result.returncode == 0 else {}


def generate_sbom(image: str) -> dict:
    """Generate SBOM with Syft"""
    print(f"Generating SBOM for {image}...")

    cmd = [
        "syft",
        "packages",
        image,
        "-o", "cyclonedx-json"
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)
    return json.loads(result.stdout) if result.returncode == 0 else {}


def check_policy(vulnerabilities: list) -> bool:
    """Check if image meets security policy"""
    critical = sum(1 for v in vulnerabilities if v.get("Severity") == "CRITICAL")
    high = sum(1 for v in vulnerabilities if v.get("Severity") == "HIGH")

    # Policy: Block if >0 CRITICAL or >5 HIGH
    if critical > 0:
        print(f"❌ POLICY VIOLATION: {critical} CRITICAL vulnerabilities")
        return False
    if high > 5:
        print(f"❌ POLICY VIOLATION: {high} HIGH vulnerabilities (max: 5)")
        return False

    print(f"✅ Policy compliant: {critical} CRITICAL, {high} HIGH")
    return True


def main():
    if len(sys.argv) < 2:
        print("Usage: scan-images.py <image>")
        sys.exit(1)

    image = sys.argv[1]

    # Scan for vulnerabilities
    trivy_results = scan_with_trivy(image)

    # Generate SBOM
    sbom = generate_sbom(image)

    # Check policy
    vulns = trivy_results.get("Results", [{}])[0].get("Vulnerabilities", [])
    compliant = check_policy(vulns)

    sys.exit(0 if compliant else 1)


if __name__ == "__main__":
    main()
