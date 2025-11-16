#!/usr/bin/env python3
"""
SIEM Forwarder for Falco Alerts
Forwards alerts to ELK/Splunk for correlation
"""

import json
import os
import sys
import requests
from datetime import datetime
from typing import Dict, Any

ELASTICSEARCH_URL = os.getenv("ELASTICSEARCH_URL", "http://elasticsearch:9200")
ELASTICSEARCH_INDEX = os.getenv("ELASTICSEARCH_INDEX", "falco-alerts")


def enrich_alert(alert: Dict[str, Any]) -> Dict[str, Any]:
    """Enrich alert with additional context for SIEM"""
    enriched = alert.copy()

    # Add standard fields for SIEM
    enriched["@timestamp"] = alert.get("time", datetime.utcnow().isoformat())
    enriched["event"] = {
        "kind": "alert",
        "category": "intrusion_detection",
        "type": "indicator",
        "severity": alert.get("priority", "unknown").lower(),
    }

    # Extract and normalize fields
    output_fields = alert.get("output_fields", {})
    enriched["kubernetes"] = {
        "pod": {
            "name": output_fields.get("k8s.pod.name"),
            "namespace": output_fields.get("k8s.ns.name"),
        },
        "container": {
            "name": output_fields.get("container.name"),
            "id": output_fields.get("container.id"),
        },
    }

    enriched["process"] = {
        "name": output_fields.get("proc.name"),
        "pid": output_fields.get("proc.pid"),
        "command_line": output_fields.get("proc.cmdline"),
    }

    enriched["user"] = {
        "name": output_fields.get("user.name"),
        "uid": output_fields.get("user.uid"),
    }

    enriched["file"] = {
        "path": output_fields.get("fd.name"),
    }

    # MITRE ATT&CK mapping
    rule = alert.get("rule", "")
    enriched["threat"] = {"technique": map_to_mitre(rule)}

    return enriched


def map_to_mitre(rule: str) -> list:
    """Map Falco rules to MITRE ATT&CK techniques"""
    mappings = {
        "container escape": ["T1611"],  # Escape to Host
        "privilege escalation": ["T1068", "T1548"],
        "reverse shell": ["T1059"],  # Command and Scripting Interpreter
        "credential access": ["T1552"],  # Unsecured Credentials
        "persistence": ["T1053"],  # Scheduled Task/Job
    }

    techniques = []
    rule_lower = rule.lower()
    for keyword, techs in mappings.items():
        if keyword in rule_lower:
            techniques.extend(techs)

    return techniques


def send_to_elasticsearch(alert: Dict[str, Any]) -> bool:
    """Send alert to Elasticsearch"""
    index_url = f"{ELASTICSEARCH_URL}/{ELASTICSEARCH_INDEX}/_doc"

    try:
        response = requests.post(
            index_url,
            json=alert,
            headers={"Content-Type": "application/json"},
            timeout=10,
        )
        response.raise_for_status()
        print(f"Alert forwarded to SIEM: {response.json().get('_id')}")
        return True
    except requests.exceptions.RequestException as e:
        print(f"Failed to forward to SIEM: {e}", file=sys.stderr)
        return False


def main():
    """Main entry point"""
    if len(sys.argv) > 1:
        with open(sys.argv[1], "r") as f:
            alert_data = json.load(f)
    else:
        alert_data = json.load(sys.stdin)

    enriched = enrich_alert(alert_data)
    success = send_to_elasticsearch(enriched)

    # Also log to stdout for container logging
    print(json.dumps(enriched, indent=2))

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
