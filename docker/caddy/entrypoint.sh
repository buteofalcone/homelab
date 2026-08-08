#!/bin/sh
set -eu

set -a
. /run/secrets/caddy.env
if [ -f /run/secrets/media-caddy.env ]; then
  . /run/secrets/media-caddy.env
fi
set +a

exec /usr/bin/caddy "$@"
