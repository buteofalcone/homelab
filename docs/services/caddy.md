# Caddy

Caddy provides publicly trusted HTTPS for private services over Tailscale.

Cloudflare DNS-only A records point each service name at the server's Tailscale IP. Caddy uses the DNS challenge, so no router port forwarding is required. The scoped Cloudflare token is stored in `/etc/homelab/caddy.env` and must never be committed to Git.

Create or update the required DNS records:

```bash
sudo ./scripts/configure-cloudflare-dns.sh
```

Reload after editing `config/caddy/Caddyfile`:

```bash
make caddy-reload
```
