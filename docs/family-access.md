# Family access

Family devices connect through Tailscale and use normal HTTPS URLs:

A short Ukrainian user guide is available at [`docs/family-guide-uk.md`](family-guide-uk.md) and from the first card on Homepage.

| Service | URL |
| --- | --- |
| Homepage | `https://home.butenko.online` |
| Nextcloud | `https://nextcloud.butenko.online` |
| Nextcloud Talk | `https://nextcloud.butenko.online/apps/spreed/` |
| Immich | `https://immich.butenko.online` |
| Jellyfin | `https://jellyfin.butenko.online` |
| Movie and series requests | `https://requests.butenko.online` |
| Butenko AI | `https://ai.butenko.online` |
| Books | `https://books.butenko.online` |

Cloudflare DNS-only records resolve these names to the HP Server Tailscale address. Caddy obtains publicly trusted certificates with the DNS challenge. This means client devices need Tailscale, but do not need hosts-file entries, custom DNS configuration, or the old Caddy root certificate.

Each person should use an individual application account. Do not share the server administrator, Portainer, Cockpit, or SSH credentials with family users.

For family chat, install the **Nextcloud Talk** app on iOS or Android and sign in with the same personal Nextcloud account and server URL. The browser version is available under **Talk** inside Nextcloud. Text chat works without separate TURN or High Performance Backend services; calls will be evaluated later.

Administrative services remain available at:

| Service | URL |
| --- | --- |
| Portainer | `https://portainer.butenko.online` |
| Beszel | `https://beszel.butenko.online` |
| Uptime Kuma | `https://uptime.butenko.online` |
| Cockpit | `https://100.65.83.35:9090` |
| Calibre administration | `https://calibre.butenko.online` |

The Books site is the read-only Calibre Content Server. On iPad, download an EPUB in Safari and choose **Open in Books**. OPDS-capable readers can use `https://books.butenko.online/opds`.

Only the owner should use the Calibre administration site. Its dedicated password is separate from server, Nextcloud and family credentials.

Do not enable Cloudflare Proxy for these DNS records and do not forward ports 80, 443, 9090, 3389, or 22 on the home router. Access control for invited tailnet users should be reviewed before family invitations are sent.
