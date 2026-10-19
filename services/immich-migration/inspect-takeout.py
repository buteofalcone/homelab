#!/usr/bin/env python3
"""Build a privacy-conscious inventory of an unpacked Google Photos Takeout."""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import tempfile
from typing import Any, Iterable

from takeout_common import EDITED_TOKENS, IMAGE_EXTENSIONS, MEDIA_EXTENSIONS, NUMBERED_RE, SIDECAR_SUFFIX, VIDEO_EXTENSIONS


def atomic_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")
        temporary = Path(handle.name)
    os.replace(temporary, path)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_json(path: Path) -> tuple[dict[str, Any] | None, str | None]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        return None, type(error).__name__
    return value if isinstance(value, dict) else None, None if isinstance(value, dict) else "not_object"


def walk_files(root: Path) -> Iterable[Path]:
    for directory, names, files in os.walk(root):
        names.sort()
        files.sort()
        base = Path(directory)
        for name in files:
            yield base / name


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--hash-duplicate-candidates", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root
    if not root.is_dir():
        raise SystemExit(f"Takeout root does not exist: {root}")

    counts: Counter[str] = Counter()
    extensions: Counter[str] = Counter()
    sidecar_fields: Counter[str] = Counter()
    sizes: dict[int, list[tuple[Path, str]]] = defaultdict(list)
    motion: dict[tuple[str, str], set[str]] = defaultdict(set)
    collision_names: dict[tuple[str, str, str], list[str]] = defaultdict(list)
    manifest: list[dict[str, Any]] = []
    malformed: list[dict[str, str]] = []

    for path in walk_files(root):
        relative = path.relative_to(root).as_posix()
        stat = path.stat()
        lower_name = path.name.casefold()
        suffix = path.suffix.casefold()
        path_id = hashlib.sha256(relative.encode("utf-8")).hexdigest()
        counts["all_files"] += 1
        counts["all_bytes"] += stat.st_size

        if suffix == ".json":
            counts["json_files"] += 1
            kind = "other_json"
            paired_path: Path | None = None
            if lower_name == "metadata.json":
                kind = "album_metadata"
                counts[kind] += 1
            elif lower_name.endswith(SIDECAR_SUFFIX):
                kind = "supplemental_metadata"
                counts[kind] += 1
                paired_path = path.with_name(path.name[: -len(SIDECAR_SUFFIX)])
                payload, error = safe_json(path)
                pairing = "direct" if paired_path.is_file() else "missing"
                if pairing == "missing" and payload is not None:
                    title = payload.get("title")
                    if isinstance(title, str) and title and (path.parent / title).is_file():
                        paired_path = path.parent / title
                        pairing = "inferred_title"
                counts[f"sidecar_{pairing}"] += 1
                if error:
                    counts["malformed_json"] += 1
                    malformed.append({"path_id": path_id, "error": error})
                elif payload is not None:
                    for key in (
                        "title", "description", "creationTime", "photoTakenTime", "geoData",
                        "geoDataExif", "googlePhotosOrigin", "favorited",
                    ):
                        if key in payload:
                            sidecar_fields[key] += 1
                    if payload.get("description"):
                        sidecar_fields["description_nonempty"] += 1
                    if payload.get("favorited") is True:
                        sidecar_fields["favorited_true"] += 1
                    geo = payload.get("geoDataExif") or payload.get("geoData") or {}
                    if isinstance(geo, dict) and (geo.get("latitude") or geo.get("longitude")):
                        sidecar_fields["gps_nonzero"] += 1
                    formatted = (payload.get("photoTakenTime") or {}).get("formatted", "")
                    if formatted:
                        sidecar_fields["capture_time_formatted"] += 1
                    if any(token in formatted for token in (" UTC", " GMT", " CET", " CEST", " EST", " EDT", " PST", " PDT")):
                        sidecar_fields["capture_time_zone_token"] += 1
            manifest.append({
                "path": relative,
                "path_id": path_id,
                "kind": kind,
                "bytes": stat.st_size,
                "paired": paired_path.is_file() if paired_path else None,
                "pairing": pairing if kind == "supplemental_metadata" else None,
            })
            continue

        extensions[suffix or "<none>"] += 1
        if suffix not in MEDIA_EXTENSIONS:
            counts["unsupported_or_auxiliary_files"] += 1
            manifest.append({"path": relative, "path_id": path_id, "kind": "auxiliary", "bytes": stat.st_size})
            continue

        media_kind = "image" if suffix in IMAGE_EXTENSIONS else "video"
        counts["media_files"] += 1
        counts[f"{media_kind}_files"] += 1
        normalized_stem = NUMBERED_RE.sub("", path.stem).casefold()
        if normalized_stem != path.stem.casefold():
            counts["numbered_suffix_media"] += 1
        collision_names[(str(path.parent), normalized_stem, suffix)].append(path_id)
        if any(token in path.stem.casefold() for token in EDITED_TOKENS):
            counts["edited_name_media"] += 1
        sizes[stat.st_size].append((path, path_id))
        motion[(str(path.parent), path.stem.casefold())].add(suffix)
        sidecar = path.with_name(path.name + SIDECAR_SUFFIX)
        manifest.append({
            "path": relative,
            "path_id": path_id,
            "kind": media_kind,
            "extension": suffix,
            "bytes": stat.st_size,
            "sidecar_direct": sidecar.is_file(),
        })

    duplicate_groups: list[dict[str, Any]] = []
    size_candidates = [items for size, items in sizes.items() if size > 0 and len(items) > 1]
    counts["same_size_candidate_groups"] = len(size_candidates)
    counts["same_size_candidate_files"] = sum(len(items) for items in size_candidates)
    if args.hash_duplicate_candidates:
        for items in size_candidates:
            hashes: dict[str, list[str]] = defaultdict(list)
            for path, path_id in items:
                hashes[sha256_file(path)].append(path_id)
            for digest, path_ids in hashes.items():
                if len(path_ids) > 1:
                    duplicate_groups.append({"sha256": digest, "path_ids": sorted(path_ids)})
        counts["exact_duplicate_groups"] = len(duplicate_groups)
        counts["exact_duplicate_files"] = sum(len(group["path_ids"]) for group in duplicate_groups)

    counts["same_stem_motion_candidates"] = sum(
        bool(exts & IMAGE_EXTENSIONS) and bool(exts & VIDEO_EXTENSIONS) for exts in motion.values()
    )
    collision_groups = [path_ids for path_ids in collision_names.values() if len(path_ids) > 1]
    counts["numbered_collision_groups"] = len(collision_groups)
    counts["numbered_collision_files"] = sum(len(path_ids) for path_ids in collision_groups)
    generated_at = datetime.now(timezone.utc).isoformat()
    report = {
        "schema_version": 1,
        "generated_at": generated_at,
        "root": str(root),
        "counts": dict(sorted(counts.items())),
        "extensions": dict(extensions.most_common()),
        "sidecar_field_presence": dict(sorted(sidecar_fields.items())),
        "content_hashing": "duplicate_candidates_only" if args.hash_duplicate_candidates else "disabled",
        "safety": {"source_modified": False, "descriptions_logged": False, "gps_values_logged": False},
    }

    output = args.output_dir
    output.mkdir(parents=True, exist_ok=True)
    atomic_json(output / "takeout-report.json", report)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=output, delete=False) as handle:
        for item in manifest:
            handle.write(json.dumps(item, ensure_ascii=False, sort_keys=True) + "\n")
        temporary = Path(handle.name)
    os.replace(temporary, output / "takeout-manifest.jsonl")
    atomic_json(output / "takeout-malformed-json.json", malformed)
    atomic_json(output / "takeout-duplicate-candidates.json", duplicate_groups)
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
