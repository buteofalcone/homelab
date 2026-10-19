#!/usr/bin/env python3
"""Apply the verified September 2026 Ridni context update idempotently."""
import json
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from app import DB_PATH, DEFAULT_SEARCH_SETTINGS, init_db, make_draft, now, row_to_grant


PROFILE_ENGLISH = {
    "organisation_name": "Ridni.org",
    "legal_form": "Ukrainian sole proprietor (FOP)",
    "country": "Ukraine",
    "website": "https://ridni.org",
    "years_active": "Approximately 8 years",
    "annual_visitors": "Approximately 1.5 million",
    "registered_users": "Approximately 500,000",
    "person_records": "Approximately 10 million",
    "historical_records": "Approximately 9.6 million",
    "archival_units": "Approximately 1.1 million",
    "settlements": "Approximately 40,000",
    "ukrainian_surnames": "Approximately 870,000",
    "global_surnames": "Approximately 500 million",
    "platform": "A digital genealogy and cultural heritage platform featuring surname and settlement maps, historical person records, archive and metrical-book catalogues, community-supported research services, and an AI research assistant.",
    "data_assets": "Approximately 10 million person records, including 9.6 million historical records; 1.1 million archival units; coverage of 40,000 settlements; 870,000 Ukrainian surnames and approximately 500 million surname records worldwide.",
    "mission": "Ridni.org helps people discover their family history and preserves Ukrainian documentary and linguistic heritage through data, community participation, and responsible digital tools.",
    "application_language": "English",
}


GRANTS = [
    {
        "title": "EED — Apply for Support",
        "funder": "European Endowment for Democracy",
        "official_url": "https://democracyendowment.eu/support",
        "application_url": "https://apply.democracyendowment.eu/Apply/en",
        "form_fields": [
            {"label": "Applicant details and legal status (name, address, website, contact)"},
            {"label": "Three referees"},
            {"label": "Title of the initiative"},
            {"label": "Initiative duration"},
            {"label": "Summary of your proposal (maximum 1,500 characters)"},
            {"label": "1. What is the objective of the initiative? (maximum 1,500 characters)"},
            {"label": "2. What are you proposing to do? (maximum 4,500 characters)"},
            {"label": "3. What are the expected results of your initiative? (maximum 1,500 characters)"},
            {"label": "4. Gender and other cross-cutting issues (maximum 1,500 characters)"},
            {"label": "5. Similar activities and complementary or innovative value (maximum 1,500 characters)"},
            {"label": "6. Risks and mitigation (maximum 1,500 characters)"},
            {"label": "7. Capacity and experience (maximum 1,800 characters)"},
            {"label": "8. Why EED and why other donors or means cannot support it? (maximum 1,800 characters)"},
            {"label": "9. Total cost and required budget template"},
            {"label": "10. Emergency funding (if applicable)"},
            {"label": "Attachments: proposed budget and supporting documents"},
        ],
        "deadline": "",
        "timezone": "Rolling applications",
        "geography": "Ukraine and other EED mandate countries",
        "funding": "No formal range; most requests are €10,000–€50,000 and average support is €40,000–€60,000",
        "cofinancing": "No mandatory co-financing is stated on the official support page; confirm in the application guidance.",
        "eligibility": "Ukraine is eligible. EED may support civil society organisations, informal or non-registered groups, independent media, artists, youth groups, and individuals. Applications are accepted on a rolling basis.",
        "fit": "Relevant when Ridni is framed as a civic-memory, public-history, access-to-information, or community-participation initiative that strengthens democratic resilience—not as routine genealogy product development.",
        "risks": "The proposal needs a credible democracy and civic-change objective. Pure digitisation or commercial platform development would be a weak fit. Three referees and a budget template are required.",
        "steps": [
            "Choose a concrete civic-memory or access-to-information objective.",
            "Explain why the initiative falls into a gap not covered by conventional EU instruments.",
            "Prepare the English application, budget template, and three independent referees.",
            "Use the secure EED application portal; no fixed deadline applies.",
        ],
        "tags": ["публічна історія", "crowdsourcing", "архіви", "оцифрування"],
        "relevance": 78,
        "status": "open",
        "positioning": "Ridni.org as a Ukrainian civic-memory infrastructure that helps communities recover suppressed local histories, widen access to documentary evidence, and participate in preserving democratic memory.",
        "source": "Official EED support page",
    },
    {
        "title": "Visegrad+ Grants — Culture and Common Identity",
        "funder": "International Visegrad Fund",
        "official_url": "https://www.visegradfund.org/visegrad-plus-grants-apply",
        "deadline": "2026-10-01",
        "timezone": "12:00 Europe/Bratislava",
        "geography": "Ukraine and V4 countries",
        "funding": "Typically €25,000–€35,000; up to 100% of the project budget",
        "cofinancing": "No mandatory co-financing stated; overheads may not exceed 15% of the requested amount.",
        "eligibility": "Ridni's FOP cannot apply or be a partner. Use an eligible non-governmental legal entity and, under the current Ukraine exception, two partners from two different V4 countries (1×UA + 2×V4). Maximum project duration: 18 months.",
        "fit": "Strong fit for cross-border research and public access around shared historical and cultural heritage, archival datasets, historical settlements, migration, HTR, and community transcription.",
        "risks": "Very short preparation window; the FOP is ineligible; the application requires two active V4 partners and a clearly non-profit project.",
        "steps": [
            "Confirm an eligible Ukrainian lead organisation or institutional host.",
            "Secure two partners from two different V4 countries.",
            "Define a compact Shared Roots pilot with measurable cross-border outputs.",
            "Request a fund consultation before the consultation cut-off if time permits.",
        ],
        "tags": ["генеалогія", "архіви", "оцифрування", "OCR / HTR", "публічна історія", "crowdsourcing"],
        "relevance": 91,
        "status": "open",
        "positioning": "Ridni.org as the digital infrastructure and data partner for a nonprofit Central European collaboration that reconnects dispersed people, places, and archival records across borders.",
        "source": "Official funder call page",
    },
    {
        "title": "CERV 2026 — European Remembrance",
        "funder": "European Commission — Citizens, Equality, Rights and Values",
        "official_url": "https://ec.europa.eu/info/funding-tenders/opportunities/portal/screen/opportunities/topic-details/CERV-2026-CITIZENS-REM",
        "deadline": "2026-10-07",
        "timezone": "17:00 Europe/Brussels",
        "geography": "CERV participating countries; confirm each consortium member in the call document",
        "funding": "€28 million indicative call-level budget",
        "cofinancing": "Confirm the funding rate and lump-sum conditions in the final call document.",
        "eligibility": "The FOP should not be treated as the applicant. A strong nonprofit/cultural/research consortium and programme-country validation are required before proceeding.",
        "fit": "Potential fit for reconstructing Ukrainian communities affected by totalitarianism, genocide, repression, deportation, displacement, and war through people-place-record connections.",
        "risks": "High administrative complexity; very short preparation window; weak fit if framed as product development or genealogy alone.",
        "steps": [
            "Read the final call document and validate Ukraine and consortium eligibility.",
            "Proceed only with an experienced nonprofit or research coordinator.",
            "Frame the work around European remembrance and public benefit, not platform development.",
            "Decide quickly whether a submission is realistic before investing in a full proposal.",
        ],
        "tags": ["архіви", "оцифрування", "публічна історія", "crowdsourcing"],
        "relevance": 78,
        "status": "open",
        "positioning": "Ridni.org as a research and digital-memory partner connecting people, families, places, and archival evidence to reconstruct communities disrupted by twentieth-century violence and displacement.",
        "source": "Official EU Funding & Tenders topic page and CERV 2026 indicative planning",
    },
]


