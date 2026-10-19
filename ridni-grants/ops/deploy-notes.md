# Production handoff

The service listens only on `127.0.0.1:8088`; expose it through the existing TLS reverse proxy for `grants.butenko.online`.

1. Copy this folder to `/opt/homelab/ridni-grants`.
2. Copy `.env.example` to `.env` and replace `GRANTS_PASSWORD` with a long unique secret.
3. Start with `docker compose up -d --build`.
4. Attach the service to the existing `homelab` Docker network and add a Caddy host for `grants.butenko.online` to `ridni-grants:8088`, then validate and reload Caddy.
5. Install the line in `ops/crontab.txt` and verify `https://grants.butenko.online/health`.

The profile data is stored in `/opt/homelab/ridni-grants/data/grants.sqlite`; back up that directory.
