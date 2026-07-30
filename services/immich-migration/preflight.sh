#!/usr/bin/env bash
set -Eeuo pipefail

readonly sample_dir=/srv/storage/incoming/google-photos-takeout/sample
readonly max_sample_bytes=$((5 * 1024 * 1024 * 1024))

[[ ${EUID} -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
[[ -d ${sample_dir} ]] || { echo "Missing sample directory: ${sample_dir}" >&2; exit 1; }
find "${sample_dir}" -type l -print -quit | grep -q . && {
  echo 'Symlinks are not allowed in the Takeout sample.' >&2
  exit 1
}

python3 - "${sample_dir}" "${max_sample_bytes}" <<'PY'
import hashlib
import os
from pathlib import Path
import sys
import zipfile

root = Path(sys.argv[1])
maximum = int(sys.argv[2])
media_extensions = {
    ".3gp", ".avi", ".gif", ".heic", ".jpeg", ".jpg", ".m4v", ".mkv",
    ".mov", ".mp4", ".mpeg", ".mpg", ".png", ".tif", ".tiff", ".webp",
}
files = sorted(path for path in root.rglob("*") if path.is_file())
if not files:
    raise SystemExit("The Takeout sample is empty.")

total_bytes = sum(path.stat().st_size for path in files)
if total_bytes > maximum:
    raise SystemExit(f"The sample is too large: {total_bytes} bytes (maximum {maximum}).")

archives = [path for path in files if path.suffix.casefold() == ".zip"]
json_count = 0
media_count = 0
if archives:
    non_archives = [path for path in files if path.suffix.casefold() != ".zip"]
    if non_archives:
        raise SystemExit("Use either Takeout ZIP files or one unpacked sample, not both.")
    for archive in archives:
        try:
            with zipfile.ZipFile(archive) as package:
                bad = package.testzip()
                if bad:
                    raise SystemExit(f"Corrupt ZIP member in {archive.name}: {bad}")
                for name in package.namelist():
                    suffix = Path(name).suffix.casefold()
                    json_count += suffix == ".json"
                    media_count += suffix in media_extensions
        except zipfile.BadZipFile as error:
            raise SystemExit(f"Invalid ZIP archive {archive.name}: {error}") from error
else:
    json_count = sum(path.suffix.casefold() == ".json" for path in files)
    media_count = sum(path.suffix.casefold() in media_extensions for path in files)

if json_count < 1:
    raise SystemExit("No Google JSON sidecar was found in the sample.")
if media_count < 1:
    raise SystemExit("No supported photo or video was found in the sample.")

manifest = hashlib.sha256()
for path in files:
    relative = path.relative_to(root).as_posix().encode()
    manifest.update(len(relative).to_bytes(8, "big"))
    manifest.update(relative)
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            manifest.update(chunk)

print(
    "IMMICH_TAKEOUT_PREFLIGHT_OK "
    f"files={len(files)} archives={len(archives)} media={media_count} json={json_count} "
    f"bytes={total_bytes} sha256={manifest.hexdigest()}"
)
PY
