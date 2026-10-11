#!/usr/bin/env python3
"""Ridni Grant Hub — dependency-free private workspace."""
from __future__ import annotations

import json
import os
import sqlite3
import subprocess
import sys
import threading
from datetime import datetime, timezone
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent
PUBLIC = ROOT / "public"
DATA = ROOT / "data"
DB_PATH = Path(os.environ.get("GRANTS_DB", DATA / "grants.sqlite"))
LOCK = threading.Lock()
SEARCH_LOCK = threading.Lock()

DEFAULT_SEARCH_SETTINGS = {
    "programs": [
        {"id": "eed", "label": "EED — Apply for Support", "enabled": True, "official_url": "https://democracyendowment.eu/support", "query": "democracy civic participation culture Ukraine", "api_search": False},
        {"id": "visegrad-plus", "label": "Visegrad+ Grants", "enabled": True, "official_url": "https://www.visegradfund.org/visegrad-plus-grants-apply", "query": "Visegrad+ culture heritage Ukraine", "api_search": False},
        {"id": "creative-europe", "label": "Creative Europe — Culture", "enabled": True, "official_url": "https://culture.ec.europa.eu/creative-europe/creative-europe-culture", "query": "Creative Europe culture heritage"},
        {"id": "horizon-cl2", "label": "Horizon Europe — Cluster 2", "enabled": True, "official_url": "https://research-and-innovation.ec.europa.eu/funding/funding-opportunities/funding-programmes-and-open-calls/horizon-europe/cluster-2-culture-creativity-and-inclusive-society_en", "query": "HORIZON CL2 heritage culture democracy"},
        {"id": "digital-heritage", "label": "Digital Europe / Europeana / Cultural Heritage Cloud", "enabled": True, "official_url": "https://digital-strategy.ec.europa.eu/en/policies/cultural-heritage", "query": "digital cultural heritage Europeana data space"},
        {"id": "eap", "label": "Endangered Archives Programme", "enabled": True, "official_url": "https://eap.bl.uk/", "query": "Endangered Archives Programme", "api_search": False},
        {"id": "meap", "label": "Modern Endangered Archives Program", "enabled": True, "official_url": "https://meap.library.ucla.edu/call-for-applications/", "query": "Modern Endangered Archives Program", "api_search": False},
        {"id": "emkp", "label": "Endangered Material Knowledge Programme", "enabled": True, "official_url": "https://www.emkp.org/digitisation-grants/", "query": "endangered material knowledge digitisation", "api_search": False},
        {"id": "heritage-hub", "label": "European Heritage Hub — Funding opportunities", "enabled": True, "official_url": "https://www.europeanheritagehub.eu/funding-opportunities/", "query": "European heritage grants", "api_search": False},
        {"id": "erasmus", "label": "Erasmus+ — Opportunities for organisations", "enabled": True, "official_url": "https://erasmus-plus.ec.europa.eu/opportunities/opportunities-for-organisations", "query": "Erasmus heritage adult education digital"},
        {"id": "eea", "label": "EEA and Norway Grants — Culture", "enabled": True, "official_url": "https://eeagrants.org/topics-programmes/culture", "query": "EEA Norway Grants culture heritage"},
        {"id": "uk", "label": "AHRC — Funding opportunities", "enabled": True, "official_url": "https://www.ukri.org/councils/ahrc/", "query": "AHRC archives heritage digital humanities"},
        {"id": "north-america", "label": "NEH / IMLS / SSHRC programmes", "enabled": True, "official_url": "https://www.neh.gov/grants", "query": "NEH IMLS SSHRC archives humanities"},
        {"id": "cerv", "label": "CERV programme", "enabled": True, "official_url": "https://commission.europa.eu/funding-tenders/find-funding/eu-funding-programmes/citizens-equality-rights-and-values-programme/citizens-equality-rights-and-values-programme-overview_en", "query": "CERV"},
    ],
    "keywords": ["genealogy", "archives", "digitisation", "OCR", "HTR", "historical records", "language heritage", "dialects", "public history", "crowdsourcing", "LLM indexing", "civic memory"],
    "excluded_keywords": ["construction", "agriculture", "clinical", "mobility", "energy infrastructure"],
    "geographies": ["Ukraine", "EU and associated countries", "Europe", "Worldwide", "UK with international partners", "US/Canada with international partners"],
    "applicant_modes": {"direct_fop": True, "ngo_or_university": True, "partner_only": True},
    "include_forthcoming": True,
    "include_cascade_funding": True,
    "official_sources_only": True,
    "minimum_relevance": 35,
    "search_breadth": "broad",
}


