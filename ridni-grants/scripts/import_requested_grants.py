#!/usr/bin/env python3
"""Idempotently import the grant list requested on 2026-09-25."""
from __future__ import annotations

import json
import sqlite3
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from app import DB_PATH, init_db, now


REQUESTED = [
    {
        "title": "Safeguarding Linguistic Diversity in Europe (HORIZON-CL2-2026-01-HERITAGE-06)",
        "funder": "Horizon Europe",
        "official_url": "https://ec.europa.eu/info/funding-tenders/opportunities/portal/screen/opportunities/topic-details/HORIZON-CL2-2026-01-HERITAGE-06",
        "deadline": "2026-09-23", "timezone": "Brussels time", "geography": "ЄС та асоційовані країни Horizon Europe",
        "funding": "Орієнтовно €5–5,75 млн на проєкт; бюджет теми €11,5 млн",
        "cofinancing": "RIA: до 100% прийнятних витрат за правилами Horizon Europe",
        "eligibility": "Потрібен міжнародний консорціум за правилами Horizon Europe. Українська організація може бути партнером; ФОП має окремо підтвердити статус legal entity.",
        "fit": "Дослідження українських діалектів, мовної спадщини, прізвищ і топонімів із цифровими корпусами та участю спільнот.",
        "risks": "Дедлайн минув; великий консорціум; Ridni не може подаватися як одиночний заявник.",
        "steps": ["Зберегти тему як орієнтир для наступного call.", "Визначити академічного координатора ЄС.", "Підготувати опис мовних даних Ridni та етичного доступу."],
        "tags": ["діалекти", "мовна спадщина", "LLM-індексація", "crowdsourcing"], "relevance": 96,
        "positioning": "Ridni.org — українська інфраструктура мовної спадщини, що поєднує історичні записи, діалекти, прізвища й топоніми з відповідальним AI та перевіркою спільнотою.",
    },
    {
        "title": "AI Integration in CCSI Work Practice: Catalysing Innovation and Competitiveness (HORIZON-CL2-2026-01-HERITAGE-03)",
        "funder": "Horizon Europe",
        "official_url": "https://ec.europa.eu/info/funding-tenders/opportunities/portal/screen/opportunities/topic-details/HORIZON-CL2-2026-01-HERITAGE-03",
        "deadline": "2026-09-23", "timezone": "Brussels time", "geography": "ЄС та асоційовані країни Horizon Europe",
        "funding": "Орієнтовно €4–5 млн на проєкт; бюджет теми €15 млн",
        "cofinancing": "Innovation Action: зазвичай до 70%; до 100% для неприбуткових організацій",
        "eligibility": "Потрібен міжнародний консорціум за правилами Horizon Europe. Ridni може виступати технологічним або пілотним партнером після перевірки legal entity.",
        "fit": "Пілот AI-інструментів для OCR/HTR, індексації та пошуку в українських культурних і архівних даних.",
        "risks": "Дедлайн минув; масштаб €4–5 млн; потрібні координатор, CCSI-партнери та реальні пілоти поза звичайною розробкою сайту.",
        "steps": ["Сформувати пакет пілота Ridni.", "Знайти координатора Horizon Europe.", "Описати KPI точності, доступності та відповідального AI."],
        "tags": ["OCR / HTR", "LLM-індексація", "архіви", "оцифрування"], "relevance": 92,
        "positioning": "Ridni.org — виробничий пілотний майданчик для доступного й відповідального AI у культурній спадщині, з мільйонами українських записів і human-in-the-loop перевіркою.",
    },
    {
        "title": "Unlocking Advanced Capabilities in Conservation and Heritage Science",
        "funder": "AHRC / UKRI", "official_url": "https://www.ukri.org/opportunity/unlocking-advanced-capabilities-in-conservation-and-heritage-science/",
        "deadline": "2026-11-25",
    },
    {
        "title": "Memory in Action", "funder": "Culture Helps Solidarity / Creative Europe",
        "official_url": "https://culturehelpssolidarity.eu/project-grants/", "deadline": "2026-10-06",
    },
    {
        "title": "Modern Endangered Archives Program", "funder": "UCLA Library / Arcadia",
        "official_url": "https://meap.library.ucla.edu/call-for-applications/", "deadline": "2026-11-16",
    },
    {
        "title": "Small Grants Scheme for Heritage-related Projects",
        "funder": "European Heritage Hub / Europa Nostra",
        "official_url": "https://www.europeanheritagehub.eu/call-for-applications-small-grants-scheme-for-heritage-related-projects-led-by-civil-society-in-eu-candidate-and-neighbouring-countries/",
        "deadline": "2026-09-20", "timezone": "не зазначено", "geography": "Україна, Молдова та інші eligible EU candidate/neighbouring countries",
        "funding": "До €10 000 або €10 000–25 000",
        "cofinancing": "Перевірити в повному Call for Applications",
        "eligibility": "Проєкти мають очолювати організації громадянського суспільства в прийнятних країнах, включно з Україною. ФОП без статусу CSO, ймовірно, потребує партнера-заявника.",
        "fit": "Пілот цифрового збереження спадщини громади, відновлення архівів або залучення громадян до документування.",
        "risks": "Дедлайн минув; перший eligibility stage закрився 7 вересня; потрібен статус civil society organisation.",
        "steps": ["Знайти українську ГО-партнера.", "Підготувати малий пілот до €25 тис.", "Стежити за наступним набором Hub."],
        "tags": ["архіви", "оцифрування", "публічна історія", "crowdsourcing"], "relevance": 86,
        "positioning": "Ridni.org допомагає громадам перетворювати локальні архіви на стійку цифрову пам’ять із відкритим доступом, географічним контекстом і участю мешканців.",
    },
    {
        "title": "Collections Stewardship", "funder": "National Endowment for the Humanities",
        "official_url": "https://www.neh.gov/program/collections-stewardship", "deadline": "2026-12-15",
    },
    {
        "title": "Imminent Research Grants", "funder": "Translated Research Center",
        "official_url": "https://imminent.translated.com/apply-for-your-grants", "deadline": "2026-10-15",
    },
    {
        "title": "Partnership Engage Grants", "funder": "SSHRC",
        "official_url": "https://sshrc-crsh.canada.ca/en/funding/opportunities/partnership-engage-grants/2026/competition.aspx", "deadline": "2026-12-15",
    },
    {
        "title": "Legacy Digitisation Grant", "funder": "Endangered Material Knowledge Programme / British Museum",
        "official_url": "https://www.emkp.org/digitisation-grants/", "deadline": "2026-12-01",
    },
    {
        "title": "Insight Grants: October 2026 Competition", "funder": "SSHRC",
        "official_url": "https://sshrc-crsh.canada.ca/en/funding/opportunities/insight-grants/2026/competition.aspx",
        "deadline": "2026-10-01", "timezone": "20:00 ET", "geography": "Канада; міжнародні collaborators допускаються",
        "funding": "Stream A: C$10 000–125 000; Stream B: C$125 001–500 000 / 2–5 років",
        "cofinancing": "Не зазначене як обов’язкове",
        "eligibility": "Заявник має бути пов’язаний із прийнятним канадським закладом вищої освіти. Ridni може бути міжнародним collaborator або постачальником спеціалізованих послуг.",
        "fit": "Довгострокове гуманітарне дослідження родинної пам’яті, історичних даних або public history із канадським PI.",
        "risks": "Оцифрування колекції або створення бази даних як головна мета не допускається; потрібен канадський академічний заявник.",
        "steps": ["Знайти канадського PI.", "Сформулювати дослідницьке питання, а не digitisation project.", "Уточнити роль Ridni та допустимі consulting costs."],
        "tags": ["генеалогія", "публічна історія", "архіви", "LLM-індексація"], "relevance": 76,
        "positioning": "Ridni.org — дослідницька інфраструктура для вивчення української родинної пам’яті в глобальному контексті, що поєднує масштабні історичні дані та відповідальні цифрові методи.",
    },
]


