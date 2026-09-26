#!/usr/bin/env python3
"""Daily light-touch verification of official grant pages.

This intentionally never invents grant calls. It verifies the source pages connected
to existing cards, records the result, and keeps any unavailable page visible for
human review. Add newly verified opportunities through the Hub's API/UI.
"""
import hashlib
import json
import sqlite3
import sys
from datetime import date, datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from app import DB_PATH, init_db

init_db()
now = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
con = sqlite3.connect(DB_PATH)
for row in con.execute("SELECT title, official_url, deadline FROM grants WHERE status='open'"):
    title, url, deadline = row
    previous = con.execute("SELECT detail FROM source_checks WHERE url=?", (url,)).fetchone()
    previous_fingerprint = ""
    if previous:
        try:
            previous_fingerprint = json.loads(previous[0] or "{}").get("fingerprint", "")
        except json.JSONDecodeError:
            pass
    try:
        req = Request(url, headers={"User-Agent": "RidniGrantHub/1.0 (+https://grants.butenko.online)"})
        with urlopen(req, timeout=25) as response:
            content = response.read(1024 * 1024)
            fingerprint = hashlib.sha256(content).hexdigest()[:16]
            status = "changed" if previous_fingerprint and previous_fingerprint != fingerprint else "reachable"
            detail = json.dumps({"http": response.status, "fingerprint": fingerprint, "final_url": response.geturl()}, ensure_ascii=False)
    except Exception as exc:
        status = "review"
        detail = json.dumps({"error": str(exc)[:180], "fingerprint": previous_fingerprint}, ensure_ascii=False)
    con.execute("INSERT INTO source_checks(url,label,checked_at,status,detail) VALUES (?,?,?,?,?) ON CONFLICT(url) DO UPDATE SET checked_at=excluded.checked_at,status=excluded.status,detail=excluded.detail", (url,title,now,status,detail))
    grant_status = "expired" if deadline and date.fromisoformat(deadline) < date.today() else "open"
    con.execute("UPDATE grants SET checked_at=?,updated_at=?,status=? WHERE official_url=?", (now,now,grant_status,url))
con.commit()
print(f"checked {con.execute('SELECT COUNT(*) FROM source_checks WHERE checked_at=?',(now,)).fetchone()[0]} official sources at {now}")