def now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def db() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    return con


def init_db() -> None:
    with db() as con:
        con.executescript("""
        CREATE TABLE IF NOT EXISTS profile (id INTEGER PRIMARY KEY CHECK(id=1), payload TEXT NOT NULL, updated_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS tags (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL, color TEXT NOT NULL DEFAULT '#2f6f66');
        CREATE TABLE IF NOT EXISTS grants (
          id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, funder TEXT NOT NULL, official_url TEXT NOT NULL,
          deadline TEXT, timezone TEXT, geography TEXT, funding TEXT, cofinancing TEXT, eligibility TEXT,
          fit TEXT, risks TEXT, steps TEXT, tags TEXT NOT NULL, relevance INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL DEFAULT 'open', liked INTEGER NOT NULL DEFAULT 0, positioning TEXT,
          application_draft TEXT, draft_status TEXT NOT NULL DEFAULT 'not_started', source TEXT, checked_at TEXT,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS source_checks (
          url TEXT PRIMARY KEY, label TEXT NOT NULL, checked_at TEXT NOT NULL, status TEXT NOT NULL, detail TEXT
        );
        CREATE TABLE IF NOT EXISTS search_settings (id INTEGER PRIMARY KEY CHECK(id=1), payload TEXT NOT NULL, updated_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS discovery_candidates (
          id INTEGER PRIMARY KEY AUTOINCREMENT, official_url TEXT UNIQUE NOT NULL, title TEXT NOT NULL,
          program TEXT NOT NULL, deadline TEXT, status TEXT NOT NULL, relevance INTEGER NOT NULL,
          matched_keywords TEXT NOT NULL, payload TEXT NOT NULL, discovered_at TEXT NOT NULL, updated_at TEXT NOT NULL
        );
        """)
        columns = {row[1] for row in con.execute("PRAGMA table_info(grants)")}
        for definition in ("application_url TEXT", "form_fields TEXT"):
            name = definition.split()[0]
            if name not in columns:
                con.execute(f"ALTER TABLE grants ADD COLUMN {definition}")
        if not con.execute("SELECT 1 FROM profile WHERE id=1").fetchone():
            profile = {
                "organisation_name": "Ridni.org", "legal_form": "Ukrainian sole proprietor (FOP)", "country": "Ukraine",
                "website": "https://ridni.org", "contact_name": "", "email": "", "phone": "",
                "registration_number": "", "tax_number": "", "legal_address": "", "pic": "",
                "bank_details": "", "team": "", "annual_budget": "", "grant_history": "",
                "years_active": "Approximately 8 years", "annual_visitors": "Approximately 1.5 million", "registered_users": "Approximately 500,000",
                "person_records": "Approximately 10 million", "historical_records": "Approximately 9.6 million", "archival_units": "Approximately 1.1 million",
                "settlements": "Approximately 40,000", "ukrainian_surnames": "Approximately 870,000", "global_surnames": "Approximately 500 million",
                "platform": "A digital genealogy and cultural heritage platform featuring surname and settlement maps, historical person records, archive and metrical-book catalogues, community-supported research services, and an AI research assistant.",
                "data_assets": "Approximately 10 million person records, including 9.6 million historical records; 1.1 million archival units; coverage of 40,000 settlements; 870,000 Ukrainian surnames and approximately 500 million surname records worldwide.",
                "mission": "Ridni.org helps people discover their family history and preserves Ukrainian documentary and linguistic heritage through data, community participation, and responsible digital tools.",
                "application_language": "English",
            }
            con.execute("INSERT INTO profile VALUES (1, ?, ?)", (json.dumps(profile, ensure_ascii=False), now()))
            for tag in SEED["tags"]:
                con.execute("INSERT INTO tags(name,color) VALUES (?,?)", (tag["name"], tag["color"]))
            for grant in SEED["grants"]:
                cols = ",".join(grant.keys())
                marks = ",".join("?" for _ in grant)
                con.execute(f"INSERT INTO grants({cols}) VALUES ({marks})", tuple(grant.values()))
        if not con.execute("SELECT 1 FROM search_settings WHERE id=1").fetchone():
            con.execute("INSERT INTO search_settings VALUES (1, ?, ?)", (json.dumps(DEFAULT_SEARCH_SETTINGS, ensure_ascii=False), now()))


