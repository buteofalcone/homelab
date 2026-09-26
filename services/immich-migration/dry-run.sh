#!/usr/bin/env bash
set -Eeuo pipefail

exec "$(dirname "${BASH_SOURCE[0]}")/import-takeout.sh" sample dry-run
