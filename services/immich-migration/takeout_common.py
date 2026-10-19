"""Shared Google Takeout filename and format constants."""

import re

MEDIA_EXTENSIONS = {
    ".3fr", ".3gp", ".3gpp", ".ari", ".arw", ".avi", ".avif", ".bmp",
    ".cap", ".cin", ".cr2", ".cr3", ".crw", ".dcr", ".dng", ".erf", ".fff", ".flv", ".gif",
    ".heic", ".heif", ".insp", ".insv", ".jpeg", ".jpe", ".jpg", ".jp2", ".jxl",
    ".iiq", ".k25", ".kdc", ".m2t", ".m2ts", ".m4v", ".mkv", ".mov", ".mp4", ".mpe", ".mpeg",
    ".mpg", ".mpo", ".mrw", ".mts", ".mxf", ".nef", ".nrw", ".orf", ".ori", ".pef", ".png",
    ".psd", ".raf", ".raw", ".rw2", ".rwl", ".sr2", ".srf", ".srw", ".svg", ".tif", ".tiff",
    ".ts", ".vob", ".webm", ".webp", ".wmv", ".x3f",
}
IMAGE_EXTENSIONS = MEDIA_EXTENSIONS - {
    ".3gp", ".3gpp", ".avi", ".flv", ".m2t", ".m2ts", ".m4v", ".mkv",
    ".insv", ".mov", ".mp4", ".mpe", ".mpeg", ".mpg", ".mts", ".mxf", ".ts",
    ".vob", ".webm", ".wmv",
}
VIDEO_EXTENSIONS = MEDIA_EXTENSIONS - IMAGE_EXTENSIONS
SIDECAR_SUFFIX = ".supplemental-metadata.json"
NUMBERED_RE = re.compile(r"\(\d+\)$")
EDITED_TOKENS = ("edited", "відредаговано", "редаговано", "bearbeitet", "modifié", "editado")
