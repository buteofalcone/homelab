# Open WebUI

Open WebUI is the private family chat interface for the model served by LM Studio on SilverBrick.

## Architecture

- Image: official `v0.11.0`, pinned to the verified multi-platform manifest digest in Compose.
- State: `/srv/appdata/open-webui` on the HP Server SSD.
- Secrets: `/etc/homelab/open-webui.env`, root-only, bind-mounted read-only, and backed up by Restic.
- Model API: LM Studio at `http://100.91.171.26:1234/v1` over Tailscale.
- Browser URL: `https://ai.butenko.online` through Caddy.
- Direct ports: `127.0.0.1:3002` for host health checks and `SERVER_IP:3002` for trusted-LAN family devices. Neither requires router forwarding.

The service has no Docker socket, host filesystem, shell, or arbitrary tool access. Open WebUI Tools/Functions and web search start disabled. Agent tools will be added later as narrow, reviewed services with approval gates.

## Provision

First verify LM Studio, then run the interactive bootstrap:

```bash
make check-lm-studio
make open-webui-bootstrap
```

The bootstrap reuses the LM Studio API token without printing it, generates a persistent WebUI secret, asks for the initial administrator email and password, creates `/srv/appdata/open-webui`, starts the container, and waits for `/health`. After the account exists, it removes the one-time administrator email and password from the runtime environment and recreates the container once so they do not remain in its environment or current log.

If a restored `webui.db` exists without `/etc/homelab/open-webui.env`, bootstrap stops instead of silently rotating the encryption key. Restore the original root-only secret file from the same recovery set.

The first account is created headlessly from the root-only environment file and public sign-up is disabled. Create separate family accounts deliberately from the administrator interface; do not share the administrator account.

## Operate

```bash
make open-webui
SERVICE=open-webui make logs
curl -fsS http://127.0.0.1:3002/health
```

If SilverBrick sleeps, the WebUI stays available but model requests fail clearly until LM Studio is reachable again.

## Backup and restore

The normal Restic job includes `/srv/appdata/open-webui` and `/etc/homelab/open-webui.env`. Before each snapshot, `scripts/database-dumps.sh` creates a consistent SQLite copy at `/srv/appdata/_backup-dumps/open-webui.db`.

Never delete `/srv/appdata/open-webui`, the SQLite dump, or `/etc/homelab/open-webui.env` while diagnosing an account or connection problem.
