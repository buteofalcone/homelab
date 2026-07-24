# Architecture

The homelab uses Docker Compose includes. Each application stack is isolated in `compose/<name>.yaml` while all containers share the `homelab` bridge network where reverse-proxy communication is required.

Base services have no Compose profile and start with `docker compose up -d`.

Optional workloads use profiles:

- `nextcloud`
- `immich`
- `jellyfin`
- `beszel-agent`

Caddy terminates local HTTPS and reaches containers by Compose service name. Direct host ports remain available as a recovery path.
