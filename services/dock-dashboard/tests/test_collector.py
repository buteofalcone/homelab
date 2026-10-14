from __future__ import annotations

import importlib.util
from pathlib import Path


path = Path(__file__).resolve().parents[1] / "scripts" / "collector.py"
spec = importlib.util.spec_from_file_location("dashboard_collector", path)
collector = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(collector)

APPLICATIONS = [
    {"id": "jellyfin", "label": "Jellyfin", "containers": ["jellyfin"], "restart": ["jellyfin"]},
]


def test_intentionally_stopped_watchtower_does_not_alert() -> None:
    alerts = collector.build_alerts(
        {"usage_percent": 40},
        [
            {"label": "System SSD", "mountpoint": "/", "total_bytes": 100, "usage_percent": 20, "smart_status": "passed", "temperature_c": 30},
            {"label": "Storage HDD", "mountpoint": "/srv/storage", "total_bytes": 100, "usage_percent": 50, "smart_status": "passed", "temperature_c": 35},
        ],
        [{"name": "watchtower", "state": "exited", "health": "none"}],
        {"backup": {"result": "success"}},
        {"tailscale_online": True},
        applications=APPLICATIONS,
    )
    assert alerts == []


def test_failed_smart_and_unhealthy_container_alert() -> None:
    alerts = collector.build_alerts(
        {"usage_percent": 40},
        [{"label": "Storage HDD", "mountpoint": "/srv/storage", "total_bytes": 100, "usage_percent": 50, "smart_status": "failed", "temperature_c": 35}],
        [{"name": "jellyfin", "state": "running", "health": "unhealthy"}],
        {"backup": {"result": "success"}},
        {"tailscale_online": True},
        applications=APPLICATIONS,
    )
    messages = " ".join(item["message"] for item in alerts)
    assert "SMART" in messages
    assert "jellyfin" in messages


def test_percent_parser_is_safe() -> None:
    assert collector.percent("12.34%") == 12.34
    assert collector.percent("not-a-number") == 0
    assert collector.bytes_from_human("1.5 GiB") == 1610612736
    assert collector.bytes_from_human("254.7MiB") == 267072307


def test_repository_catalog_is_valid() -> None:
    catalog = collector.load_catalog()
    applications = catalog["applications"]
    assert catalog["version"] == 1
    assert any(item["id"] == "jellyfin" and item["restart"] == ["jellyfin"] for item in applications)


def test_top_processes_use_sample_delta_and_hide_collector() -> None:
    before = {10: {"name": "jellyfin", "cpu_ticks": 100, "memory_bytes": 100}, 20: {"name": "python3", "cpu_ticks": 100, "memory_bytes": 999}}
    after = {10: {"name": "jellyfin", "cpu_ticks": 125, "memory_bytes": 100}, 20: {"name": "python3", "cpu_ticks": 200, "memory_bytes": 999}}
    result = collector.build_top_processes(before, after, seconds=1.0, current_pid=20)
    assert result["cpu"]["name"] == "jellyfin"
    assert result["memory"]["name"] == "jellyfin"
    assert result["cpu"]["cpu_percent"] > 0
