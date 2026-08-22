#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import grp
import json
import os
import platform
import re
import shutil
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


VERSION = "1.0.0"
APP_GROUPS = {
    "Core": ["caddy", "homepage", "homepage-docker-proxy", "portainer"],
    "Immich": ["immich-server", "immich-machine-learning", "immich-database", "immich-redis"],
    "Jellyfin": ["jellyfin"],
    "Nextcloud": ["nextcloud", "nextcloud-cron", "nextcloud-db", "nextcloud-redis"],
    "Calibre": ["calibre"],
    "Open WebUI": ["open-webui"],
    "Seerr": ["seerr"],
    "Media": ["qbittorrent", "sonarr", "radarr", "prowlarr"],
    "Kurhan": ["kurhan"],
    "Ridni": ["ridni-staging-app-1", "ridni-staging-nginx-1", "ridni-staging-horizon-1", "ridni-staging-scheduler-1", "ridni-staging-mysql-1", "ridni-staging-redis-1"],
    "Monitoring": ["beszel", "beszel-agent", "uptime-kuma"],
    "Time Machine": ["timemachine"],
}
APP_PROBES = {
    "Immich": "http://127.0.0.1:2283/api/server/ping",
    "Jellyfin": "http://127.0.0.1:8096/health",
    "Nextcloud": "http://127.0.0.1:8080/status.php",
    "Open WebUI": "http://127.0.0.1:3002/health",
    "Calibre": "https://books.butenko.online/",
    "Seerr": "https://requests.butenko.online/",
    "Kurhan": "https://kurhan.butenko.online/",
}


def run(command: list[str], timeout: float = 6) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, capture_output=True, timeout=timeout, check=False)


def read_text(path: str) -> str:
    try:
        return Path(path).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def cpu_sample() -> tuple[int, int]:
    fields = [int(value) for value in read_text("/proc/stat").splitlines()[0].split()[1:]]
    idle = fields[3] + (fields[4] if len(fields) > 4 else 0)
    return idle, sum(fields)


def collect_cpu() -> dict[str, Any]:
    idle_1, total_1 = cpu_sample()
    time.sleep(0.2)
    idle_2, total_2 = cpu_sample()
    delta_total = total_2 - total_1
    usage = 0.0 if delta_total <= 0 else 100.0 * (1 - (idle_2 - idle_1) / delta_total)
    model = ""
    for line in read_text("/proc/cpuinfo").splitlines():
        if line.lower().startswith("model name"):
            model = line.split(":", 1)[-1].strip().replace("(R)", "").replace("(TM)", "")
            model = re.sub(r"\s+CPU.*$", "", model).strip()
            break
    temps: list[float] = []
    for path in Path("/sys/class/hwmon").glob("hwmon*/temp*_input"):
        try:
            sensor_name = (path.parent / "name").read_text().strip().lower()
            if sensor_name not in {"coretemp", "k10temp", "cpu_thermal", "acpitz"}:
                continue
            value = float(path.read_text().strip()) / 1000
            if 0 < value < 120:
                temps.append(value)
        except (OSError, ValueError):
            continue
    load = os.getloadavg()
    return {
        "usage_percent": round(usage, 1),
        "temperature_c": round(max(temps), 1) if temps else None,
        "load_1": round(load[0], 2),
        "load_5": round(load[1], 2),
        "model": model or platform.processor() or "CPU",
    }


def collect_memory() -> dict[str, Any]:
    values: dict[str, int] = {}
    for line in read_text("/proc/meminfo").splitlines():
        key, _, raw = line.partition(":")
        match = re.search(r"\d+", raw)
        if match:
            values[key] = int(match.group()) * 1024
    total = values.get("MemTotal", 0)
    available = values.get("MemAvailable", 0)
    used = max(0, total - available)
    return {
        "total_bytes": total,
        "available_bytes": available,
        "used_bytes": used,
        "usage_percent": round(used / total * 100, 1) if total else None,
    }


def filesystem_row(label: str, mountpoint: str, device: str | None, smart: dict[str, Any]) -> dict[str, Any]:
    try:
        usage = shutil.disk_usage(mountpoint)
        used = usage.total - usage.free
        percent = used / usage.total * 100 if usage.total else 0
    except OSError:
        usage = None
        used = 0
        percent = 0
    row = {
        "label": label,
        "mountpoint": mountpoint,
        "device": device,
        "total_bytes": usage.total if usage else None,
        "used_bytes": used if usage else None,
        "free_bytes": usage.free if usage else None,
        "usage_percent": round(percent, 1) if usage else None,
        "smart_status": "unknown",
        "temperature_c": None,
        "model": None,
    }
    if device and device in smart:
        row.update(smart[device])
    return row


def parent_disk(source: str) -> str | None:
    result = run(["lsblk", "-ndo", "PKNAME", source])
    name = result.stdout.strip()
    if name:
        return f"/dev/{name}"
    direct = run(["lsblk", "-ndo", "TYPE", source]).stdout.strip()
    return source if direct == "disk" else None


