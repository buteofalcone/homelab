# Ridni Grant Hub

Internal grant workspace for Ridni: an editable organisation profile, activity tags, ranked opportunities, deadline calendar, configurable discovery filters and an approval-first application-draft workflow.

## Run locally

```bash
python3 app.py
```

Open `http://127.0.0.1:8088`. Production access is intentionally unauthenticated and must remain restricted to the private Tailscale network and its private reverse-proxy route.

## Daily source check

```bash
python3 scripts/sync_official_sources.py
```

The checker verifies the official source pages attached to current cards and all enabled programme sources. It also queries the official EU Funding & Tenders REST API for open and forthcoming calls and puts matches into a separate review queue. The same check can be started manually with the **Пошук** button in search settings.

Candidate relevance is calculated for each specific opportunity from matched Ridni keywords, exclusions, and the selected search breadth. No fund or programme receives a hard-coded score bonus or penalty. Sources without a compatible discovery API, such as EED, EAP, and MEAP, are monitored through their official programme pages; their verified rolling or current opportunities are stored directly as cards.

Discovery candidates are never promoted automatically. The review workflow is: open the official source, verify deadline/budget/eligibility, choose **Підготувати картку**, complete the card, confirm the verification checkbox, and save. Only then is the candidate removed from the review queue and added to **Можливості**.

The Ridni profile and all generated application-draft content are English. Drafts always remain in `needs_approval` status and are never submitted automatically.

Search settings are editable in **Налаштування пошуку** and persisted in SQLite. They include programmes, keywords, exclusions, eligibility modes, forthcoming/cascade funding, breadth and minimum relevance. Official-only verification cannot be disabled.
