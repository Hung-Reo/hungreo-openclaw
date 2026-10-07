#!/bin/bash
# 10 — HƯNG CHẠY. Nemo: backup → dừng container → cài plugin codex 2026.9.8 (ghim) trong container chạy 1 lần.
# Sau bước này container vẫn DỪNG; chạy tiếp 11_login.sh (đăng nhập ChatGPT) rồi 12_config_start.sh.
set -euo pipefail
trap 'echo "FAILED ở dòng $LINENO — Nemo có thể đang dừng; báo Claude Code (hoặc: docker start nemo-sandbox)"' ERR
S=/home/hung/sandbox-nemo
B=/home/hung/backups/nemo-sol-fallback-20261007
[ -e "$B" ] && { echo "ABORT: $B đã tồn tại"; exit 1; }

echo "[1/4] dừng Nemo"
docker stop -t 60 nemo-sandbox >/dev/null
docker ps -a --format '{{.Names}} {{.Status}}' | grep nemo-sandbox

echo "[2/4] backup config + state (khi đã dừng)"
mkdir -p "$B"; chmod 700 "$B"
cp -p "$S/config/openclaw.json" "$B/"
cp -p "$S"/config/state/openclaw.sqlite* "$B/" 2>/dev/null || true
tar czf "$B/npm-projects.tgz" -C "$S/config" npm
(cd "$B" && sha256sum * > SHA256SUMS && cut -c1-16,65- SHA256SUMS)

echo "[3/4] cài @openclaw/codex@2026.9.8 --pin (container 1 lần, openclaw.json ghi được)"
docker run --rm --user 1001:1001 --cpus 1 --memory 1500m --env-file "$S/nemo.env" \
  -v "$S/.npm:/sandbox/.npm" -v "$S/runtime-9.8:/sandbox/runtime:ro" -v "$S/config:/sandbox/config" \
  -v "$S/workspace:/sandbox/workspace" -v "$S/.cache:/sandbox/.cache" \
  node:24.21.0-bookworm-slim node /sandbox/runtime/node_modules/openclaw/dist/entry.js \
  plugins install @openclaw/codex@2026.9.8 --pin < /dev/null

echo "[4/4] kiểm plugin"
docker run --rm --user 1001:1001 --env-file "$S/nemo.env" \
  -v "$S/.npm:/sandbox/.npm" -v "$S/runtime-9.8:/sandbox/runtime:ro" -v "$S/config:/sandbox/config" \
  -v "$S/workspace:/sandbox/workspace" -v "$S/.cache:/sandbox/.cache" \
  node:24.21.0-bookworm-slim node /sandbox/runtime/node_modules/openclaw/dist/entry.js plugins list --json 2>/dev/null |
  python3 -c 'import json,sys;d=json.load(sys.stdin);print([(x["id"],x.get("version"),x.get("enabled")) for x in d.get("plugins",d) if x.get("origin")!="bundled"])'
echo "OK 10 — Nemo đang DỪNG. Chạy tiếp 11_login.sh (cần ssh -t)"