def row_to_grant(row: sqlite3.Row) -> dict:
    item = dict(row)
    for key in ("tags", "steps", "application_draft", "form_fields"):
        if item.get(key):
            try: item[key] = json.loads(item[key])
            except json.JSONDecodeError: pass
    item["liked"] = bool(item["liked"])
    return item


def get_profile(con: sqlite3.Connection) -> dict:
    return json.loads(con.execute("SELECT payload FROM profile WHERE id=1").fetchone()[0])


def get_search_settings(con: sqlite3.Connection) -> dict:
    row = con.execute("SELECT payload FROM search_settings WHERE id=1").fetchone()
    return json.loads(row[0]) if row else DEFAULT_SEARCH_SETTINGS


def rank(grant: dict, tag_names: set[str]) -> int:
    overlap = len(set(grant.get("tags", [])) & tag_names)
    freshness = 10 if grant.get("status") == "open" else 0
    direct = 18 if any(x in " ".join(grant.get("tags", [])).lower() for x in ("архів", "ocr", "мов", "індексац")) else 0
    return min(100, 42 + overlap * 9 + freshness + direct)


def draft_text(label: str, grant: dict, profile: dict, focus: str) -> str:
    key = label.lower()
    organisation = profile.get("organisation_name", "Ridni.org")
    mission = profile.get("mission", "")
    platform = profile.get("platform", "")
    data_assets = profile.get("data_assets", "")
    if any(word in key for word in ("title", "project name")):
        return f"{organisation}: {grant['title']}"
    if any(word in key for word in ("applicant details", "legal status", "contact")):
        return f"Applicant: {organisation}. Legal status: {profile.get('legal_form', '[confirm legal status]')}. Address: {profile.get('legal_address', '[add address]')}. Website: {profile.get('website', '')}. Contact: {profile.get('contact_name', '[add contact name]')} — {profile.get('email', '[add email]')}, {profile.get('phone', '[add phone]')}."
    if "referee" in key or "reference" in key:
        return "Provide three independent referees who know Ridni.org's work. For each: full name, role and organisation, and email address or telephone number. Confirm their consent before submission."
    if any(word in key for word in ("duration", "from", " to:")):
        return "Proposed duration: 12 months, subject to confirmation against the final work plan and the funder's permitted timeframe."
    if any(word in key for word in ("summary", "abstract", "description", "overview")):
        return f"{organisation} will deliver a focused {focus} initiative that turns Ukrainian historical and cultural records into trusted, reusable public knowledge. The work combines responsible digital methods, community participation, and measurable access outcomes."
    if any(word in key for word in ("need", "problem", "context", "rationale")):
        return "Ukrainian documentary heritage remains fragmented, difficult to discover, and vulnerable to loss. Families, researchers, and local communities need reliable ways to locate, interpret, and preserve records that connect people, places, and historical events."
    if any(word in key for word in ("objective", "goal", "aim")):
        return "The project will preserve and structure priority records, improve their discoverability, and enable communities to contribute contextual knowledge. Its objectives are public access, responsible reuse, stronger local capacity, and evidence-based historical understanding."
    if any(word in key for word in ("activit", "method", "approach", "work plan", "propos")):
        return "We will select and assess source materials; agree rights and metadata procedures with custodians; digitise or structure priority records; apply quality-controlled OCR/HTR or indexing where appropriate; link persons and places; and publish documented outputs with community review."
    if any(word in key for word in ("output", "result", "deliverable", "impact")):
        return "Expected outputs include a documented dataset or collection, standardised metadata, improved search and discovery pathways, public-facing contextual materials, and a reusable workflow for participating archives and communities. Progress will be measured through records processed, collection coverage, data quality checks, public use, and partner participation."
    if any(word in key for word in ("beneficiar", "target group", "audience", "stakeholder")):
        return "Primary beneficiaries are Ukrainian families, local communities, archive custodians, historians, educators, and researchers. The project will also support diaspora users and partner institutions seeking reliable access to Ukrainian historical evidence."
    if any(word in key for word in ("partner", "consortium", "team", "capacity")):
        return f"{organisation} brings approximately eight years of operational experience and a platform reaching about 1.5 million annual visitors. {platform} The final application will name the eligible lead, archival custodians, and any required institutional partners for this call."
    if any(word in key for word in ("timeline", "schedule", "milestone")):
        return "Months 1–2: confirm partners, rights, scope, and baseline. Months 3–8: process collections and quality-control data. Months 9–10: publish and test public access. Months 11–12: evaluate use, document the workflow, and complete reporting. The timeline will be adjusted to the call's permitted duration."
    if any(word in key for word in ("budget", "cost", "finance")):
        return "The budget will prioritise collection assessment, specialist digitisation or metadata work, rights and preservation measures, community engagement, accessible publication, and proportionate project coordination. Each cost line will be mapped to an activity and checked against the funder's eligibility rules."
    if any(word in key for word in ("risk", "ethic", "data protection", "safeguard")):
        return "Key risks are unclear rights, sensitive personal data, uneven source quality, and partner capacity. We will use written permissions, proportionate access controls, documented provenance, human quality review, and a clear escalation path with custodians and partners."
    if any(word in key for word in ("sustain", "legacy", "continuation")):
        return "Outputs will be maintained through Ridni.org's existing infrastructure, documented for reuse, and shared with participating custodians and communities. The project will create a repeatable model rather than a one-off publication."
    if any(word in key for word in ("organisation", "applicant", "profile", "experience")):
        return f"{organisation} is a Ukrainian digital genealogy and cultural heritage platform. {mission} {data_assets}"
    if any(word in key for word in ("gender", "cross-cutting", "minority", "youth")):
        return "The initiative will use inclusive language and accessible participation routes, seek balanced representation in community engagement, and monitor whether women, young people, minorities, displaced people, and geographically marginalised communities can benefit equitably."
    if any(word in key for word in ("similar", "innovative", "complementary")):
        return "The initiative complements existing archival digitisation and public-history work by connecting fragmented records across people, places, and communities, while making provenance and responsible reuse central to public access. It does not duplicate commercial genealogy services."
    if any(word in key for word in ("other donor", "other donors", "other means")):
        return "This initiative needs flexible support for a civic-memory and access-to-information intervention that may not fit conventional research, infrastructure, or heritage grant cycles. Before submission, list any specific donors approached and explain why EED is the appropriate gap-filling funder."
    if "emergency" in key:
        return "Not requested at this stage. Use this section only if a sudden, well-evidenced situation creates an urgent threat to the initiative or its ability to continue."
    if any(word in key for word in ("attachment", "budget template", "total cost")):
        return "Prepare the required budget template in EUR, including taxes where applicable, and attach only supporting documents that substantiate capacity, permissions, or the urgency and public value of the initiative."
    return f"This section will describe how {organisation} will deliver the proposed {focus} work in line with the grant's official requirements. Add call-specific evidence, partner names, quantities, and wording before submission."


