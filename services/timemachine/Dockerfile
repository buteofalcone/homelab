FROM debian:13-slim@sha256:8aa5a7bf5a1955bddbe7d74fcdd0b91ab30e74362a8b73af672b0481b35b44a0

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        samba \
        samba-common-bin \
        tini \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/homelab-timemachine-entrypoint

RUN chmod 0755 /usr/local/bin/homelab-timemachine-entrypoint

EXPOSE 445/tcp

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/homelab-timemachine-entrypoint"]
