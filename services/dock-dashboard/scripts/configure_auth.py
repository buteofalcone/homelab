#!/usr/bin/env python3
from __future__ import annotations

import argparse
import getpass
import grp
import os
import re
import secrets
import tempfile
from pathlib import Path

from argon2 import PasswordHasher


def quote(value: str) -> str:
    return "'" + value.replace("'", "\\'") + "'"


def write_atomic(path: Path, values: dict[str, str], group: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"{key}={quote(value)}\n" for key, value in values.items()]
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.writelines(lines)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o640)
        os.chown(temporary, 0, grp.getgrnam(group).gr_gid)
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def parse_existing(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^([A-Z0-9_]+)=(.*)$", line)
        if not match:
            continue
        value = match.group(2).strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
            value = value[1:-1]
        values[match.group(1)] = value
    return values


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="/etc/homelab/dashboard.env")
    parser.add_argument("--group", default="hp-dashboard")
    parser.add_argument("--username", default="butenko")
    parser.add_argument("--generate-bootstrap", action="store_true")
    args = parser.parse_args()
    path = Path(args.config)
    values = parse_existing(path)

    if args.generate_bootstrap:
        password = secrets.token_urlsafe(18)
        bootstrap_path = Path("/root/hp-dashboard-initial-password")
        bootstrap_path.write_text(password + "\n", encoding="utf-8")
        os.chmod(bootstrap_path, 0o600)
    else:
        first = getpass.getpass("New HP dashboard password: ")
        second = getpass.getpass("Repeat password: ")
        if first != second:
            raise SystemExit("Passwords do not match")
        if len(first) < 12:
            raise SystemExit("Password must contain at least 12 characters")
        password = first
        try:
            Path("/root/hp-dashboard-initial-password").unlink()
        except FileNotFoundError:
            pass

    values.update({
        "DASHBOARD_USERNAME": args.username,
        "DASHBOARD_PASSWORD_HASH": PasswordHasher().hash(password),
        "DASHBOARD_HOST": values.get("DASHBOARD_HOST", "dashboard.butenko.online"),
        "DASHBOARD_PROXY_TOKEN": values.get("DASHBOARD_PROXY_TOKEN", secrets.token_urlsafe(32)),
        "DASHBOARD_SESSION_IDLE_SECONDS": "1800",
        "DASHBOARD_SESSION_MAX_SECONDS": "28800",
    })
    write_atomic(path, values, args.group)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
