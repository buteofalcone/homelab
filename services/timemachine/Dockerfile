FROM debian:13-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a

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
