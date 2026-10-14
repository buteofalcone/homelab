#!/usr/bin/env python3
"""Copy a bounded, representative Takeout sample without altering the source."""

from __future__ import annotations

import argparse
from collections import defaultdict
import json
from pathlib import Path
import re
import shutil

from takeout_common import EDITED_TOKENS, IMAGE_EXTENSIONS, MEDIA_EXTENSIONS, NUMBERED_RE, SIDECAR_SUFFIX, VIDEO_EXTENSIONS


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--destination", required=True, type=Path)
    parser.add_argument("--max-bytes", type=int, default=2 * 1024**3)
    parser.add_argument("--max-media", type=int, default=300)
    return parser.parse_args()


def metadata_features(sidecar: Path) -> set[str]:
    if not sidecar.is_file():
        return {"unmatched"}
    try:
        payload = json.loads(sidecar.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return {"malformed-sidecar"}
    features = {"matched"}
    if payload.get("description"):
        features.add("description")
    if payload.get("favorited") is True:
        features.add("favorite")
    geo = payload.get("geoDataExif") or payload.get("geoData") or {}
    features.add("gps" if isinstance(geo, dict) and (geo.get("latitude") or geo.get("longitude")) else "no-gps")
    return features


def main() -> int:
    args = parse_args()
    if not args.root.is_dir():
        raise SystemExit(f"Missing Takeout root: {args.root}")
    if args.destination.exists() and any(args.destination.iterdir()):
        raise SystemExit(f"Sample destination is not empty: {args.destination}")

    candidates: dict[str, list[Path]] = defaultdict(list)
    for path in args.root.rglob("*"):
        if not path.is_file() or path.suffix.casefold() not in MEDIA_EXTENSIONS:
            continue
        suffix = path.suffix.casefold()
        categories = {"image" if suffix in IMAGE_EXTENSIONS else "video"}
        if suffix in {".heic", ".heif"}:
            categories.add("heic")
        if suffix in {".raw", ".dng", ".rw2"}:
            categories.add("raw")
        if re.search(r"Photos from 19\d\d", path.parent.name):
            categories.add("historical")
        if NUMBERED_RE.search(path.stem):
            categories.add("numbered")
        if any(token in path.stem.casefold() for token in EDITED_TOKENS):
            categories.add("edited")
        categories.update(metadata_features(path.with_name(path.name + SIDECAR_SUFFIX)))
        if suffix in IMAGE_EXTENSIONS and any(path.with_suffix(video).is_file() for video in VIDEO_EXTENSIONS):
            categories.add("motion")
        for category in categories:
            if len(candidates[category]) < 50:
                candidates[category].append(path)
        if len(candidates["general"]) < args.max_media * 4:
            candidates["general"].append(path)

    priority = (
        "motion", "heic", "video", "favorite", "gps", "no-gps", "description",
        "historical", "numbered", "edited", "raw", "unmatched", "malformed-sidecar", "image", "general",
    )
    selected: list[Path] = []
    selected_set: set[Path] = set()
    estimated_bytes = 0
    for category in priority:
        for path in candidates.get(category, []):
            if path in selected_set:
                continue
            related = {path, path.with_name(path.name + SIDECAR_SUFFIX), path.parent / "metadata.json"}
            for other_suffix in VIDEO_EXTENSIONS | IMAGE_EXTENSIONS:
                paired = path.with_suffix(other_suffix)
                if paired.is_file() and paired.stem.casefold() == path.stem.casefold():
                    related.update({paired, paired.with_name(paired.name + SIDECAR_SUFFIX)})
            additional = sum(item.stat().st_size for item in related if item.is_file())
            if selected and (len(selected) >= args.max_media or estimated_bytes + additional > args.max_bytes):
                continue
            selected.append(path)
            selected_set.add(path)
            estimated_bytes += additional

    args.destination.mkdir(parents=True, exist_ok=True)
    copied: set[Path] = set()
    for media in selected:
        related = {media, media.with_name(media.name + SIDECAR_SUFFIX), media.parent / "metadata.json"}
        for other_suffix in VIDEO_EXTENSIONS | IMAGE_EXTENSIONS:
            paired = media.with_suffix(other_suffix)
            if paired.is_file() and paired.stem.casefold() == media.stem.casefold():
                related.update({paired, paired.with_name(paired.name + SIDECAR_SUFFIX)})
        for source in related:
            if not source.is_file() or source in copied:
                continue
            target = args.destination / source.relative_to(args.root)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            copied.add(source)

    manifest = {
        "schema_version": 1,
        "source": str(args.root),
        "destination": str(args.destination),
        "selected_media": len(selected),
        "copied_files": len(copied),
        "copied_bytes": sum(path.stat().st_size for path in copied),
        "source_modified": False,
    }
    (args.destination / "sample-manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(json.dumps(manifest, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
