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


VERSION = "1.2.0"
DEFAULT_CATALOG = Path("/etc/homelab/dashboard-service-catalog.json")


def load_catalog(path: Path | None = None) -> dict[str, Any]:
    candidates = [path] if path else [
        Path(os.getenv("DASHBOARD_CATALOG_FILE", str(DEFAULT_CATALOG))),
        Path("/opt/homelab/config/service-catalog.json"),
        Path(__file__).resolve().parents[3] / "config" / "service-catalog.json",
    ]
    for candidate in candidates:
        if candidate is None or not candidate.is_file():
            continue
        try:
            payload = json.loads(candidate.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if isinstance(payload.get("applications"), list):
            return payload
    return {"version": 0, "applications": []}


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


def process_snapshot() -> dict[int, dict[str, Any]]:
    snapshot: dict[int, dict[str, Any]] = {}
    page_size = os.sysconf("SC_PAGE_SIZE")
    for path in Path("/proc").glob("[0-9]*/stat"):
        try:
            pid = int(path.parent.name)
            raw = path.read_text(encoding="utf-8", errors="replace")
            close = raw.rfind(")")
            name = raw[raw.find("(") + 1:close]
            fields = raw[close + 2:].split()
            snapshot[pid] = {
                "name": name,
                "cpu_ticks": int(fields[11]) + int(fields[12]),
                "memory_bytes": max(0, int(fields[21])) * page_size,
            }
        except (OSError, ValueError, IndexError):
            continue
    return snapshot


def build_top_processes(before: dict[int, dict[str, Any]], after: dict[int, dict[str, Any]], seconds: float, current_pid: int) -> dict[str, dict[str, Any] | None]:
    clock_ticks = os.sysconf("SC_CLK_TCK")
    rows: list[dict[str, Any]] = []
    for pid, current in after.items():
        previous = before.get(pid)
        if pid == current_pid or not previous or seconds <= 0:
            continue
        cpu_percent = max(0.0, (current["cpu_ticks"] - previous["cpu_ticks"]) / clock_ticks / seconds * 100)
        rows.append({"pid": pid, "name": current["name"], "cpu_percent": round(cpu_percent, 1), "memory_bytes": current["memory_bytes"]})
    return {
        "cpu": max(rows, key=lambda item: item["cpu_percent"], default=None),
        "memory": max(rows, key=lambda item: item["memory_bytes"], default=None),
    }


def collect_top_processes() -> dict[str, dict[str, Any] | None]:
    before = process_snapshot()
    started = time.monotonic()
    time.sleep(0.25)
    after = process_snapshot()
    return build_top_processes(before, after, time.monotonic() - started, os.getpid())


def filesystem_row(label: str, mountpoint: str | None, device: str | None, smart: dict[str, Any], size_bytes: int | None = None, external: bool = False) -> dict[str, Any]:
    try:
        usage = shutil.disk_usage(mountpoint) if mountpoint else None
        used = usage.total - usage.free
        percent = used / usage.total * 100 if usage.total else 0
    except (OSError, AttributeError):
        usage = None
        used = 0
        percent = 0
    row = {
        "label": label,
        "mountpoint": mountpoint,
        "device": device,
        "total_bytes": usage.total if usage else size_bytes,
        "used_bytes": used if usage else None,
        "free_bytes": usage.free if usage else None,
        "usage_percent": round(percent, 1) if usage else None,
        "smart_status": "unknown",
        "temperature_c": None,
        "model": None,
        "external": external,
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
    external: list[dict[str, Any]] = []
    result = run(["lsblk", "-J", "-b", "-T", "-o", "PATH,TYPE,TRAN,RM,HOTPLUG,MODEL,SIZE,MOUNTPOINTS"], timeout=10)
    try:
        blockdevices = json.loads(result.stdout).get("blockdevices", [])
    except json.JSONDecodeError:
        blockdevices = []
    excluded = {item for item in (root_disk, storage_disk) if item}
    for disk in blockdevices:
        if disk.get("type") != "disk" or disk.get("path") in excluded:
            continue
        if not (disk.get("tran") == "usb" or bool(disk.get("rm")) or bool(disk.get("hotplug"))):
            continue
        mounts: list[str] = []
        stack = list(disk.get("children") or [])
        while stack:
            child = stack.pop(0)
            mounts.extend(item for item in (child.get("mountpoints") or []) if item)
            stack.extend(child.get("children") or [])
        mounts.extend(item for item in (disk.get("mountpoints") or []) if item)
        model = str(disk.get("model") or "External disk").strip()
        external.append({
            "label": f"USB · {model}",
            "mountpoint": mounts[0] if mounts else None,
            "device": disk.get("path"),
            "size_bytes": disk.get("size") if isinstance(disk.get("size"), int) else None,
        })
    devices = {item for item in (root_disk, storage_disk) if item}
    devices.update(item["device"] for item in external if item.get("device"))
    smart = smart_for_devices(devices)
    disks = [
        filesystem_row("System SSD", "/", root_disk, smart),
        filesystem_row("Storage HDD", "/srv/storage", storage_disk, smart),
    ]
    disks.extend(
        filesystem_row(item["label"], item["mountpoint"], item["device"], smart, item["size_bytes"], external=True)
        for item in external
    )
    return disks


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
    rx_bytes = None
    tx_bytes = None
    if interface and re.fullmatch(r"[A-Za-z0-9_.-]+", interface):
        try:
            rx_bytes = int(read_text(f"/sys/class/net/{interface}/statistics/rx_bytes").strip())
            tx_bytes = int(read_text(f"/sys/class/net/{interface}/statistics/tx_bytes").strip())
        except ValueError:
            pass
    return {
        "interface": interface,
        "lan_ipv4": lan_ipv4,
        "tailscale_ipv4": tailscale_ipv4,
        "tailscale_online": tailscale_online,
        "phone_online": phone_online,
        "rx_bytes": rx_bytes,
        "tx_bytes": tx_bytes,
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


def percent(value: str) -> float:
    try:
        return round(float(value.strip().rstrip("%")), 2)
    except (AttributeError, ValueError):
        return 0.0


def bytes_from_human(value: str) -> int:
    match = re.fullmatch(r"\s*([0-9.]+)\s*([KMGT]?i?B)\s*", value, re.IGNORECASE)
    if not match:
        return 0
    units = {"b": 1, "kb": 1000, "kib": 1024, "mb": 1000**2, "mib": 1024**2, "gb": 1000**3, "gib": 1024**3, "tb": 1000**4, "tib": 1024**4}
    return int(float(match.group(1)) * units.get(match.group(2).lower(), 0))


def collect_container_resources() -> dict[str, list[dict[str, Any]]]:
    result = run(["docker", "stats", "--no-stream", "--format", "{{json .}}"], timeout=15)
    rows: list[dict[str, Any]] = []
    for line in result.stdout.splitlines():
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            continue
        name = item.get("Name") or item.get("Container")
        if not isinstance(name, str) or not name:
            continue
        memory_usage = str(item.get("MemUsage", "")).split(" / ", 1)[0]
        rows.append({
            "name": name,
            "cpu_percent": percent(item.get("CPUPerc", "0")),
            "memory_percent": percent(item.get("MemPerc", "0")),
            "memory_usage": memory_usage,
            "memory_bytes": bytes_from_human(memory_usage),
        })
    return {
        "cpu": sorted(rows, key=lambda item: item["cpu_percent"], reverse=True)[:3],
        "memory": sorted(rows, key=lambda item: item["memory_bytes"], reverse=True)[:3],
    }


def probe_url(url: str) -> tuple[bool, str]:
    request = urllib.request.Request(url, headers={"User-Agent": "hp-dashboard-collector/1.0"})
    try:
        with urllib.request.urlopen(request, timeout=3) as response:
            return 200 <= response.status < 400, f"HTTP {response.status}"
    except urllib.error.HTTPError as exc:
        return False, f"HTTP {exc.code}"
    except (urllib.error.URLError, TimeoutError, OSError):
        return False, "endpoint down"


def collect_apps(containers: list[dict[str, str]], applications: list[dict[str, Any]]) -> list[dict[str, str]]:
    by_name = {item["name"]: item for item in containers}
    apps: list[dict[str, str]] = []
    for application in applications:
        app_name = str(application.get("label") or application.get("id") or "Unknown")
        names = [name for name in application.get("containers", []) if isinstance(name, str)]
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
        probe = application.get("probe")
        if status == "healthy" and isinstance(probe, str):
            reachable, probe_detail = probe_url(probe)
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


def build_alerts(memory: dict[str, Any], disks: list[dict[str, Any]], containers: list[dict[str, str]], timers: dict[str, Any], network: dict[str, Any], apps: list[dict[str, str]] | None = None, applications: list[dict[str, Any]] | None = None) -> list[dict[str, str]]:
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
    expected = {
        name
        for application in (applications or [])
        for name in application.get("containers", [])
        if isinstance(name, str)
    }
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
    catalog = load_catalog()
    applications = [item for item in catalog.get("applications", []) if isinstance(item, dict)]
    cpu = collect_cpu()
    memory = collect_memory()
    top_processes = collect_top_processes()
    disks = collect_disks()
    network = collect_network()
    containers = collect_containers()
    top_containers = collect_container_resources()
    timers = collect_timers()
    apps = collect_apps(containers, applications)
    alerts = build_alerts(memory, disks, containers, timers, network, apps, applications)
    if not applications:
        alerts.append({"level": "warning", "message": "Service catalog is unavailable"})
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
        "top_processes": top_processes,
        "disks": disks,
        "network": network,
        "containers": containers,
        "top_containers": top_containers,
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
