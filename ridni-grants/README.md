# Ridni Grant Hub

Internal grant workspace for Ridni: an editable organisation profile, activity tags, ranked opportunities, deadline calendar and an approval-first application-draft workflow.

## Run locally

```bash
python3 app.py
```

Open `http://127.0.0.1:8088`. Set `GRANTS_USER` and `GRANTS_PASSWORD` before production use.

## Daily source check

```bash
python3 scripts/sync_official_sources.py
```

The checker verifies the official source pages attached to the current cards and records their last checked time. It is designed to run from cron. New, verified calls can be added through the interface or the JSON API.
