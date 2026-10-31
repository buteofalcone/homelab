FROM caddy:2-builder-alpine@sha256:0aa610043dab5da82ad0a0268e46bb852785e6f5160f12f1c6fe3f42903d7e1b AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare

FROM caddy:2-alpine@sha256:e70b164da81ef698b3ad19af799ea6086ce6d9e48ed4079eb9fe26f6fbf14ee5

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
COPY docker/caddy/entrypoint.sh /usr/local/bin/homelab-caddy-entrypoint

RUN chmod 0755 /usr/local/bin/homelab-caddy-entrypoint

ENTRYPOINT ["/usr/local/bin/homelab-caddy-entrypoint"]
CMD ["run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
