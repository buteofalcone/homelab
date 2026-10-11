#!/usr/bin/env python3
"""Daily light-touch verification of official grant pages.

This intentionally never invents grant calls. It verifies the source pages connected
to existing cards, records the result, and keeps any unavailable page visible for
human review. Add newly verified opportunities through the Hub's API/UI.
"""
import hashlib
import json
import re
import sqlite3
import sys
import uuid
from datetime import date, datetime, timezone
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from app import DB_PATH, get_search_settings, init_db

EU_SEARCH_API = "https://api.tech.ec.europa.eu/search-api/prod/rest/search"
USER_AGENT = "RidniGrantHub/1.1 (+https://grants.butenko.online)"


def first(metadata, key, default=""):
    value = metadata.get(key, default)
    return value[0] if isinstance(value, list) and value else value or default


def plain(value):
    return re.sub(r"<[^>]+>", " ", str(value or ""))


def check_source(con, label, url, checked_at, extra=None):
    previous = con.execute("SELECT detail FROM source_checks WHERE url=?", (url,)).fetchone()
    previous_fingerprint = ""
    if previous:
        try:
            previous_fingerprint = json.loads(previous[0] or "{}").get("fingerprint", "")
        except json.JSONDecodeError:
            pass
    try:
        req = Request(url, headers={"User-Agent": USER_AGENT})
        with urlopen(req, timeout=25) as response:
            content = response.read(1024 * 1024)
            fingerprint = hashlib.sha256(content).hexdigest()[:16]
            status = "changed" if previous_fingerprint and previous_fingerprint != fingerprint else "reachable"
            payload = {"http": response.status, "fingerprint": fingerprint, "final_url": response.geturl(), **(extra or {})}
    except Exception as exc:
        status = "review"
        payload = {"error": str(exc)[:180], "fingerprint": previous_fingerprint, **(extra or {})}
    con.execute(
        "INSERT INTO source_checks(url,label,checked_at,status,detail) VALUES (?,?,?,?,?) "
        "ON CONFLICT(url) DO UPDATE SET label=excluded.label,checked_at=excluded.checked_at,status=excluded.status,detail=excluded.detail",
        (url, label, checked_at, status, json.dumps(payload, ensure_ascii=False)),
    )


def multipart_json(fields):
    boundary = "----RidniGrantHub" + uuid.uuid4().hex
    chunks = []
    for name, value in fields.items():
        chunks.extend([
            f"--{boundary}\r\n".encode(),
            f'Content-Disposition: form-data; name="{name}"; filename="blob"\r\n'.encode(),
            b"Content-Type: application/json\r\n\r\n",
            json.dumps(value, ensure_ascii=False).encode(),
            b"\r\n",
        ])
    chunks.append(f"--{boundary}--\r\n".encode())
    return b"".join(chunks), boundary


def search_eu_program(program, settings):
    statuses = ["31094502"]
    if settings.get("include_forthcoming", True):
        statuses.append("31094501")
    types = ["1", "2"]
    if settings.get("include_cascade_funding", True):
        types.append("8")
    must = [
        {"terms": {"type": types}},
        {"terms": {"status": statuses}},
        {"term": {"programmePeriod": "2021 - 2027"}},
    ]
    if program.get("id") == "cerv":
        must.append({"terms": {"frameworkProgramme": ["43251589"]}})
    fields = {
        "query": {"bool": {"must": must}},
        "languages": ["en"],
        "sort": {"field": "sortStatus", "order": "ASC"},
        "displayFields": ["type", "identifier", "reference", "title", "status", "startDate", "deadlineDate", "frameworkProgramme", "typesOfAction"],
    }
    body, boundary = multipart_json(fields)
    params = urlencode({"apiKey": "SEDIA", "text": program.get("query") or "*", "pageSize": "50", "pageNumber": "1"})
    request = Request(
        EU_SEARCH_API + "?" + params,
        data=body,
        headers={"User-Agent": USER_AGENT, "Accept": "application/json", "Referer": "https://ec.europa.eu/info/funding-tenders/opportunities/portal/", "Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )
    with urlopen(request, timeout=40) as response:
        return json.load(response).get("results", [])


def score_candidate(result, program, settings):
    metadata = result.get("metadata", {})
    haystack = " ".join([
        plain(first(metadata, "title")), plain(result.get("summary")), plain(result.get("content")),
        plain(first(metadata, "description")), plain(first(metadata, "callIdentifier")),
    ]).lower()
    if any(word.lower() in haystack for word in settings.get("excluded_keywords", [])):
        return 0, []
    matched = [word for word in settings.get("keywords", []) if word.lower() in haystack]
    score = 25 + min(60, len(matched) * 10)
    if settings.get("search_breadth") == "broad":
        score += 5
    if settings.get("search_breadth") == "strict" and len(matched) < 2:
        score = 0
    return min(100, score), matched

init_db()
now = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
con = sqlite3.connect(DB_PATH)
settings = get_search_settings(con)
for row in con.execute("SELECT title, official_url, deadline FROM grants WHERE status='open'"):
    title, url, deadline = row
    check_source(con, title, url, now, {"kind": "grant"})
    grant_status = "expired" if deadline and date.fromisoformat(deadline) < date.today() else "open"
    con.execute("UPDATE grants SET checked_at=?,updated_at=?,status=? WHERE official_url=?", (now,now,grant_status,url))

known_urls = {row[0] for row in con.execute("SELECT official_url FROM grants")}
found = 0
for program in settings.get("programs", []):
    if not program.get("enabled"):
        continue
    check_source(con, "Програма: " + program["label"], program["official_url"], now, {"kind": "program", "query": program.get("query", "")})
    if not program.get("api_search", True):
        continue
    try:
        results = search_eu_program(program, settings)
    except Exception as exc:
        check_source(con, "EU API: " + program["label"], EU_SEARCH_API + "?program=" + program["id"], now, {"kind": "api", "error": str(exc)[:180]})
        continue
    for result in results:
        metadata = result.get("metadata", {})
        url = result.get("url") or first(metadata, "url")
        if not url or url in known_urls or "/screen/opportunities/" not in url:
            continue
        relevance, matched = score_candidate(result, program, settings)
        if relevance < int(settings.get("minimum_relevance", 35)):
            continue
        title = plain(first(metadata, "title") or result.get("summary")).strip()
        if not title:
            continue
        raw_deadline = str(first(metadata, "deadlineDate"))
        deadline_match = re.search(r"\d{4}-\d{2}-\d{2}", raw_deadline)
        deadline = deadline_match.group(0) if deadline_match else ""
        status = str(first(metadata, "status", "open"))
        con.execute(
            "INSERT INTO discovery_candidates(official_url,title,program,deadline,status,relevance,matched_keywords,payload,discovered_at,updated_at) "
            "VALUES (?,?,?,?,?,?,?,?,?,?) ON CONFLICT(official_url) DO UPDATE SET title=excluded.title,program=excluded.program,"
            "deadline=excluded.deadline,status=excluded.status,relevance=excluded.relevance,matched_keywords=excluded.matched_keywords,"
            "payload=excluded.payload,updated_at=excluded.updated_at",
            (url, title, program["label"], deadline, status, relevance, json.dumps(matched, ensure_ascii=False), json.dumps(result, ensure_ascii=False), now, now),
        )
        found += 1
con.commit()
checks = con.execute("SELECT COUNT(*) FROM source_checks WHERE checked_at=?", (now,)).fetchone()[0]
print(f"checked {checks} official sources; retained {found} discovery candidates at {now}")
