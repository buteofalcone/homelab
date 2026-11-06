#!/usr/bin/env python3
from __future__ import annotations

import ipaddress
import json
import subprocess


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, capture_output=True, check=True)


def main() -> int:
    routes = json.loads(run(["ip", "-j", "route", "show", "default"]).stdout)
    if not routes:
        raise SystemExit("No default route found")
    interface = routes[0]["dev"]
    addresses = json.loads(run(["ip", "-j", "-4", "address", "show", "dev", interface]).stdout)
    info = next(item for item in addresses[0]["addr_info"] if item.get("scope") == "global")
    network = ipaddress.ip_interface(f"{info['local']}/{info['prefixlen']}").network
    rules = f"""
table inet homelab_dashboard {{
  chain input {{
    type filter hook input priority -8; policy accept;
    iifname \"lo\" tcp dport 8787 accept comment \"Dashboard loopback\"
    iifname \"tailscale0\" tcp dport 8787 accept comment \"Dashboard Tailscale\"
    iifname \"{interface}\" ip saddr {network} tcp dport 8787 accept comment \"Dashboard trusted LAN\"
    iifname \"br-*\" tcp dport 8787 accept comment \"Dashboard Caddy bridge\"
    tcp dport 8787 reject with tcp reset comment \"Reject dashboard from other interfaces\"
  }}
}}
""".strip() + "\n"
    subprocess.run(["nft", "delete", "table", "inet", "homelab_dashboard"], capture_output=True, check=False)
    subprocess.run(["nft", "-f", "-"], input=rules, text=True, check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
