#!/usr/bin/env python3
"""Ridni Grant Hub — dependency-free private workspace."""
from __future__ import annotations

import base64
import json
import os
import secrets
import sqlite3
import threading
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent
PUBLIC = ROOT / "public"
DATA = ROOT / "data"
DB_PATH = Path(os.environ.get("GRANTS_DB", DATA / "grants.sqlite"))
LOCK = threading.Lock()


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
        """)
        if not con.execute("SELECT 1 FROM profile WHERE id=1").fetchone():
            profile = {
                "organisation_name": "Ridni.org", "legal_form": "ФОП / Ukrainian sole proprietor", "country": "Україна",
                "website": "https://ridni.org", "contact_name": "", "email": "", "phone": "",
                "registration_number": "", "tax_number": "", "legal_address": "", "pic": "",
                "bank_details": "", "team": "", "annual_budget": "", "grant_history": "",
                "years_active": "8 років", "annual_visitors": "1,5 млн", "registered_users": "500 тис.",
                "person_records": "10 млн", "historical_records": "9,6 млн", "archival_units": "1,1 млн",
                "settlements": "40 тис.", "ukrainian_surnames": "870 тис.", "global_surnames": "≈500 млн",
                "platform": "Генеалогія, карти прізвищ, каталог метричних книг, AI-помічник.",
                "data_assets": "10 млн записів про осіб, з них 9,6 млн історичних записів; 1,1 млн архівних одиниць; 40 тис. населених пунктів; 870 тис. українських і близько 500 млн світових прізвищ.",
                "mission": "Ridni.org допомагає людям знаходити родинну історію та зберігає українську документальну й мовну спадщину через дані, спільноту та відповідальні цифрові інструменти.",
            }
            con.execute("INSERT INTO profile VALUES (1, ?, ?)", (json.dumps(profile, ensure_ascii=False), now()))
            for tag in SEED["tags"]:
                con.execute("INSERT INTO tags(name,color) VALUES (?,?)", (tag["name"], tag["color"]))
            for grant in SEED["grants"]:
                cols = ",".join(grant.keys())
                marks = ",".join("?" for _ in grant)
                con.execute(f"INSERT INTO grants({cols}) VALUES ({marks})", tuple(grant.values()))


def row_to_grant(row: sqlite3.Row) -> dict:
    item = dict(row)
    for key in ("tags", "steps", "application_draft"):
        if item.get(key):
            try: item[key] = json.loads(item[key])
            except json.JSONDecodeError: pass
    item["liked"] = bool(item["liked"])
    return item


def get_profile(con: sqlite3.Connection) -> dict:
    return json.loads(con.execute("SELECT payload FROM profile WHERE id=1").fetchone()[0])


def rank(grant: dict, tag_names: set[str]) -> int:
    overlap = len(set(grant.get("tags", [])) & tag_names)
    freshness = 10 if grant.get("status") == "open" else 0
    direct = 18 if any(x in " ".join(grant.get("tags", [])).lower() for x in ("архів", "ocr", "мов", "індексац")) else 0
    return min(100, 42 + overlap * 9 + freshness + direct)


def make_draft(grant: dict, profile: dict) -> dict:
    positioning = grant.get("positioning") or profile.get("mission", "")
    return {
        "status": "needs_approval", "created_at": now(),
        "application_title": grant["title"], "applicant": profile.get("organisation_name", "Ridni.org"),
        "legal_form": profile.get("legal_form", ""), "contact": profile.get("contact_name", ""),
        "project_summary": positioning,
        "proposed_work": "Підготувати конкретний пілот на матеріалах Ridni з вимірюваними результатами, правами на дані та планом участі спільноти.",
        "missing": [key for key in ("contact_name", "email", "registration_number", "legal_address") if not profile.get(key)],
        "note": "Це робоча чернетка. Перед поданням потрібне ваше схвалення й звірка з офіційною формою конкурсу."
    }


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(PUBLIC), **kwargs)
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def _auth(self) -> bool:
        user, password = os.environ.get("GRANTS_USER"), os.environ.get("GRANTS_PASSWORD")
        if not user or not password: return True
        expected = "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()
        if secrets.compare_digest(self.headers.get("Authorization", ""), expected): return True
        self.send_response(HTTPStatus.UNAUTHORIZED)
        self.send_header("WWW-Authenticate", 'Basic realm="Ridni Grant Hub"')
        self.end_headers()
        return False

    def _json(self, payload, code=200):
        raw = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw))); self.end_headers(); self.wfile.write(raw)

    def _body(self):
        try: return json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))).decode() or "{}")
        except json.JSONDecodeError: return {}

    def do_GET(self):
        if not self._auth(): return
        parsed = urlparse(self.path)
        if parsed.path == "/health": return self._json({"ok": True, "at": now()})
        if parsed.path == "/api/bootstrap":
            with db() as con:
                return self._json({"profile": get_profile(con), "tags": [dict(x) for x in con.execute("SELECT * FROM tags ORDER BY name")], "grants": [row_to_grant(x) for x in con.execute("SELECT * FROM grants ORDER BY relevance DESC, deadline ASC")], "source_checks": [dict(x) for x in con.execute("SELECT * FROM source_checks ORDER BY checked_at DESC")]})
        self.path = "/index.html" if parsed.path == "/" else parsed.path
        return super().do_GET()

    def do_HEAD(self):
        if not self._auth(): return
        parsed = urlparse(self.path)
        self.path = "/index.html" if parsed.path == "/" else parsed.path
        return super().do_HEAD()

    def do_POST(self):
        if not self._auth(): return
        parts = [x for x in urlparse(self.path).path.split("/") if x]
        body = self._body()
        with LOCK, db() as con:
            if parts == ["api", "tags"]:
                con.execute("INSERT INTO tags(name,color) VALUES (?,?)", (body.get("name", "").strip(), body.get("color", "#2f6f66")))
                return self._json({"ok": True}, 201)
            if parts == ["api", "grants"]:
                required = {"title", "funder", "official_url"}
                if not required <= body.keys(): return self._json({"error": "Missing required fields"}, 400)
                body.setdefault("tags", []); body.setdefault("steps", []); body.setdefault("relevance", 50); body.setdefault("status", "open")
                keys = ["title","funder","official_url","deadline","timezone","geography","funding","cofinancing","eligibility","fit","risks","steps","tags","relevance","status","positioning","source"]
                values = [json.dumps(body[x], ensure_ascii=False) if x in ("steps","tags") else body.get(x, "") for x in keys]
                con.execute(f"INSERT INTO grants({','.join(keys)},created_at,updated_at) VALUES ({','.join('?'*len(keys))},?,?)", values + [now(), now()])
                return self._json({"ok": True}, 201)
            if len(parts) == 4 and parts[:2] == ["api", "grants"] and parts[3] == "like":
                gid = int(parts[2]); liked = bool(body.get("liked", True))
                row = con.execute("SELECT * FROM grants WHERE id=?", (gid,)).fetchone()
                if not row: return self._json({"error":"Not found"},404)
                if liked:
                    draft = make_draft(row_to_grant(row), get_profile(con))
                    con.execute("UPDATE grants SET liked=1, application_draft=?, draft_status='needs_approval', updated_at=? WHERE id=?", (json.dumps(draft,ensure_ascii=False),now(),gid))
                    return self._json({"ok": True, "draft_status": "needs_approval", "draft": draft})
                con.execute("UPDATE grants SET liked=0, updated_at=? WHERE id=?", (now(), gid))
                return self._json({"ok": True, "draft_status": row["draft_status"]})
            if len(parts) == 4 and parts[:2] == ["api", "grants"] and parts[3] == "draft":
                gid = int(parts[2]); row = con.execute("SELECT * FROM grants WHERE id=?", (gid,)).fetchone()
                if not row: return self._json({"error":"Not found"},404)
                draft = make_draft(row_to_grant(row), get_profile(con)); con.execute("UPDATE grants SET application_draft=?, draft_status='needs_approval', liked=1, updated_at=? WHERE id=?", (json.dumps(draft,ensure_ascii=False),now(),gid)); return self._json(draft)
        return self._json({"error":"Not found"},404)

    def do_PUT(self):
        if not self._auth(): return
        path = urlparse(self.path).path; body = self._body()
        with LOCK, db() as con:
            if path == "/api/profile":
                con.execute("UPDATE profile SET payload=?,updated_at=? WHERE id=1", (json.dumps(body,ensure_ascii=False),now())); return self._json({"ok":True})
        return self._json({"error":"Not found"},404)

    def do_DELETE(self):
        if not self._auth(): return
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