def apply():
    init_db()
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    profile = json.loads(con.execute("SELECT payload FROM profile WHERE id=1").fetchone()[0])
    profile.update(PROFILE_ENGLISH)
    con.execute("UPDATE profile SET payload=?,updated_at=? WHERE id=1", (json.dumps(profile, ensure_ascii=False), now()))

    current = json.loads(con.execute("SELECT payload FROM search_settings WHERE id=1").fetchone()[0])
    current_by_id = {item.get("id"): item for item in current.get("programs", [])}
    programmes = []
    for default in DEFAULT_SEARCH_SETTINGS["programs"]:
        existing = current_by_id.pop(default["id"], {})
        merged = {**existing, **default, "enabled": existing.get("enabled", default["enabled"])}
        merged.pop("priority", None)
        programmes.append(merged)
    programmes.extend(current_by_id.values())
    current["programs"] = programmes
    con.execute("UPDATE search_settings SET payload=?,updated_at=? WHERE id=1", (json.dumps(current, ensure_ascii=False), now()))

    inserted = 0
    updated = 0
    for grant in GRANTS:
        existing = con.execute("SELECT id FROM grants WHERE official_url=?", (grant["official_url"],)).fetchone()
        keys = list(grant)
        values = [json.dumps(grant[key], ensure_ascii=False) if key in {"steps", "tags", "form_fields"} else grant[key] for key in keys]
        if existing:
            assignments = ",".join(f"{key}=?" for key in keys)
            con.execute(f"UPDATE grants SET {assignments},updated_at=? WHERE id=?", values + [now(), existing["id"]])
            updated += 1
            continue
        con.execute(
            f"INSERT INTO grants({','.join(keys)},created_at,updated_at) VALUES ({','.join('?' for _ in keys)},?,?)",
            values + [now(), now()],
        )
        inserted += 1
    refreshed_drafts = 0
    for row in con.execute("SELECT * FROM grants WHERE application_draft IS NOT NULL AND application_draft != ''").fetchall():
        grant = row_to_grant(row)
        if not grant.get("form_fields"):
            continue
        draft = make_draft(grant, profile)
        con.execute(
            "UPDATE grants SET application_draft=?,draft_status='needs_approval',updated_at=? WHERE id=?",
            (json.dumps(draft, ensure_ascii=False), now(), row["id"]),
        )
        refreshed_drafts += 1
    con.commit()
    total = con.execute("SELECT COUNT(*) FROM grants").fetchone()[0]
    print(f"updated English profile and {len(programmes)} monitoring programmes; inserted {inserted} grants; updated {updated}; refreshed {refreshed_drafts} drafts; total {total}")


if __name__ == "__main__":
    apply()
