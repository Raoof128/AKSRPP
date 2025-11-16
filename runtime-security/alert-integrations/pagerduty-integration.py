#!/usr/bin/env python3
"""
PagerDuty Integration for Falco Alerts
Creates incidents for CRITICAL/WARNING alerts
"""

import json
import os
import sys
import requests
from datetime import datetime
from typing import Dict, Any

PAGERDUTY_API_URL = "https://events.pagerduty.com/v2/enqueue"
PAGERDUTY_INTEGRATION_KEY = os.getenv("PAGERDUTY_INTEGRATION_KEY")


def create_incident(alert: Dict[str, Any]) -> Dict[str, Any]:
    """Create PagerDuty incident from Falco alert"""
    priority = alert.get("priority", "Unknown")
    rule = alert.get("rule", "Unknown Rule")
    output = alert.get("output", "No details")
    output_fields = alert.get("output_fields", {})

    pod = output_fields.get("k8s.pod.name", "unknown")
    namespace = output_fields.get("k8s.ns.name", "unknown")

    # Map Falco priority to PagerDuty severity
    pd_severity = {
        "Critical": "critical",
        "CRITICAL": "critical",
        "Warning": "warning",
        "WARNING": "warning",
        "Error": "error",
        "ERROR": "error",
    }.get(priority, "info")

    incident = {
        "routing_key": PAGERDUTY_INTEGRATION_KEY,
        "event_action": "trigger",
        "dedup_key": f"falco-{namespace}-{pod}-{rule}",
        "payload": {
            "summary": f"[{priority}] {rule}: {namespace}/{pod}",
            "severity": pd_severity,
            "source": "falco-runtime-security",
            "component": f"{namespace}/{pod}",
            "group": "kubernetes-security",
            "class": "runtime-security",
            "custom_details": {
                "rule": rule,
                "output": output,
                "pod": pod,
                "namespace": namespace,
                "container": output_fields.get("container.name", "unknown"),
                "user": output_fields.get("user.name", "unknown"),
                "command": output_fields.get("proc.cmdline", "unknown"),
            },
        },
        "links": [
            {
                "href": f"https://grafana.company.com/d/security?var-pod={pod}",
                "text": "View in Grafana",
            },
        ],
    }

    return incident


def send_to_pagerduty(incident: Dict[str, Any]) -> bool:
    """Send incident to PagerDuty"""
    if not PAGERDUTY_INTEGRATION_KEY:
        print("ERROR: PAGERDUTY_INTEGRATION_KEY not set", file=sys.stderr)
        return False

    try:
        response = requests.post(
            PAGERDUTY_API_URL,
            json=incident,
            headers={"Content-Type": "application/json"},
            timeout=10,
        )
        response.raise_for_status()
        result = response.json()
        print(f"PagerDuty incident created: {result.get('dedup_key')}")
        return True
    except requests.exceptions.RequestException as e:
        print(f"Failed to create PagerDuty incident: {e}", file=sys.stderr)
        return False


def main():
    """Main entry point"""
    # Only trigger PagerDuty for CRITICAL/WARNING
    if len(sys.argv) > 1:
        with open(sys.argv[1], "r") as f:
            alert_data = json.load(f)
    else:
        alert_data = json.load(sys.stdin)

    priority = alert_data.get("priority", "").upper()
    if priority not in ["CRITICAL", "WARNING"]:
        print(f"Priority {priority} - not creating PagerDuty incident")
        sys.exit(0)

    incident = create_incident(alert_data)
    success = send_to_pagerduty(incident)

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
