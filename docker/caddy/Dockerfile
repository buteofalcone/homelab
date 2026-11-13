FROM caddy:2-builder-alpine@sha256:0aa610043dab5da82ad0a0268e46bb852785e6f5160f12f1c6fe3f42903d7e1b AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare

FROM caddy:2-alpine@sha256:003a97808e781aa9f7e75cc2f43d34d461099031faf5e20faefb9f61126836f0

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
COPY docker/caddy/entrypoint.sh /usr/local/bin/homelab-caddy-entrypoint

RUN chmod 0755 /usr/local/bin/homelab-caddy-entrypoint

ENTRYPOINT ["/usr/local/bin/homelab-caddy-entrypoint"]
CMD ["run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
