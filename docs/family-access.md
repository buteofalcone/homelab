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

## Local network access for legacy devices

Devices that cannot run Tailscale may use the server only while connected to the trusted home Wi-Fi/LAN. No router port forwarding is needed:

| Service | Local address |
| --- | --- |
| SMB Inbox | `smb://192.168.1.130/Inbox` |
| Homepage | `http://192.168.1.130:3000` |
| Nextcloud | `http://192.168.1.130:8080` |
| Immich | `http://192.168.1.130:2283` |
| Jellyfin | `http://192.168.1.130:8096` |
| Books / OPDS | `http://192.168.1.130:8081/opds` |

The SMB Inbox account is `homelab` with the dedicated root-only password provisioned by `make timemachine-bootstrap`. SMB1 remains disabled; use an SMB2-capable client. An iPad 2 has no modern native Files application, so it needs a compatible third-party SMB client. Modern Immich and Nextcloud web interfaces may not run in the old iOS Safari engine even when network access works; SMB file access and any still-compatible native clients remain usable.

The Calibre Content Server is bound specifically to the HP Server LAN address, not all interfaces. On an old iPad, configure an OPDS-compatible reader with `http://192.168.1.130:8081/opds`. The catalog works only on the trusted home Wi-Fi and requires no Tailscale client. Do not forward TCP 8081 on the router.

Run `make verify-lan-access` after deployment to verify that the five family endpoints are listening on the LAN address and return healthy responses. These ports must never be forwarded on the router.

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
