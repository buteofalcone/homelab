FROM caddy:2-builder-alpine@sha256:3dbe908afe8ecb4f5505a80153c8de0fecd1b14d560798a6955c5cf115951561 AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare

FROM caddy:2-alpine@sha256:6aeddd44c3078b0f9a35206472a11420648a79c184603ef95957d0a20044cb2b

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
COPY docker/caddy/entrypoint.sh /usr/local/bin/homelab-caddy-entrypoint

RUN chmod 0755 /usr/local/bin/homelab-caddy-entrypoint

ENTRYPOINT ["/usr/local/bin/homelab-caddy-entrypoint"]
CMD ["run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