def main() -> None:
    init_db()
    stamp = now()
    inserted = updated = 0
    with sqlite3.connect(DB_PATH) as con:
        for grant in REQUESTED:
            status = "expired" if grant["deadline"] < date.today().isoformat() else "open"
            existing = con.execute("SELECT id FROM grants WHERE official_url=?", (grant["official_url"],)).fetchone()
            if existing:
                con.execute(
                    "UPDATE grants SET title=?,funder=?,deadline=?,status=?,updated_at=? WHERE id=?",
                    (grant["title"], grant["funder"], grant["deadline"], status, stamp, existing[0]),
                )
                updated += 1
                continue
            full = {
                "title": grant["title"], "funder": grant["funder"], "official_url": grant["official_url"],
                "deadline": grant["deadline"], "timezone": grant.get("timezone", ""), "geography": grant.get("geography", ""),
                "funding": grant.get("funding", ""), "cofinancing": grant.get("cofinancing", ""),
                "eligibility": grant.get("eligibility", ""), "fit": grant.get("fit", ""), "risks": grant.get("risks", ""),
                "steps": json.dumps(grant.get("steps", []), ensure_ascii=False),
                "tags": json.dumps(grant.get("tags", []), ensure_ascii=False),
                "relevance": grant.get("relevance", 50), "status": status,
                "positioning": grant.get("positioning", ""), "source": "Official funder page",
                "created_at": stamp, "updated_at": stamp,
            }
            columns = ",".join(full)
            con.execute(f"INSERT INTO grants({columns}) VALUES ({','.join('?' for _ in full)})", tuple(full.values()))
            inserted += 1
    print(f"requested grants synced: inserted={inserted}, updated={updated}, total={len(REQUESTED)}")


if __name__ == "__main__":
    main()
