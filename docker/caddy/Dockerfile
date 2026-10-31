FROM caddy:2-builder-alpine@sha256:95a5e7e2692b5eb9545aadc5b90a39f6f509bee59c9508a493f83ee902eaef63 AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare

FROM caddy:2-alpine@sha256:6aeddd44c3078b0f9a35206472a11420648a79c184603ef95957d0a20044cb2b

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
COPY docker/caddy/entrypoint.sh /usr/local/bin/homelab-caddy-entrypoint

RUN chmod 0755 /usr/local/bin/homelab-caddy-entrypoint

ENTRYPOINT ["/usr/local/bin/homelab-caddy-entrypoint"]
CMD ["run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
