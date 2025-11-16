#!/usr/bin/env python3
"""
Slack Webhook Integration for Falco Alerts
Sends formatted security alerts to Slack channels
"""

import json
import os
import sys
import requests
from datetime import datetime
from typing import Dict, Any

SLACK_WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL")
SLACK_CHANNEL = os.getenv("SLACK_CHANNEL", "#security-alerts")

# Emoji mapping for severity
SEVERITY_EMOJI = {
    "Critical": "🚨",
    "CRITICAL": "🚨",
    "Warning": "⚠️",
    "WARNING": "⚠️",
    "Error": "❌",
    "ERROR": "❌",
    "Notice": "ℹ️",
    "NOTICE": "ℹ️",
}

# Color mapping for Slack attachments
SEVERITY_COLOR = {
    "Critical": "danger",
    "CRITICAL": "danger",
    "Warning": "warning",
    "WARNING": "warning",
    "Error": "#ff9900",
    "ERROR": "#ff9900",
}


def format_alert(alert: Dict[str, Any]) -> Dict[str, Any]:
    """Format Falco alert for Slack"""
    priority = alert.get("priority", "Unknown")
    rule = alert.get("rule", "Unknown Rule")
    output = alert.get("output", "No details available")
    time_str = alert.get("time", datetime.utcnow().isoformat())
    output_fields = alert.get("output_fields", {})

    # Extract key fields
    pod = output_fields.get("k8s.pod.name", "unknown")
    namespace = output_fields.get("k8s.ns.name", "unknown")
    container = output_fields.get("container.name", "unknown")
    user = output_fields.get("user.name", "unknown")
    command = output_fields.get("proc.cmdline", "unknown")

    emoji = SEVERITY_EMOJI.get(priority, "🔔")
    color = SEVERITY_COLOR.get(priority, "#808080")

    # Build Slack message
    message = {
        "channel": SLACK_CHANNEL,
        "username": "Falco Security Bot",
        "icon_emoji": ":shield:",
        "text": f"{emoji} *{priority} Security Alert: {rule}*",
        "attachments": [
            {
                "color": color,
                "title": rule,
                "text": output,
                "fields": [
                    {
                        "title": "Pod",
                        "value": f"{namespace}/{pod}",
                        "short": True,
                    },
                    {
                        "title": "Container",
                        "value": container,
                        "short": True,
                    },
                    {
                        "title": "User",
                        "value": user,
                        "short": True,
                    },
                    {
                        "title": "Priority",
                        "value": priority,
                        "short": True,
                    },
                    {
                        "title": "Command",
                        "value": f"```{command[:100]}```",
                        "short": False,
                    },
                ],
                "footer": "Falco Runtime Security",
                "ts": int(datetime.fromisoformat(time_str.replace("Z", "+00:00")).timestamp()),
            }
        ],
    }

    # Add action buttons for CRITICAL alerts
    if priority in ["Critical", "CRITICAL"]:
        message["attachments"][0]["actions"] = [
            {
                "type": "button",
                "text": "View in Grafana",
                "url": f"https://grafana.company.com/d/security?var-pod={pod}",
            },
            {
                "type": "button",
                "text": "Incident Response Runbook",
                "url": "https://wiki.company.com/security/incident-response",
                "style": "danger",
            },
        ]

    return message


def send_to_slack(message: Dict[str, Any]) -> bool:
    """Send message to Slack webhook"""
    if not SLACK_WEBHOOK_URL:
        print("ERROR: SLACK_WEBHOOK_URL not set", file=sys.stderr)
        return False

    try:
        response = requests.post(
            SLACK_WEBHOOK_URL,
            json=message,
            headers={"Content-Type": "application/json"},
            timeout=10,
        )
        response.raise_for_status()
        print(f"Slack alert sent successfully: {response.status_code}")
        return True
    except requests.exceptions.RequestException as e:
        print(f"Failed to send Slack alert: {e}", file=sys.stderr)
        return False


def main():
    """Main entry point"""
    # Read alert from stdin or file
    if len(sys.argv) > 1:
        with open(sys.argv[1], "r") as f:
            alert_data = json.load(f)
    else:
        alert_data = json.load(sys.stdin)

    # Format and send alert
    slack_message = format_alert(alert_data)
    success = send_to_slack(slack_message)

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
