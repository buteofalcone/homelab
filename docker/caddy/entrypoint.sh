#!/bin/sh
set -eu

. /run/secrets/caddy.env
export CLOUDFLARE_API_TOKEN

exec /usr/bin/caddy "$@"
