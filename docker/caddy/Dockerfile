FROM caddy:2-builder-alpine@sha256:86e132d1d6db8850352b2dbc15f82a4cb25363ac305ee41e11405873e5931f37 AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare

FROM caddy:2-alpine@sha256:6aeddd44c3078b0f9a35206472a11420648a79c184603ef95957d0a20044cb2b

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
COPY docker/caddy/entrypoint.sh /usr/local/bin/homelab-caddy-entrypoint

RUN chmod 0755 /usr/local/bin/homelab-caddy-entrypoint

ENTRYPOINT ["/usr/local/bin/homelab-caddy-entrypoint"]
CMD ["run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
