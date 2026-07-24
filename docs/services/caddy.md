# Caddy

Caddy provides local HTTPS through its internal certificate authority.

Configure DNS for `*.BASE_DOMAIN` to point at the server. Wildcard DNS is convenient but not required; individual records also work.

Reload after editing `config/caddy/Caddyfile`:

```bash
make caddy-reload
```

Export the local CA:

```bash
make caddy-root
```

Each client must trust the exported root certificate.
