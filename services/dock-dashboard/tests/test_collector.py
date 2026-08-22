from __future__ import annotations

import importlib.util
from pathlib import Path


path = Path(__file__).resolve().parents[1] / "scripts" / "collector.py"
spec = importlib.util.spec_from_file_location("dashboard_collector", path)
collector = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(collector)


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
    )
    assert alerts == []


def test_failed_smart_and_unhealthy_container_alert() -> None:
    alerts = collector.build_alerts(
        {"usage_percent": 40},
        [{"label": "Storage HDD", "mountpoint": "/srv/storage", "total_bytes": 100, "usage_percent": 50, "smart_status": "failed", "temperature_c": 35}],
        [{"name": "jellyfin", "state": "running", "health": "unhealthy"}],
        {"backup": {"result": "success"}},
        {"tailscale_online": True},
    )
    messages = " ".join(item["message"] for item in alerts)
    assert "SMART" in messages
    assert "jellyfin" in messages