def mount_source(mountpoint: str) -> str | None:
    result = run(["findmnt", "-nro", "SOURCE", mountpoint])
    source = result.stdout.strip()
    return source if source.startswith("/dev/") else None


def smart_for_devices(devices: set[str]) -> dict[str, dict[str, Any]]:
    output: dict[str, dict[str, Any]] = {}
    for device in sorted(devices):
        result = run(["smartctl", "-j", "-a", device], timeout=12)
        try:
            payload = json.loads(result.stdout)
        except json.JSONDecodeError:
            output[device] = {"smart_status": "unknown", "temperature_c": None, "model": None}
            continue
        passed = payload.get("smart_status", {}).get("passed")
        temp = payload.get("temperature", {}).get("current")
        output[device] = {
            "smart_status": "passed" if passed is True else "failed" if passed is False else "unknown",
            "temperature_c": temp if isinstance(temp, (int, float)) else None,
            "model": payload.get("model_name") or payload.get("model_family"),
            "smart_test": payload.get("ata_smart_self_test_log", {}).get("standard", {}).get("table", [{}])[0].get("status", {}).get("string")
            if payload.get("ata_smart_self_test_log", {}).get("standard", {}).get("table") else None,
        }
    return output


def collect_disks() -> list[dict[str, Any]]:
    root_source = mount_source("/")
    storage_source = mount_source("/srv/storage")
    root_disk = parent_disk(root_source) if root_source else None
    storage_disk = parent_disk(storage_source) if storage_source else None
    smart = smart_for_devices({item for item in (root_disk, storage_disk) if item})
    return [
        filesystem_row("System SSD", "/", root_disk, smart),
        filesystem_row("Storage HDD", "/srv/storage", storage_disk, smart),
    ]


def collect_network() -> dict[str, Any]:
    lan_ipv4 = None
    interface = None
    addresses = run(["ip", "-j", "-4", "address", "show", "scope", "global"])
    try:
        for item in json.loads(addresses.stdout):
            if item.get("ifname") == "tailscale0" or item.get("ifname", "").startswith(("docker", "br-")):
                continue
            infos = item.get("addr_info", [])
            if infos:
                interface = item.get("ifname")
                lan_ipv4 = infos[0].get("local")
                break
    except json.JSONDecodeError:
        pass

    tailscale_ipv4 = None
    tailscale_online = False
    phone_online = False
    result = run(["tailscale", "status", "--json"])
    try:
        payload = json.loads(result.stdout)
        self_node = payload.get("Self", {})
        tailscale_online = bool(self_node.get("Online", False))
        tailscale_ipv4 = next((ip for ip in self_node.get("TailscaleIPs", []) if ":" not in ip), None)
        for peer in payload.get("Peer", {}).values():
            name = f"{peer.get('HostName', '')} {peer.get('DNSName', '')}".lower()
            if "gt-neo" in name:
                phone_online = bool(peer.get("Online", False))
                break
    except json.JSONDecodeError:
        pass
    return {
        "interface": interface,
        "lan_ipv4": lan_ipv4,
        "tailscale_ipv4": tailscale_ipv4,
        "tailscale_online": tailscale_online,
        "phone_online": phone_online,
    }


def collect_containers() -> list[dict[str, str]]:
    result = run(["docker", "ps", "-a", "--format", "{{json .}}"], timeout=12)
    containers: list[dict[str, str]] = []
    for line in result.stdout.splitlines():
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            continue
        status_text = item.get("Status", "")
        health = "healthy" if "(healthy)" in status_text else "unhealthy" if "(unhealthy)" in status_text else "none"
        containers.append({
            "name": item.get("Names", "unknown"),
            "state": item.get("State", "unknown"),
            "health": health,
            "status": status_text,
            "image": item.get("Image", ""),
        })
    return sorted(containers, key=lambda item: item["name"])


def probe_url(url: str) -> tuple[bool, str]:
    request = urllib.request.Request(url, headers={"User-Agent": "hp-dashboard-collector/1.0"})
    try:
        with urllib.request.urlopen(request, timeout=3) as response:
            return 200 <= response.status < 400, f"HTTP {response.status}"
    except urllib.error.HTTPError as exc:
        return False, f"HTTP {exc.code}"
    except (urllib.error.URLError, TimeoutError, OSError):
        return False, "endpoint down"


def collect_apps(containers: list[dict[str, str]]) -> list[dict[str, str]]:
    by_name = {item["name"]: item for item in containers}
    apps: list[dict[str, str]] = []
    for app_name, names in APP_GROUPS.items():
        members = [by_name.get(name) for name in names]
        present = [member for member in members if member]
        bad = [member for member in present if member["state"] != "running" or member["health"] == "unhealthy"]
        if not present:
            status, detail = "unknown", "not deployed"
        elif bad or len(present) != len(names):
            status, detail = "degraded", f"{len(present) - len(bad)}/{len(names)} ready"
        else:
            status = "healthy"
            detail = f"{len(present)} container" + ("s" if len(present) != 1 else "")
        if status == "healthy" and app_name in APP_PROBES:
            reachable, probe_detail = probe_url(APP_PROBES[app_name])
            if not reachable:
                status, detail = "degraded", probe_detail
        apps.append({"name": app_name, "status": status, "detail": detail})
    return apps


