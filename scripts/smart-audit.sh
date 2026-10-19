#!/usr/bin/env bash
set -Eeuo pipefail

output=/tmp/hp-smart-audit.txt

sudo -v

{
    echo '=== SMART device scan ==='
    sudo smartctl --scan
    echo
    echo '=== /dev/sda ==='
    sudo smartctl -a /dev/sda
    echo
    echo '=== /dev/sdb ==='
    sudo smartctl -a /dev/sdb
} | tee "$output"

echo
echo 'SMART_AUDIT_OK'
