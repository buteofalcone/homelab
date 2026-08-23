"""Shared Google Takeout filename and format constants."""

import re

MEDIA_EXTENSIONS = {
    ".3gp", ".3gpp", ".avi", ".avif", ".bmp", ".dng", ".flv", ".gif",
    ".heic", ".heif", ".insp", ".jpeg", ".jpe", ".jpg", ".jp2", ".jxl",
    ".m2t", ".m2ts", ".m4v", ".mkv", ".mov", ".mp4", ".mpe", ".mpeg",
    ".mpg", ".mpo", ".mts", ".mxf", ".png", ".psd", ".raw", ".rw2",
    ".svg", ".tif", ".tiff", ".ts", ".webm", ".webp", ".wmv",
}
IMAGE_EXTENSIONS = MEDIA_EXTENSIONS - {
    ".3gp", ".3gpp", ".avi", ".flv", ".m2t", ".m2ts", ".m4v", ".mkv",
    ".mov", ".mp4", ".mpe", ".mpeg", ".mpg", ".mts", ".mxf", ".ts",
    ".webm", ".wmv",
}
VIDEO_EXTENSIONS = MEDIA_EXTENSIONS - IMAGE_EXTENSIONS
SIDECAR_SUFFIX = ".supplemental-metadata.json"
NUMBERED_RE = re.compile(r"(?:\(\d+\)|[ _-]\d+)$")
EDITED_TOKENS = ("edited", "відредаговано", "редаговано", "bearbeitet", "modifié", "editado")
