#!/usr/bin/env bash
set -Eeuo pipefail
cd -- "$(dirname -- "$0")"
exec ionice -c3 nice -n 19 python3 cleanup.py verify
