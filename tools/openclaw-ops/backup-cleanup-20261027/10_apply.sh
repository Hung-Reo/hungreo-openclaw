#!/usr/bin/env bash
set -Eeuo pipefail
cd -- "$(dirname -- "$0")"
: "${1:?After target-specific GO only: pass approved targets.json SHA256}"
exec ionice -c3 nice -n 19 python3 cleanup.py execute --approved-spec-sha256 "$1"
