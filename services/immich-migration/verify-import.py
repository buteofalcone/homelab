#!/usr/bin/env python3
"""Verify Immich import state through the official API and write stable reports."""

from __future__ import annotations

import argparse
from collections import Counter
import csv
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import re
import tempfile
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--server", default="http://127.0.0.1:2283")
    parser.add_argument("--api-key-file", type=Path, default=Path("/etc/homelab/immich-go-api-key"))
    parser.add_argument("--takeout-report", type=Path)
    parser.add_argument("--import-log", type=Path)
    parser.add_argument("--immich-go-log", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--accept-sample", action="store_true")
    return parser.parse_args()


class ImmichApi:
    def __init__(self, server: str, key: str) -> None:
        self.base = server.rstrip("/") + "/api"
        self.key = key

    def request(self, method: str, path: str, body: dict[str, Any] | None = None) -> Any:
        data = json.dumps(body).encode() if body is not None else None
        request = Request(
            self.base + path,
            method=method,
            data=data,
            headers={"x-api-key": self.key, "accept": "application/json", "content-type": "application/json"},
        )
        try:
            with urlopen(request, timeout=120) as response:
                payload = response.read()
        except HTTPError as error:
            detail = error.read(1024).decode("utf-8", "replace")
            raise RuntimeError(f"Immich API {method} {path} returned {error.code}: {detail}") from error
        except URLError as error:
            raise RuntimeError(f"Immich API unavailable for {method} {path}: {error.reason}") from error
        return json.loads(payload) if payload else None

    def assets(self) -> list[dict[str, Any]]:
        assets: list[dict[str, Any]] = []
        page = 1
        while True:
            response = self.request("POST", "/search/metadata", {"page": page, "size": 1000, "withExif": True})
            result = response.get("assets", response)
            items = result.get("items", [])
            if not isinstance(items, list):
                raise RuntimeError("Immich search response did not contain assets.items")
            assets.extend(items)
            if len(items) < 1000 or not result.get("nextPage"):
                break
            page += 1
        return assets


def parse_time(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def parse_run(line: str) -> dict[str, str] | None:
    if "mode=sample" not in line or "action=apply" not in line or "event=finish" not in line:
        return None
    return dict(re.findall(r"([a-z_]+)=([^ ]+)", line))


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        handle.write(text)
        temporary = Path(handle.name)
    os.replace(temporary, path)


def atomic_csv(path: Path, rows: list[tuple[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", newline="", dir=path.parent, delete=False) as handle:
        writer = csv.writer(handle)
        writer.writerow(("metric", "value"))
        writer.writerows(rows)
        temporary = Path(handle.name)
    os.replace(temporary, path)


def main() -> int:
    args = parse_args()
    key = args.api_key_file.read_text(encoding="utf-8").strip()
    if not 20 <= len(key) <= 256:
        raise SystemExit("Immich API key format is invalid.")
    api = ImmichApi(args.server, key)
    del key

    version = api.request("GET", "/server/version")
    assets = api.assets()
    albums = api.request("GET", "/albums")
    tags = api.request("GET", "/tags")
    counts: Counter[str] = Counter()
    suspicious_examples: list[str] = []
    now = datetime.now(timezone.utc)
    for asset in assets:
        kind = str(asset.get("type", "unknown")).lower()
        counts["assets"] += 1
        counts[kind] += 1
        counts["favorites"] += bool(asset.get("isFavorite"))
        counts["archived"] += asset.get("visibility") == "archive" or bool(asset.get("isArchived"))
        exif = asset.get("exifInfo") or {}
        if exif.get("latitude") is not None and exif.get("longitude") is not None:
            counts["with_gps"] += 1
        else:
            counts["without_gps"] += 1
        capture = parse_time(exif.get("dateTimeOriginal") or asset.get("fileCreatedAt"))
        suspicious = capture is None
        if capture is not None:
            capture_utc = capture.replace(tzinfo=timezone.utc) if capture.tzinfo is None else capture.astimezone(timezone.utc)
            suspicious = capture_utc.year in {1904, 1970} or capture_utc.year < 1800 or capture_utc > now + timedelta(days=1)
        if suspicious:
            counts["suspicious_date"] += 1
            if len(suspicious_examples) < 100:
                suspicious_examples.append(str(asset.get("id", "unknown")))
        else:
            counts["valid_capture_date"] += 1
        if exif.get("timeZone"):
            counts["with_timezone"] += 1
        if asset.get("livePhotoVideoId"):
            counts["live_or_motion"] += 1

    counts["albums"] = len(albums) if isinstance(albums, list) else 0
    counts["tags"] = len(tags) if isinstance(tags, list) else 0
    go_log = args.immich_go_log.read_text(encoding="utf-8", errors="replace") if args.immich_go_log and args.immich_go_log.exists() else ""
    counts["failed_import_log_lines"] = len(
        re.findall(r"(?im)^.*(?:ERR|WRN).*\b(?:fail|error|missing metadata|unsupported)\b.*$", go_log)
    )

    takeout = {}
    if args.takeout_report and args.takeout_report.exists():
        takeout = json.loads(args.takeout_report.read_text(encoding="utf-8"))
    report = {
        "schema_version": 1,
        "generated_at": now.isoformat(),
        "immich_version": version,
        "counts": dict(sorted(counts.items())),
        "takeout": takeout.get("counts", {}),
        "suspicious_asset_ids_sample": suspicious_examples,
        "warnings": [
            "Takeout and Immich media are on the same physical disk and are not a disaster-recovery backup."
        ],
    }
    args.output_dir.mkdir(parents=True, exist_ok=True)
    atomic_write(args.output_dir / "verification-report.json", json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    lines = ["# Immich import verification", "", f"Generated: {report['generated_at']}", "", "## Counts", ""]
    lines.extend(f"- {name}: {value}" for name, value in sorted(counts.items()))
    lines.extend(["", "## Safety", "", f"- {report['warnings'][0]}", ""])
    atomic_write(args.output_dir / "verification-summary.md", "\n".join(lines))
    csv_rows = [(f"immich.{name}", value) for name, value in sorted(counts.items())]
    csv_rows.extend((f"takeout.{name}", value) for name, value in sorted(report["takeout"].items()))
    atomic_csv(args.output_dir / "verification-summary.csv", csv_rows)

    if args.accept_sample:
        runs: list[dict[str, str]] = []
        if args.import_log and args.import_log.exists():
            runs = [run for line in args.import_log.read_text(encoding="utf-8").splitlines() if (run := parse_run(line))]
        if len(runs) < 2:
            raise SystemExit("Two successful sample apply runs are required before acceptance.")
        first, second = runs[-2:]
        first_delta = int(first["assets_after"]) - int(first["assets_before"])
        second_asset_delta = int(second["assets_after"]) - int(second["assets_before"])
        second_album_delta = int(second["albums_after"]) - int(second["albums_before"])
        if first_delta <= 0 or second_asset_delta != 0 or second_album_delta != 0:
            raise SystemExit(
                f"Sample idempotency failed: first_asset_delta={first_delta} "
                f"second_asset_delta={second_asset_delta} second_album_delta={second_album_delta}"
            )
        if counts["failed_import_log_lines"]:
            raise SystemExit("The latest immich-go log contains failed/unsupported warning lines; review before acceptance.")
        marker = {
            "schema_version": 1,
            "accepted_at": now.isoformat(),
            "first_asset_delta": first_delta,
            "second_asset_delta": second_asset_delta,
            "second_album_delta": second_album_delta,
            "immich_version": version,
        }
        atomic_write(args.output_dir / "sample-accepted.json", json.dumps(marker, indent=2, sort_keys=True) + "\n")
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
