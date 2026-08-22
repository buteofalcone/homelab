#!/usr/bin/env python3
from __future__ import annotations

import json
import logging
import logging.handlers
import os
import subprocess
import sys
from pathlib import Path


CONFIG_PATH = Path("/etc/homelab/dashboard-actions.json")
RESTART_GROUPS = {
    "immich": ["immich-server", "immich-machine-learning"],
    "jellyfin": ["jellyfin"],
    "nextcloud": ["nextcloud", "nextcloud-cron"],
    "calibre": ["calibre"],
    "open-webui": ["open-webui"],
    "seerr": ["seerr"],
    "media-automation": ["qbittorrent", "sonarr", "radarr", "prowlarr"],
    "kurhan": ["kurhan"],
    "ridni": ["ridni-staging-app-1", "ridni-staging-horizon-1", "ridni-staging-scheduler-1", "ridni-staging-nginx-1"],
}


def logger() -> logging.Logger:
    log = logging.getLogger("hp-dashboard-action")
    log.setLevel(logging.INFO)
    try:
        log.addHandler(logging.handlers.SysLogHandler(address="/dev/log"))
    except OSError:
        log.addHandler(logging.StreamHandler())
    return log


def run(command: list[str], timeout: int = 90) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, capture_output=True, timeout=timeout, check=False)


def load_smart_targets() -> dict[str, str]:
    try:
        payload = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    targets = payload.get("smart_devices", {})
    allowed: dict[str, str] = {}
    for name in ("system-ssd", "storage-hdd"):
        path = targets.get(name)
        if isinstance(path, str) and path.startswith("/dev/disk/by-id/") and Path(path).exists():
            allowed[name] = path
    return allowed


def fail(message: str, code: int = 2) -> int:
    print(message, file=sys.stderr)
    return code


def main(argv: list[str]) -> int:
    if os.geteuid() != 0:
        return fail("Action helper must run as root")
    if not argv:
        return fail("Missing action")
    action = argv[0]
    target = argv[1] if len(argv) == 2 else None
    if len(argv) > 2:
        return fail("Too many arguments")

    log = logger()
    log.info("action=%s target=%s caller_uid=%s", action, target or "-", os.getuid())

    if action == "restart" and target in RESTART_GROUPS:
        missing = [name for name in RESTART_GROUPS[target] if run(["docker", "inspect", name], timeout=15).returncode != 0]
        if missing:
            return fail(f"Refusing partial restart; missing containers: {', '.join(missing)}", 4)
        stopped = [
            name for name in RESTART_GROUPS[target]
            if run(["docker", "inspect", "-f", "{{.State.Running}}", name], timeout=15).stdout.strip() != "true"
        ]
        if stopped:
            return fail(f"Refusing to start stopped containers: {', '.join(stopped)}", 4)
        result = run(["docker", "restart", *RESTART_GROUPS[target]])
        if result.returncode:
            return fail(result.stderr.strip() or "Container restart failed", result.returncode)
        print(f"Restarted {target}")
        return 0
    if action == "backup" and target is None:
        active = run(["systemctl", "is-active", "homelab-backup.service"])
        if active.stdout.strip() == "active":
            return fail("Backup is already running", 3)
        result = run(["systemctl", "start", "--no-block", "homelab-backup.service"])
        if result.returncode:
            return fail(result.stderr.strip() or "Backup could not be started", result.returncode)
        print("Backup job started")
        return 0
    if action == "smart-short" and target in {"system-ssd", "storage-hdd"}:
        device = load_smart_targets().get(target)
        if not device:
            return fail("SMART target is not configured", 4)
        result = run(["smartctl", "-t", "short", device], timeout=20)
        if result.returncode != 0:
            return fail(result.stderr.strip() or result.stdout.strip() or "SMART test failed", result.returncode)
        print(result.stdout.strip()[-1200:] or f"SMART short test started for {target}")
        return 0
    if action in {"reboot", "shutdown"} and target is None:
        verb = "reboot" if action == "reboot" else "poweroff"
        unit = f"hp-dashboard-{action}"
        result = run(["systemd-run", "--collect", f"--unit={unit}", "--on-active=5s", "/usr/bin/systemctl", verb], timeout=15)
        if result.returncode:
            return fail(result.stderr.strip() or f"Could not schedule {action}", result.returncode)
        print(f"{action.capitalize()} scheduled in 5 seconds")
        return 0
    return fail("Action or target is not allowlisted")


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