def systemd_properties(unit: str, properties: list[str]) -> dict[str, str | None]:
    command = ["systemctl", "show", unit]
    for prop in properties:
        command.extend(["--property", prop])
    result = run(command)
    values: dict[str, str | None] = {prop: None for prop in properties}
    for line in result.stdout.splitlines():
        key, _, value = line.partition("=")
        if key in values:
            values[key] = value or None
    return values


def collect_timers() -> dict[str, Any]:
    backup = systemd_properties("homelab-backup.service", ["Result", "ExecMainStatus", "ActiveEnterTimestamp"])
    backup_timer = systemd_properties("homelab-backup.timer", ["NextElapseUSecRealtime", "LastTriggerUSec"])
    health = systemd_properties("homelab-health.service", ["Result", "ExecMainStatus", "ActiveEnterTimestamp"])
    return {
        "backup": {
            "result": backup.get("Result") or "unknown",
            "exit_status": backup.get("ExecMainStatus"),
            "last_run": backup_timer.get("LastTriggerUSec") or backup.get("ActiveEnterTimestamp"),
            "next_run": backup_timer.get("NextElapseUSecRealtime"),
        },
        "health": {
            "result": health.get("Result") or "unknown",
            "exit_status": health.get("ExecMainStatus"),
            "last_run": health.get("ActiveEnterTimestamp"),
        },
    }


def build_alerts(memory: dict[str, Any], disks: list[dict[str, Any]], containers: list[dict[str, str]], timers: dict[str, Any], network: dict[str, Any], apps: list[dict[str, str]] | None = None) -> list[dict[str, str]]:
    alerts: list[dict[str, str]] = []
    if (memory.get("usage_percent") or 0) >= 90:
        alerts.append({"level": "critical", "message": f"RAM usage is {memory['usage_percent']:.0f}%"})
    for disk in disks:
        if disk.get("mountpoint") == "/srv/storage" and disk.get("total_bytes") is None:
            alerts.append({"level": "critical", "message": "/srv/storage is not available"})
        elif (disk.get("usage_percent") or 0) >= 90:
            alerts.append({"level": "critical", "message": f"{disk['label']} usage is {disk['usage_percent']:.0f}%"})
        if disk.get("smart_status") == "failed":
            alerts.append({"level": "critical", "message": f"{disk['label']} SMART health failed"})
        if (disk.get("temperature_c") or 0) >= 55:
            alerts.append({"level": "warning", "message": f"{disk['label']} temperature is {disk['temperature_c']}°C"})
    expected = {name for names in APP_GROUPS.values() for name in names}
    unhealthy = [
        item["name"] for item in containers
        if item["name"] in expected and (item["state"] != "running" or item["health"] == "unhealthy")
    ]
    if unhealthy:
        alerts.append({"level": "warning", "message": f"Container attention: {', '.join(unhealthy[:4])}"})
    degraded_apps = [item["name"] for item in (apps or []) if item["status"] not in {"healthy"}]
    if degraded_apps:
        alerts.append({"level": "warning", "message": f"App endpoint attention: {', '.join(degraded_apps[:4])}"})
    if timers.get("backup", {}).get("result") not in {"success", "done"}:
        alerts.append({"level": "warning", "message": "Last backup result is not successful"})
    if not network.get("tailscale_online"):
        alerts.append({"level": "warning", "message": "Tailscale reports offline"})
    return alerts


def collect() -> dict[str, Any]:
    cpu = collect_cpu()
    memory = collect_memory()
    disks = collect_disks()
    network = collect_network()
    containers = collect_containers()
    timers = collect_timers()
    apps = collect_apps(containers)
    alerts = build_alerts(memory, disks, containers, timers, network, apps)
    now = dt.datetime.now(dt.timezone.utc)
    state = "critical" if any(item["level"] == "critical" for item in alerts) else "warning" if alerts else "good"
    return {
        "collector_version": VERSION,
        "generated_at": now.isoformat(),
        "generated_at_epoch": now.timestamp(),
        "summary": {
            "state": state,
            "hostname": platform.node(),
            "kernel": platform.release(),
            "uptime_seconds": float(read_text("/proc/uptime").split()[0]) if read_text("/proc/uptime") else None,
        },
        "cpu": cpu,
        "memory": memory,
        "disks": disks,
        "network": network,
        "containers": containers,
        "apps": apps,
        "timers": timers,
        "alerts": alerts,
    }


def write_atomic(output: Path, payload: dict[str, Any], group: str) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{output.name}.", dir=output.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, separators=(",", ":"))
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o640)
        os.chown(temporary, 0, grp.getgrnam(group).gr_gid)
        os.replace(temporary, output)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="/run/hp-dashboard/status.json")
    parser.add_argument("--group", default="hp-dashboard")
    parser.add_argument("--stdout", action="store_true")
    args = parser.parse_args()
    payload = collect()
    if args.stdout:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        write_atomic(Path(args.output), payload, args.group)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
