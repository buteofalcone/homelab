FROM debian:13-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2

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
