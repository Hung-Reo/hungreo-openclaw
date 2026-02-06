#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if command -v rg >/dev/null 2>&1; then
  TOKEN="$(rg "OPENCLAW_GATEWAY_TOKEN" .env | cut -d= -f2-)"
else
  TOKEN="$(grep -E "^OPENCLAW_GATEWAY_TOKEN=" .env | head -n 1 | cut -d= -f2-)"
fi
if [[ -z "$TOKEN" ]]; then
  echo "Missing OPENCLAW_GATEWAY_TOKEN in .env" >&2
  exit 1
fi

docker compose exec openclaw-gateway node dist/index.js gateway status \
  --token "$TOKEN" \
  --url ws://127.0.0.1:18789
