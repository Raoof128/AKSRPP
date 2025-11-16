#!/usr/bin/env python3
"""
Security Metrics Exporter for Prometheus

Exports custom security metrics from the AKSRPP platform.
"""

import time
import subprocess
import json
from http.server import HTTPServer, BaseHTTPRequestHandler
from typing import Dict, List


class SecurityMetrics:
    """Collect security metrics from the platform."""

    def __init__(self):
        self.namespace_security = "security"
        self.namespace_gatekeeper = "gatekeeper-system"
        self.namespace_falco = "falco"

    def get_policy_violations(self) -> int:
        """Get count of policy violations from Gatekeeper."""
        try:
            result = subprocess.run(
                ["kubectl", "get", "constraints", "-A", "-o", "json"],
                capture_output=True,
                text=True,
                check=True,
                timeout=10,
            )
            data = json.loads(result.stdout)
            total_violations = sum(
                item.get("status", {}).get("totalViolations", 0)
                for item in data.get("items", [])
            )
            return total_violations
        except (subprocess.CalledProcessError, json.JSONDecodeError, subprocess.TimeoutExpired):
            return -1

    def get_pod_count(self, namespace: str, label: str) -> int:
        """Get count of pods in namespace with label."""
        try:
            result = subprocess.run(
                [
                    "kubectl",
                    "get",
                    "pods",
                    "-n",
                    namespace,
                    "-l",
                    label,
                    "-o",
                    "json",
                ],
                capture_output=True,
                text=True,
                check=True,
                timeout=10,
            )
            data = json.loads(result.stdout)
            return len(data.get("items", []))
        except (subprocess.CalledProcessError, json.JSONDecodeError, subprocess.TimeoutExpired):
            return -1

    def export_metrics(self) -> str:
        """Export metrics in Prometheus format."""
        metrics = []

        # Policy violations
        violations = self.get_policy_violations()
        if violations >= 0:
            metrics.append(
                f"# HELP aksrpp_policy_violations_total Total OPA policy violations"
            )
            metrics.append(f"# TYPE aksrpp_policy_violations_total gauge")
            metrics.append(f"aksrpp_policy_violations_total {violations}")

        # Component health
        components = {
            "gatekeeper": (
                self.namespace_gatekeeper,
                "control-plane=controller-manager",
            ),
            "operator": (self.namespace_security, "app=remediation-operator"),
            "falco": (self.namespace_falco, "app.kubernetes.io/name=falco"),
        }

        for component, (namespace, label) in components.items():
            count = self.get_pod_count(namespace, label)
            if count >= 0:
                metrics.append(
                    f"# HELP aksrpp_component_pods Number of pods for {component}"
                )
                metrics.append(f"# TYPE aksrpp_component_pods gauge")
                metrics.append(
                    f'aksrpp_component_pods{{component="{component}"}} {count}'
                )

        # Platform info
        metrics.append(f"# HELP aksrpp_platform_info Platform information")
        metrics.append(f"# TYPE aksrpp_platform_info gauge")
        metrics.append(f'aksrpp_platform_info{{version="1.0.0"}} 1')

        return "\n".join(metrics) + "\n"


class MetricsHandler(BaseHTTPRequestHandler):
    """HTTP handler for Prometheus scraping."""

    def do_GET(self):  # noqa: N802
        """Handle GET requests."""
        if self.path == "/metrics":
            metrics = SecurityMetrics()
            output = metrics.export_metrics()

            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(output.encode())
        elif self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"OK")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):  # noqa: A002
        """Suppress request logging."""
        pass


def main():
    """Main function."""
    port = 9100
    server = HTTPServer(("0.0.0.0", port), MetricsHandler)

    print(f"Security metrics exporter running on port {port}")
    print(f"Metrics endpoint: http://localhost:{port}/metrics")
    print(f"Health endpoint: http://localhost:{port}/health")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()


if __name__ == "__main__":
    main()
