# Family access

Family devices connect through Tailscale and use normal HTTPS URLs:

| Service | URL |
| --- | --- |
| Homepage | `https://home.butenko.online` |
| Nextcloud | `https://nextcloud.butenko.online` |
| Immich | `https://immich.butenko.online` |
| Jellyfin | `https://jellyfin.butenko.online` |

Cloudflare DNS-only records resolve these names to the HP Server Tailscale address. Caddy obtains publicly trusted certificates with the DNS challenge. This means client devices need Tailscale, but do not need hosts-file entries, custom DNS configuration, or the old Caddy root certificate.

Each person should use an individual application account. Do not share the server administrator, Portainer, Cockpit, or SSH credentials with family users.

Administrative services remain available at:

| Service | URL |
| --- | --- |
| Portainer | `https://portainer.butenko.online` |
| Beszel | `https://beszel.butenko.online` |
| Uptime Kuma | `https://uptime.butenko.online` |
| Cockpit | `https://100.65.83.35:9090` |

Do not enable Cloudflare Proxy for these DNS records and do not forward ports 80, 443, 9090, 3389, or 22 on the home router. Access control for invited tailnet users should be reviewed before family invitations are sent.
