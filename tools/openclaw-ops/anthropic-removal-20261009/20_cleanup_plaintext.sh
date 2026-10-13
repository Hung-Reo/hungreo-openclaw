#!/bin/bash
# 20 — Xoá bản plaintext token Anthropic cũ ở các file "auth rác" (danh sách cố định). Mặc định DRY-RUN.
# KHÔNG đụng lcm.db, transcript, backup upgrade/daily (còn dữ liệu khác).
#   Dry-run: ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 20_cleanup_plaintext.sh
#   Xoá:     ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s -- --yes' < 20_cleanup_plaintext.sh
set -euo pipefail
YES="${1:-}"
H=/home/hung/.openclaw-hungreo; S=/home/hung/.openclaw-suckhoe; BK=/home/hung/backups
FILES=(
  "$H/agents/main/agent/auth-profiles.json.sqlite-import.1781161013530.bak"
  "$H/agents/main/agent/auth-profiles.json.bak-20260611-1355-pre-2026.6.5"
  "$H/agents/main/agent/auth-profiles.json.openai-provider-unification.1780571270212.bak"
  "$H/agents/main/agent/auth-profiles.json.oauth-ref.1779160647156.bak"
  "$S/agents/main/agent/auth-profiles.json.openai-provider-unification.1780619512245.bak"
  "$S/agents/main/agent/auth-profiles.json.sqlite-import.1781161513849.bak"
  "$S/agents/main/agent/auth-profiles.json.bak-20260611-1355-pre-2026.6.5"
  "$S/backups/auth-fix-20260521-131718/auth-profiles.json.bak"
  "$S/backups/auth-reauth-20260524-205429/auth-profiles.json.bak"
  "$BK/openclaw/20260227-203422-hotfix-rate-limit/suckhoe.auth-profiles.json.before"
  "$BK/anthropic-removal-20261009/hungreo/state-openclaw.sqlite.pre-anthropic-logout"
  "$BK/anthropic-removal-20261009/suckhoe/state-openclaw.sqlite.pre-anthropic-logout"
)
DIR="$H/agents/research"   # agent mồ côi: không có trong config, 0 hội thoại, chỉ còn auth store chứa token

echo "== kiểm điều kiện"
jq -e '.agents.entries.research // empty' "$H/openclaw.json" >/dev/null && { echo "ABORT: research có trong config"; exit 1; }
for p in hungreo suckhoe; do
  python3 - "/home/hung/.openclaw-$p/state/openclaw.sqlite" <<'PY' || { echo "ABORT: kho auth $p còn token — chưa xong bước 11"; exit 1; }
import sqlite3, sys
r = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True).execute("select value_json from config_machine_state where state_key='authProfiles.store'").fetchone()
sys.exit(1 if r and "sk-ant-" in r[0] else 0)
PY
done
echo "  research không có trong config ✓  kho auth 2 bot sạch ✓"

echo "== danh sách ($([ "$YES" = "--yes" ] && echo XOÁ || echo DRY-RUN))"
n=0
for f in "${FILES[@]}"; do
  if [ ! -e "$f" ]; then echo "  (không còn) ${f#/home/hung/}"; continue; fi
  has=$(grep -caE 'sk-ant-oat01-[A-Za-z0-9_-]{60,}' "$f" || true)
  [ "$has" -gt 0 ] || { echo "  BỎ QUA (không thấy token) ${f#/home/hung/}"; continue; }
  echo "  $(stat -c %s "$f")B  ${f#/home/hung/}"
  if [ "$YES" = "--yes" ]; then rm -f -- "$f"; fi
  n=$((n+1))
done
if [ -d "$DIR" ]; then
  echo "  dir $(du -sh "$DIR" | cut -f1)  ${DIR#/home/hung/}/"
  [ "$YES" = "--yes" ] && rm -rf -- "$DIR"
  n=$((n+1))
fi
echo "== $n mục $([ "$YES" = "--yes" ] && echo "đã xoá" || echo "sẽ xoá — chạy lại với --yes")"
if [ "$YES" = "--yes" ]; then
  left=0; for f in "${FILES[@]}" "$DIR"; do [ -e "$f" ] && left=$((left+1)); done
  echo "  còn lại trong danh sách: $left"
  for p in hungreo suckhoe; do echo "  $p active=$(systemctl --user is-active openclaw-gateway-$p.service)"; done
fi
