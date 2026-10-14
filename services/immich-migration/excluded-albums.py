#!/usr/bin/env python3
"""Remove only excluded albums created during one Takeout import run."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("snapshot", "apply"))
    parser.add_argument("--server", default="http://127.0.0.1:2283")
    parser.add_argument("--api-key-file", type=Path, default=Path("/etc/homelab/immich-go-api-key"))
    parser.add_argument("--state-file", type=Path, required=True)
    parser.add_argument("--name", action="append", dest="names", required=True)
    return parser.parse_args()


class ImmichApi:
    def __init__(self, server: str, key: str) -> None:
        self.base = server.rstrip("/") + "/api"
        self.key = key

    def request(self, method: str, path: str) -> Any:
        request = Request(
            self.base + path,
            method=method,
            headers={"x-api-key": self.key, "accept": "application/json"},
        )
        try:
            with urlopen(request, timeout=120) as response:
                payload = response.read()
        except HTTPError as error:
            raise RuntimeError(f"Immich API {method} {path} returned HTTP {error.code}") from error
        except URLError as error:
            raise RuntimeError(f"Immich API unavailable for {method} {path}: {error.reason}") from error
        return json.loads(payload) if payload else None

    def albums(self) -> list[dict[str, Any]]:
        payload = self.request("GET", "/albums")
        if not isinstance(payload, list):
            raise RuntimeError("Immich API did not return an album list")
        return payload


def matching_ids(albums: list[dict[str, Any]], names: set[str]) -> set[str]:
    return {
        album_id
        for album in albums
        if str(album.get("albumName", "")) in names
        and (album_id := str(album.get("id", "")))
    }


def atomic_write(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        json.dump(payload, handle, ensure_ascii=False, sort_keys=True)
        handle.write("\n")
        temporary = Path(handle.name)
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def main() -> int:
    args = parse_args()
    key = args.api_key_file.read_text(encoding="utf-8").strip()
    if not 20 <= len(key) <= 256 or re.fullmatch(r"[A-Za-z0-9_-]+", key) is None:
        raise SystemExit("Immich API key format is invalid.")
    api = ImmichApi(args.server, key)
    del key

    requested_names = set(args.names)
    if args.action == "snapshot":
        preserved_ids = sorted(matching_ids(api.albums(), requested_names))
        atomic_write(
            args.state_file,
            {
                "schema_version": 1,
                "created_at": datetime.now(timezone.utc).isoformat(),
                "names": sorted(requested_names),
                "preserved_ids": preserved_ids,
            },
        )
        print(f"EXCLUDED_ALBUM_SNAPSHOT_OK preserved={len(preserved_ids)}")
        return 0

    state = json.loads(args.state_file.read_text(encoding="utf-8"))
    if state.get("schema_version") != 1 or set(state.get("names", [])) != requested_names:
        raise SystemExit("Excluded-album snapshot does not match this import policy.")
    preserved_ids = set(state.get("preserved_ids", []))
    current_ids = matching_ids(api.albums(), requested_names)
    delete_ids = sorted(current_ids - preserved_ids)
    for album_id in delete_ids:
        api.request("DELETE", "/albums/" + quote(album_id, safe=""))
        digest = hashlib.sha256(album_id.encode()).hexdigest()[:12]
        print(f"EXCLUDED_ALBUM_DELETED id_sha256={digest}")

    remaining_new = matching_ids(api.albums(), requested_names) - preserved_ids
    if remaining_new:
        raise RuntimeError(f"Excluded album cleanup verification failed for {len(remaining_new)} album(s)")
    print(f"EXCLUDED_ALBUM_CLEANUP_OK deleted={len(delete_ids)} preserved={len(preserved_ids)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