def make_draft(grant: dict, profile: dict) -> dict:
    tag_map = {
        "генеалогія": "genealogy", "архіви": "archives", "оцифрування": "digitisation",
        "OCR / HTR": "OCR and HTR", "LLM-індексація": "LLM-assisted indexing",
        "діалекти": "dialects", "мовна спадщина": "language heritage",
        "публічна історія": "public history", "crowdsourcing": "community participation",
    }
    themes = [tag_map.get(tag, tag) for tag in grant.get("tags", [])]
    focus = ", ".join(themes[:4]) or "digital cultural heritage"
    fields = grant.get("form_fields") or []
    if not fields:
        raise ValueError("Application form fields have not been reviewed")
    sections = [{"label": field["label"] if isinstance(field, dict) else str(field), "text": draft_text(field["label"] if isinstance(field, dict) else str(field), grant, profile, focus)} for field in fields]
    return {
        "status": "needs_approval", "created_at": now(),
        "application_title": grant["title"], "applicant": profile.get("organisation_name", "Ridni.org"),
        "legal_form": profile.get("legal_form", ""), "contact": profile.get("contact_name", ""),
        "application_url": grant.get("application_url") or grant.get("official_url", ""),
        "sections": sections,
        "missing": [key for key in ("contact_name", "email", "registration_number", "legal_address") if not profile.get(key)],
        "note": "This is a field-by-field working draft. Replace assumptions with call-specific evidence and verify every field against the official form. It will never be submitted automatically."
    }


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(PUBLIC), **kwargs)
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def _json(self, payload, code=200):
        raw = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw))); self.end_headers(); self.wfile.write(raw)

    def _body(self):
        try: return json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))).decode() or "{}")
        except json.JSONDecodeError: return {}

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/health": return self._json({"ok": True, "at": now()})
        if parsed.path == "/api/bootstrap":
            with db() as con:
                candidates = []
                for row in con.execute("SELECT * FROM discovery_candidates ORDER BY relevance DESC, deadline ASC LIMIT 100"):
                    item = dict(row)
                    item["matched_keywords"] = json.loads(item["matched_keywords"])
                    candidates.append(item)
                return self._json({"profile": get_profile(con), "search_settings": get_search_settings(con), "tags": [dict(x) for x in con.execute("SELECT * FROM tags ORDER BY name")], "grants": [row_to_grant(x) for x in con.execute("SELECT * FROM grants ORDER BY relevance DESC, deadline ASC")], "source_checks": [dict(x) for x in con.execute("SELECT * FROM source_checks ORDER BY checked_at DESC")], "discovery_candidates": candidates})
        self.path = "/index.html" if parsed.path == "/" else parsed.path
        return super().do_GET()

    def do_HEAD(self):
        parsed = urlparse(self.path)
        self.path = "/index.html" if parsed.path == "/" else parsed.path
        return super().do_HEAD()

    def do_POST(self):
        parts = [x for x in urlparse(self.path).path.split("/") if x]
        body = self._body()
        if parts == ["api", "search", "run"]:
            if not SEARCH_LOCK.acquire(blocking=False):
                return self._json({"error": "A search is already running"}, 409)
            try:
                result = subprocess.run(
                    [sys.executable, str(ROOT / "scripts" / "sync_official_sources.py")],
                    cwd=ROOT, env=os.environ.copy(), capture_output=True, text=True, timeout=180,
                )
                if result.returncode:
                    return self._json({"error": (result.stderr or result.stdout)[-1000:]}, 500)
                return self._json({"ok": True, "detail": result.stdout.strip()})
            except subprocess.TimeoutExpired:
                return self._json({"error": "Search timed out after 180 seconds"}, 504)
            finally:
                SEARCH_LOCK.release()
        with LOCK, db() as con:
            if parts == ["api", "tags"]:
                con.execute("INSERT INTO tags(name,color) VALUES (?,?)", (body.get("name", "").strip(), body.get("color", "#2f6f66")))
                return self._json({"ok": True}, 201)
            if parts == ["api", "grants"]:
                required = {"title", "funder", "official_url"}
                if not required <= body.keys(): return self._json({"error": "Missing required fields"}, 400)
                if not body.get("verified"): return self._json({"error": "Official source verification is required"}, 400)
                if con.execute("SELECT 1 FROM grants WHERE official_url=?", (body["official_url"],)).fetchone():
                    return self._json({"error": "This official opportunity is already in the collection"}, 409)
                body.setdefault("tags", []); body.setdefault("steps", []); body.setdefault("relevance", 50); body.setdefault("status", "open")
                keys = ["title","funder","official_url","application_url","form_fields","deadline","timezone","geography","funding","cofinancing","eligibility","fit","risks","steps","tags","relevance","status","positioning","source"]
                values = [json.dumps(body.get(x, []), ensure_ascii=False) if x in ("steps","tags","form_fields") else body.get(x, "") for x in keys]
                cursor = con.execute(f"INSERT INTO grants({','.join(keys)},created_at,updated_at) VALUES ({','.join('?'*len(keys))},?,?)", values + [now(), now()])
                candidate_id = body.get("candidate_id")
                if candidate_id:
                    con.execute("DELETE FROM discovery_candidates WHERE id=? AND official_url=?", (int(candidate_id), body["official_url"]))
                return self._json({"ok": True, "id": cursor.lastrowid}, 201)
            if len(parts) == 4 and parts[:2] == ["api", "grants"] and parts[3] == "like":
                gid = int(parts[2]); liked = bool(body.get("liked", True))
                row = con.execute("SELECT * FROM grants WHERE id=?", (gid,)).fetchone()
                if not row: return self._json({"error":"Not found"},404)
                con.execute("UPDATE grants SET liked=?, updated_at=? WHERE id=?", (int(liked), now(), gid))
                return self._json({"ok": True, "draft_status": row["draft_status"]})
            if len(parts) == 4 and parts[:2] == ["api", "grants"] and parts[3] == "draft":
                gid = int(parts[2]); row = con.execute("SELECT * FROM grants WHERE id=?", (gid,)).fetchone()
                if not row: return self._json({"error":"Not found"},404)
                try:
                    draft = make_draft(row_to_grant(row), get_profile(con))
                except ValueError as exc:
                    return self._json({"error": str(exc)}, 409)
                con.execute("UPDATE grants SET application_draft=?, draft_status='needs_approval', liked=1, updated_at=? WHERE id=?", (json.dumps(draft,ensure_ascii=False),now(),gid)); return self._json(draft)
        return self._json({"error":"Not found"},404)

    def do_PUT(self):
        path = urlparse(self.path).path; body = self._body()
        with LOCK, db() as con:
            if path == "/api/profile":
                con.execute("UPDATE profile SET payload=?,updated_at=? WHERE id=1", (json.dumps(body,ensure_ascii=False),now())); return self._json({"ok":True})
            if path == "/api/search-settings":
                current = get_search_settings(con)
                allowed = {"programs", "keywords", "excluded_keywords", "geographies", "applicant_modes", "include_forthcoming", "include_cascade_funding", "official_sources_only", "minimum_relevance", "search_breadth"}
                merged = {**current, **{key: value for key, value in body.items() if key in allowed}}
                merged["official_sources_only"] = True
                merged["minimum_relevance"] = max(0, min(100, int(merged.get("minimum_relevance", 35))))
                if merged.get("search_breadth") not in {"strict", "balanced", "broad"}: merged["search_breadth"] = "broad"
                con.execute("UPDATE search_settings SET payload=?,updated_at=? WHERE id=1", (json.dumps(merged,ensure_ascii=False),now()))
                return self._json({"ok":True, "search_settings": merged})
            parts = [x for x in path.split("/") if x]
            if len(parts) == 4 and parts[:2] == ["api", "grants"] and parts[3] == "form-schema":
                gid = int(parts[2]); row = con.execute("SELECT official_url FROM grants WHERE id=?", (gid,)).fetchone()
                if not row: return self._json({"error":"Not found"},404)
                labels = [str(item).strip() for item in body.get("fields", []) if str(item).strip()]
                if not labels: return self._json({"error":"Add at least one form field"},400)
                fields = [{"label": label} for label in labels]
                con.execute("UPDATE grants SET application_url=?,form_fields=?,updated_at=? WHERE id=?", (body.get("application_url", "").strip() or row["official_url"], json.dumps(fields, ensure_ascii=False), now(), gid))
                return self._json({"ok":True, "form_fields":fields})
            if len(parts) == 4 and parts[:2] == ["api", "grants"] and parts[3] == "draft":
                gid = int(parts[2]); row = con.execute("SELECT application_draft FROM grants WHERE id=?", (gid,)).fetchone()
                if not row: return self._json({"error":"Not found"},404)
                draft = json.loads(row["application_draft"] or "{}")
                sections = body.get("sections")
                if not isinstance(sections, list) or not all(isinstance(x, dict) and x.get("label") and x.get("text") is not None for x in sections):
                    return self._json({"error":"Invalid draft sections"},400)
                draft["sections"] = sections; draft["updated_at"] = now()
                con.execute("UPDATE grants SET application_draft=?,draft_status='needs_approval',updated_at=? WHERE id=?", (json.dumps(draft,ensure_ascii=False),now(),gid))
                return self._json({"ok":True, "draft":draft})
        return self._json({"error":"Not found"},404)

    def do_DELETE(self):
        parts = [x for x in urlparse(self.path).path.split("/") if x]
        if len(parts) == 3 and parts[:2] == ["api", "tags"]:
            with LOCK, db() as con: con.execute("DELETE FROM tags WHERE id=?", (int(parts[2]),))
            return self._json({"ok":True})
        return self._json({"error":"Not found"},404)


