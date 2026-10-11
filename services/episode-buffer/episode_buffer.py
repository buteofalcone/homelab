#!/usr/bin/env python3
"""Maintain a small rolling Sonarr episode buffer from Jellyfin watch state."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


STATE_VERSION = 1


def log(message: str) -> None:
    print(message, flush=True)


def die(message: str) -> None:
    raise RuntimeError(message)


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def parse_date(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def normalize(value: str) -> str:
    value = unicodedata.normalize("NFKD", value).casefold()
    return re.sub(r"[\W_]+", "", value, flags=re.UNICODE)


def env_int(name: str, default: int, minimum: int = 0) -> int:
    raw = os.environ.get(name, str(default))
    try:
        value = int(raw)
    except ValueError as exc:
        raise RuntimeError(f"{name} must be an integer") from exc
    if value < minimum:
        die(f"{name} must be at least {minimum}")
    return value


class Api:
    def __init__(self, base_url: str, token: str, token_header: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.token_header = token_header

    def request(
        self,
        method: str,
        path: str,
        *,
        query: dict[str, Any] | None = None,
        body: Any | None = None,
    ) -> Any:
        url = f"{self.base_url}{path}"
        if query:
            url += "?" + urllib.parse.urlencode(query, doseq=True)
        headers = {self.token_header: self.token, "Accept": "application/json"}
        data = None
        if body is not None:
            headers["Content-Type"] = "application/json"
            data = json.dumps(body).encode("utf-8")
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = response.read()
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")[:500]
            raise RuntimeError(f"{method} {path} returned HTTP {exc.code}: {detail}") from exc
        except urllib.error.URLError as exc:
            raise RuntimeError(f"{method} {path} failed: {exc.reason}") from exc
        if not payload:
            return None
        return json.loads(payload)

    def get(self, path: str, query: dict[str, Any] | None = None) -> Any:
        return self.request("GET", path, query=query)

    def post(self, path: str, body: Any) -> Any:
        return self.request("POST", path, body=body)

    def put(self, path: str, body: Any) -> Any:
        return self.request("PUT", path, body=body)

    def delete(self, path: str) -> Any:
        return self.request("DELETE", path)


class State:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.data: dict[str, Any] = {
            "version": STATE_VERSION,
            "initialized": False,
            "seen_played_ids": [],
            "processed": {},
            "dry_run_candidates": {},
        }
        if path.exists():
            self.data = json.loads(path.read_text(encoding="utf-8"))
            if self.data.get("version") != STATE_VERSION:
                die("Unsupported episode-buffer state version")

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.data["last_run_utc"] = utc_now().isoformat()
        fd, temp_name = tempfile.mkstemp(prefix="state.", suffix=".json", dir=self.path.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(self.data, handle, ensure_ascii=False, indent=2, sort_keys=True)
                handle.write("\n")
            os.chmod(temp_name, 0o600)
            os.replace(temp_name, self.path)
        finally:
            if os.path.exists(temp_name):
                os.unlink(temp_name)


class EpisodeBuffer:
    def __init__(self) -> None:
        jellyfin_key = os.environ.get("JELLYFIN_API_KEY", "")
        sonarr_key = os.environ.get("SONARR_API_KEY", "")
        if not jellyfin_key or not sonarr_key:
            die("Jellyfin and Sonarr API keys are required")
        self.username = os.environ.get("JELLYFIN_USERNAME", "").strip()
        if not self.username:
            die("JELLYFIN_USERNAME is required")
        self.jellyfin = Api(
            os.environ.get("JELLYFIN_URL", "http://127.0.0.1:8096"),
            jellyfin_key,
            "X-Emby-Token",
        )
        self.sonarr = Api(os.environ["SONARR_URL"], sonarr_key, "X-Api-Key")
        self.state = State(Path(os.environ.get("EPISODE_BUFFER_STATE", "/srv/appdata/episode-buffer/state.json")))
        self.dry_run = os.environ.get("EPISODE_BUFFER_DRY_RUN", "true").lower() != "false"
        self.buffer_size = env_int("EPISODE_BUFFER_SIZE", 3, 1)
        self.grace = timedelta(hours=env_int("EPISODE_BUFFER_GRACE_HOURS", 24, 0))
        self.recycle_days = env_int("EPISODE_BUFFER_RECYCLE_DAYS", 7, 1)
        self.manage_all = os.environ.get("EPISODE_BUFFER_MANAGE_ALL", "true").lower() != "false"
        self.managed_tag = os.environ.get("EPISODE_BUFFER_MANAGED_TAG", "rolling-3")
        self.keep_tag = os.environ.get("EPISODE_BUFFER_KEEP_TAG", "keep")
        self.user = self._find_user()
        self.tags = {item["id"]: item["label"] for item in self.sonarr.get("/api/v3/tag")}
        self.series = self.sonarr.get("/api/v3/series")

    def _find_user(self) -> dict[str, Any]:
        matches = [user for user in self.jellyfin.get("/Users") if user.get("Name") == self.username]
        if len(matches) != 1:
            names = ", ".join(sorted(user.get("Name", "?") for user in self.jellyfin.get("/Users")))
            die(f"Jellyfin user {self.username!r} was not found exactly once; available users: {names}")
        return matches[0]

    def played_episodes(self) -> list[dict[str, Any]]:
        result = self.jellyfin.get(
            f"/Users/{self.user['Id']}/Items",
            {
                "Recursive": "true",
                "IncludeItemTypes": "Episode",
                "Filters": "IsPlayed",
                "Fields": "Path,ProviderIds,SeriesId,UserData",
                "EnableUserData": "true",
                "Limit": 100000,
            },
        )
        return result.get("Items", [])

    def sonarr_series_for(self, jellyfin_episode: dict[str, Any]) -> dict[str, Any] | None:
        series_id = jellyfin_episode.get("SeriesId")
        provider_ids: dict[str, Any] = {}
        if series_id:
            item = self.jellyfin.get(f"/Users/{self.user['Id']}/Items/{series_id}")
            provider_ids = item.get("ProviderIds", {})
        tvdb = str(provider_ids.get("Tvdb", ""))
        if tvdb:
            matches = [series for series in self.series if str(series.get("tvdbId", "")) == tvdb]
            if len(matches) == 1:
                return matches[0]
        wanted = normalize(jellyfin_episode.get("SeriesName", ""))
        matches = [series for series in self.series if normalize(series.get("title", "")) == wanted]
        return matches[0] if len(matches) == 1 else None

    def tag_labels(self, series: dict[str, Any]) -> set[str]:
        return {self.tags.get(tag_id, "") for tag_id in series.get("tags", [])}

    @staticmethod
    def episode_key(episode: dict[str, Any]) -> tuple[int, int]:
        return int(episode.get("seasonNumber", 0)), int(episode.get("episodeNumber", 0))

    def process_series(self, series: dict[str, Any], watched: list[dict[str, Any]]) -> None:
        labels = self.tag_labels(series)
        if self.keep_tag in labels:
            log(f"SKIP_KEEP series={series['title']}")
            return
        if not self.manage_all and self.managed_tag not in labels:
            log(f"SKIP_UNMANAGED series={series['title']} required_tag={self.managed_tag}")
            return

        episodes = self.sonarr.get("/api/v3/episode", {"seriesId": series["id"]})
        episodes = sorted((item for item in episodes if item.get("seasonNumber", 0) > 0), key=self.episode_key)
        by_key = {self.episode_key(item): item for item in episodes}
        matched: list[tuple[dict[str, Any], dict[str, Any]]] = []
        for item in watched:
            key = (int(item.get("ParentIndexNumber", 0)), int(item.get("IndexNumber", 0)))
            if key in by_key:
                matched.append((item, by_key[key]))
        if not matched:
            log(f"SKIP_NO_MATCH series={series['title']}")
            return

        matched.sort(key=lambda pair: self.episode_key(pair[1]))
        furthest = matched[-1][1]
        furthest_key = self.episode_key(furthest)
        following = [item for item in episodes if self.episode_key(item) > furthest_key][: self.buffer_size]
        following_ids = {item["id"] for item in following}

        for jellyfin_item, sonarr_episode in matched:
            episode_id = str(jellyfin_item["Id"])
            label = f"{series['title']} S{sonarr_episode['seasonNumber']:02d}E{sonarr_episode['episodeNumber']:02d}"
            file_id = int(sonarr_episode.get("episodeFileId") or 0)
            if file_id:
                linked_episodes = [item for item in episodes if int(item.get("episodeFileId") or 0) == file_id]
                if len(linked_episodes) > 1:
                    log(f"SKIP_MULTI_EPISODE_FILE {label} file_id={file_id} episodes={len(linked_episodes)}")
                    continue
            if self.dry_run:
                log(f"DRY_RUN_RECYCLE {label}")
                self.state.data["dry_run_candidates"][episode_id] = {
                    "label": label,
                    "observed_utc": utc_now().isoformat(),
                }
                continue
            if sonarr_episode.get("monitored"):
                updated = dict(sonarr_episode)
                updated["monitored"] = False
                self.sonarr.put(f"/api/v3/episode/{sonarr_episode['id']}", updated)
                sonarr_episode["monitored"] = False
            if file_id:
                self.sonarr.delete(f"/api/v3/episodefile/{file_id}")
            self.state.data["processed"][episode_id] = {
                "label": label,
                "processed_utc": utc_now().isoformat(),
                "episode_file_id": file_id,
            }
            log(f"RECYCLED {label} file_id={file_id}")

        if self.dry_run:
            for item in following:
                status = "present" if item.get("hasFile") else "missing"
                log(f"DRY_RUN_BUFFER series={series['title']} S{item['seasonNumber']:02d}E{item['episodeNumber']:02d} {status}")
            return

        search_ids: list[int] = []
        now = utc_now()
        for item in episodes:
            should_monitor = item["id"] in following_ids
            if bool(item.get("monitored")) != should_monitor:
                updated = dict(item)
                updated["monitored"] = should_monitor
                self.sonarr.put(f"/api/v3/episode/{item['id']}", updated)
            aired = parse_date(item.get("airDateUtc"))
            if should_monitor and not item.get("hasFile") and aired and aired <= now:
                search_ids.append(item["id"])
        if search_ids:
            self.sonarr.post("/api/v3/command", {"name": "EpisodeSearch", "episodeIds": search_ids})
        log(f"BUFFER_UPDATED series={series['title']} next={len(following)} searches={len(search_ids)}")

    def ensure_sonarr_policy(self, mutate: bool) -> None:
        tags = self.sonarr.get("/api/v3/tag")
        labels = {item["label"] for item in tags}
        for label in (self.managed_tag, self.keep_tag):
            if label not in labels:
                if not mutate:
                    die(f"Missing Sonarr tag: {label}")
                self.sonarr.post("/api/v3/tag", {"label": label})
                log(f"TAG_CREATED {label}")
        config = self.sonarr.get("/api/v3/config/mediamanagement")
        expected_path = "/data/recycle/sonarr"
        if config.get("recycleBin") != expected_path or int(config.get("recycleBinCleanupDays") or 0) != self.recycle_days:
            if not mutate:
                die("Sonarr Recycle Bin policy does not match the tracked episode-buffer policy")
            updated = dict(config)
            updated["recycleBin"] = expected_path
            updated["recycleBinCleanupDays"] = self.recycle_days
            self.sonarr.put("/api/v3/config/mediamanagement", updated)
            log(f"SONARR_RECYCLE_POLICY_OK path={expected_path} days={self.recycle_days}")

    def baseline(self, reset: bool = False) -> None:
        played = self.played_episodes()
        if self.state.data.get("initialized") and not reset:
            log("EPISODE_BUFFER_BASELINE_ALREADY_EXISTS")
            return
        self.state.data["seen_played_ids"] = sorted(str(item["Id"]) for item in played)
        self.state.data["initialized"] = True
        self.state.data["baseline_utc"] = utc_now().isoformat()
        if reset:
            self.state.data["dry_run_candidates"] = {}
        self.state.save()
        log(f"EPISODE_BUFFER_BASELINE_OK played={len(played)}")

    def run(self) -> None:
        self.ensure_sonarr_policy(mutate=False)
        if not self.state.data.get("initialized"):
            self.baseline()
            return
        played = self.played_episodes()
        seen = set(self.state.data.get("seen_played_ids", []))
        processed = set(self.state.data.get("processed", {}))
        cutoff = utc_now() - self.grace
        candidates: list[dict[str, Any]] = []
        for item in played:
            item_id = str(item["Id"])
            if item_id in seen or item_id in processed:
                continue
            last_played = parse_date(item.get("UserData", {}).get("LastPlayedDate"))
            if not last_played or last_played > cutoff:
                continue
            candidates.append(item)

        grouped: dict[int, tuple[dict[str, Any], list[dict[str, Any]]]] = {}
        unmatched = 0
        for item in candidates:
            series = self.sonarr_series_for(item)
            if not series:
                unmatched += 1
                log(f"SKIP_SERIES_NOT_FOUND title={item.get('SeriesName', '?')}")
                continue
            grouped.setdefault(series["id"], (series, []))[1].append(item)
        for series, items in grouped.values():
            self.process_series(series, items)
        if not self.dry_run:
            seen.update(str(item["Id"]) for item in candidates)
            self.state.data["seen_played_ids"] = sorted(seen)
        self.state.save()
        mode = "dry-run" if self.dry_run else "active"
        log(f"EPISODE_BUFFER_RUN_OK mode={mode} candidates={len(candidates)} series={len(grouped)} unmatched={unmatched}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("prepare", "baseline", "reset-baseline", "run", "verify"))
    args = parser.parse_args()
    try:
        app = EpisodeBuffer()
        if args.command == "prepare":
            app.ensure_sonarr_policy(mutate=True)
            log("EPISODE_BUFFER_PREPARE_OK")
        elif args.command == "baseline":
            app.baseline()
        elif args.command == "reset-baseline":
            app.baseline(reset=True)
        elif args.command == "verify":
            app.ensure_sonarr_policy(mutate=False)
            log(f"EPISODE_BUFFER_VERIFY_OK user={app.username} mode={'dry-run' if app.dry_run else 'active'}")
        else:
            app.run()
    except Exception as exc:  # deliberate single-line systemd error
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