SEED = {"tags": [
 {"name":"генеалогія","color":"#3467d6"},{"name":"архіви","color":"#8a5cdb"},{"name":"оцифрування","color":"#2f8879"},{"name":"OCR / HTR","color":"#d66a3b"},{"name":"LLM-індексація","color":"#b24483"},{"name":"діалекти","color":"#977226"},{"name":"мовна спадщина","color":"#3b7891"},{"name":"публічна історія","color":"#596774"},{"name":"crowdsourcing","color":"#4c8e4d"}],
"grants": []}

def seed_grant(**kwargs):
    kwargs["tags"] = json.dumps(kwargs["tags"], ensure_ascii=False); kwargs["steps"] = json.dumps(kwargs["steps"], ensure_ascii=False)
    kwargs.update(created_at=now(), updated_at=now())
    SEED["grants"].append(kwargs)

seed_grant(title="Imminent Research Grants", funder="Translated Research Center", official_url="https://imminent.translated.com/apply-for-your-grants", deadline="2026-10-15", timezone="не зазначено", geography="Увесь світ", funding="5 грантів по $20 000 / 1 рік", cofinancing="Не вимагається; 50% виплата після фінального звіту", eligibility="Дослідники, підприємці, організації й компанії; український ФОП потенційно підходить.", fit="Експеримент зі словниками прізвищ і топонімів Ridni для поліпшення HTR/LLM-індексації.", risks="Потрібна дослідницька новизна; лише 5 переможців; передбачена стаття.", steps=["Підтвердити статус ФОП і права на результати.","Відібрати контрольну вибірку рукописів.","Описати baseline та CER/WER.","Подати 250-слівний опис."], tags=["OCR / HTR","LLM-індексація","мовна спадщина"], relevance=95, status="open", positioning="Ridni.org — практична лабораторія для відповідального AI-опрацювання українських історичних джерел: поєднуємо великі масиви записів, локальні словники та людську перевірку.", source="Official funder page")
seed_grant(title="Memory in Action", funder="Culture Helps Solidarity / Creative Europe", official_url="https://culturehelpssolidarity.eu/project-grants/", deadline="2026-10-06", timezone="14:00 Europe/Kyiv", geography="Україна та країни Creative Europe", funding="До €7 000", cofinancing="Рекомендовано покривати грантом до 80% бюджету", eligibility="Організації й фізичні особи; для ФОП потрібне підтвердження форми договору. Консорціум не потрібний.", fit="Модуль сімейних архівів переміщених громад: фото, листи й історії, прив’язані до місць походження.", risks="Не для загальної розробки сайту або OCR; потрібні згода і захист приватності.", steps=["Обрати одну громаду.","Знайти місцевого партнера.","Підготувати правила згоди.","Скласти бюджет."], tags=["публічна історія","генеалогія","архіви"], relevance=88, status="open", positioning="Ridni.org збирає й поєднує сімейні архіви з історією місць, щоб переміщені громади могли зберегти пам’ять і повернути її у спільний контекст.", source="Official funder page")
seed_grant(title="UCLA Modern Endangered Archives Program", funder="UCLA Library / Arcadia", official_url="https://meap.library.ucla.edu/call-for-applications/", deadline="2026-11-16", timezone="Pre-application deadline", geography="Колекції поза США, Канадою, Великою Британією та ЄС", funding="Planning до $20 000; Project до $70 000", cofinancing="Фіксованого співфінансування немає", eligibility="Потрібні архів, бібліотека, університет або культурна/громадська організація. ФОП самостійно не підходить.", fit="Оцифрування й індексація визначеної української колекції XX–XXI ст. під ризиком втрати.", risks="Відкритий доступ у UCLA обов’язковий; не для XIX-ст. метрик як базового кейсу.", steps=["Обрати колекцію після 1940 р.","Зафіксувати загрози.","Залучити установу-заявника.","Перевірити права на відкриту публікацію."], tags=["архіви","оцифрування","публічна історія"], relevance=84, status="open", positioning="Ridni.org допомагає українським громадам перетворювати вразливі сучасні архіви на доступні, описані й етично керовані цифрові колекції.", source="Official funder page")
seed_grant(title="Unlocking Advanced Capabilities in Conservation and Heritage Science", funder="AHRC / UKRI", official_url="https://www.ukri.org/opportunity/unlocking-advanced-capabilities-in-conservation-and-heritage-science/", deadline="2026-11-25", timezone="16:00 UK", geography="Велика Британія; міжнародне партнерство", funding="£500 000–£1,5 млн", cofinancing="До 100% прийнятних капітальних витрат", eligibility="Координатор — прийнятна британська дослідницька організація. ФОП може бути зовнішнім партнером, не заявником.", fit="Пілот для випробування HTR/OCR/AI-інфраструктури на українських історичних записах.", risks="Не фінансує звичайне оцифрування чи розвиток сайту; потрібен UK lead.", steps=["Підготувати one-pager пілота.","Знайти UK-координатора.","Описати дані та KPI.","Уточнити модель партнерства."], tags=["архіви","OCR / HTR","LLM-індексація"], relevance=83, status="open", positioning="Ridni.org надає масштабний український тестовий полігон для точного, підзвітного AI-опрацювання рукописних архівів і перевірки результатів спільнотою.", source="Official funder page")
seed_grant(title="EMKP Legacy Digitisation Grant", funder="Endangered Material Knowledge Programme / British Museum", official_url="https://www.emkp.org/digitisation-grants/", deadline="2026-12-01", timezone="12:00 GMT", geography="Міжнародний", funding="До £20 000 / 1 рік", cofinancing="Не зазначено", eligibility="Заявник має працювати з установою або громадою-господарем; незалежним дослідникам — після погодження. NGO/університет можливі.", fit="Окремий пілот оцифрування наявних етнографічних матеріалів про традиційні знання, ремесла чи локальну культуру.", risks="Не для метричних книг чи загальної HTR-розробки; відкритий депозит і ліцензія CC BY-NC-SA.", steps=["Вибрати legacy-колекцію.","Підтвердити права та етичний протокол.","Залучити установу/громаду.","Скласти план відкритого депозиту."], tags=["архіви","оцифрування","мовна спадщина"], relevance=79, status="open", positioning="Ridni.org зберігає локальне знання, пов’язуючи оцифровані сімейні та етнографічні матеріали з людьми, місцями й мовним контекстом.", source="Official funder page")
seed_grant(title="NEH Collections Stewardship", funder="National Endowment for the Humanities", official_url="https://www.neh.gov/program/collections-stewardship", deadline="2026-12-15", timezone="23:59 ET", geography="США; міжнародні партнери через американського заявника", funding="До $350 000 для однієї організації; до $500 000 для консорціуму", cofinancing="Не вимагається", eligibility="Заявник — US 501(c)(3), університет або орган влади. Український ФОП самостійно не підходить.", fit="Відкрита індексація українських архівів із Ridni як технологічним партнером.", risks="Потрібні US applicant та доступна колекція; модель виплат ФОП слід узгодити.", steps=["Визначити колекцію й правовласника.","Знайти US-заявника.","Описати OCR/HTR work package.","Узгодити бюджет і контрактну модель."], tags=["архіви","оцифрування","OCR / HTR","LLM-індексація"], relevance=82, status="open", positioning="Ridni.org перетворює українські архіви на відкриті, пошукові джерела: від зображення до перевіреного індексу і зрозумілого родинного контексту.", source="Official funder page")
seed_grant(title="SSHRC Partnership Engage Grants", funder="Social Sciences and Humanities Research Council of Canada", official_url="https://sshrc-crsh.canada.ca/en/funding/opportunities/partnership-engage-grants/2026/competition.aspx", deadline="2026-12-15", timezone="20:00 ET", geography="Канада; один міжнародний партнер допускається", funding="C$10 000–50 000 / до 1 року", cofinancing="Не обов’язкове; очікують грошовий або натуральний внесок партнера", eligibility="Заявник — дослідник канадського університету. Ridni як український ФОП потенційно може бути міжнародним private-sector partner.", fit="Дослідження HTR/VLM/LLM-витягання імен, подій і топонімів із human-in-the-loop перевіркою.", risks="Це не грант на звичайне оцифрування чи створення бази даних; потрібен Canadian PI.", steps=["Підготувати research concept.","Знайти канадського PI.","Узгодити внесок Ridni.","Перевірити допустимість контрактних виплат."], tags=["генеалогія","OCR / HTR","LLM-індексація","публічна історія"], relevance=91, status="open", positioning="Ridni.org — міжнародний приклад того, як історичні дані, алгоритми та експертна перевірка можуть разом відновлювати зв’язки між людьми, подіями й місцями.", source="Official funder page")

if __name__ == "__main__":
    init_db()
    port = int(os.environ.get("PORT", "8088"))
    print(f"Ridni Grant Hub running on :{port}")
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
