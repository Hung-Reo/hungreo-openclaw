#!/usr/bin/env bash
# Chạy trên Mac (Claude PC). Đưa menu 5 lệnh + overlay có MANIFEST + tắt auto-update plugin lên VPS user claudebot.
#   bash 40_menu_overlay_deploy.sh            → dry-run: chỉ kiểm preflight, không đổi gì
#   bash 40_menu_overlay_deploy.sh --apply    → backup, chép file, tắt autoUpdate, apply overlay (chưa restart)
#   bash 40_menu_overlay_deploy.sh --restart  → như --apply rồi restart claude-collab (cần GO riêng của Hưng)
# Rollback: bash 99_menu_rollback.sh <tên thư mục backup in ra ở bước 2>
set -euo pipefail
MODE="${1:-dry-run}"
HERE="$(cd "$(dirname "$0")" && pwd)"
B="$HERE/vps-bundle"
SSH=(ssh -o ConnectTimeout=10 -i "$HOME/.ssh/hostinger_kvm2" claudebot@72.61.123.33)
SCP=(scp -q -o ConnectTimeout=10 -i "$HOME/.ssh/hostinger_kvm2")
DEST=claudebot@72.61.123.33

# Các bản đã từng chạy (đo 25/11). Lần 1 (18:45): launcher ebb4649b…/server 45d2aff7…; lần 2: aafc32a2…/a35fb740…
EXPECT_LAUNCHER="ebb4649b448e3608a2efa929294b7ae8fe2edc77616afcecc64ad77fdedde9cf,aafc32a26320f34026ea00e08bc622dbb336ec56a8ff386cd4f81cbcb2fa19a7"
EXPECT_SERVER="45d2aff7ac797f280cfc2e46788af6983e07cf9c0d98c10b467385f29156fad4,a35fb740b0f2da24dc36c19f0ea5b7b1e2cc0079252093162803f9ccfccb9f32"
NEW_SERVER="$(shasum -a 256 "$B/plugin/server.ts" | cut -d' ' -f1)"

echo "1) Test local"
(cd "$B" && bun test tests/ >/dev/null) || { echo "bun test FAIL, dừng"; exit 1; }
(cd "$B/plugin" && shasum -a 256 -c --quiet MANIFEST.sha256) || { echo "MANIFEST lệch repo, dừng"; exit 1; }

echo "2) Preflight VPS (read-only)"
"${SSH[@]}" bash -s "$EXPECT_LAUNCHER" "$EXPECT_SERVER" "$NEW_SERVER" <<'EOF'
set -euo pipefail
C=~/.claude/plugins/cache/claude-plugins-official/telegram/0.0.7
L=$(sha256sum ~/collab-hub/start-claude-collab.sh | cut -d' ' -f1)
S=$(sha256sum $C/server.ts | cut -d' ' -f1)
V=$(jq -r '.plugins["telegram@claude-plugins-official"][0].version' ~/.claude/plugins/installed_plugins.json)
A=$(jq -r '."claude-plugins-official" | if has("autoUpdate") then .autoUpdate else "default(on)" end' ~/.claude/plugins/known_marketplaces.json)
echo "  version=$V autoUpdate=$A service=$(systemctl --user is-active claude-collab.service)"
[[ "$V" == 0.0.7 ]] || { echo "  plugin không còn 0.0.7, dừng"; exit 1; }
[[ ",$1," == *",$L,"* ]] || { echo "  launcher trên VPS khác bản đã đo ($L), dừng"; exit 1; }
[[ ",$2," == *",$S,"* || "$S" == "$3" ]] || { echo "  server.ts cache khác bản đã đo ($S), dừng"; exit 1; }
echo "  preflight OK"
EOF
[[ "$MODE" == "--apply" || "$MODE" == "--restart" ]] || { echo "Dry-run xong, chưa đổi gì."; exit 0; }

TS="$(date +%Y%m%d-%H%M%S)"
BK="menu-overlay-$TS"
echo "3) Backup trên VPS → ~/backups/$BK"
"${SSH[@]}" "set -e; mkdir -p ~/backups/$BK; cp -p ~/collab-hub/start-claude-collab.sh ~/.claude/plugins/known_marketplaces.json ~/backups/$BK/"

echo "4) Chép overlay + launcher + plugin-overlay.sh"
"${SSH[@]}" "mkdir -p ~/collab-hub/plugin-overlay.new"
"${SCP[@]}" "$B/plugin/MANIFEST.sha256" "$B/plugin/.mcp.json" "$B"/plugin/*.ts "$DEST:collab-hub/plugin-overlay.new/"
"${SCP[@]}" "$B/hub/plugin-overlay.sh" "$DEST:collab-hub/plugin-overlay.sh.new"
"${SCP[@]}" "$B/hub/start-claude-collab.sh" "$DEST:collab-hub/start-claude-collab.sh.new"
"${SSH[@]}" bash -s "$BK" <<'EOF'
set -euo pipefail
cd ~/collab-hub
(cd plugin-overlay.new && sha256sum --quiet -c MANIFEST.sha256)
rm -rf plugin-overlay && mv plugin-overlay.new plugin-overlay
install -m 0755 plugin-overlay.sh.new plugin-overlay.sh && rm plugin-overlay.sh.new
install -m 0755 start-claude-collab.sh.new start-claude-collab.sh && rm start-claude-collab.sh.new
bash -n start-claude-collab.sh
echo "4b) Chuyển ID voice từ code ra STATE_DIR (repo public không chứa ID)"
ST=~/.claude/channels/telegram-collab
OLD=~/.claude/plugins/cache/claude-plugins-official/telegram/0.0.7/voice-pipeline.ts
if [[ ! -s "$ST/voice-chat-id" ]]; then
  CID="$(sed -n "s/^export const VOICE_CHAT_ID = '\(-\{0,1\}[0-9]\{1,\}\)'.*/\1/p" "$OLD")"
  [[ -n "$CID" ]] || { echo "  không đọc được VOICE_CHAT_ID từ bản đang chạy, dừng"; exit 1; }
  (umask 077; printf '%s\n' "$CID" > "$ST/voice-chat-id")
fi
UID_CODE="$(sed -n "s/^export const VOICE_USER_ID = '\([0-9]\{1,\}\)'.*/\1/p" "$OLD")"
UID_ACCESS="$(jq -r '.allowFrom[0] // empty' "$ST/access.json")"
if [[ -n "$UID_CODE" && "$UID_CODE" != "$UID_ACCESS" ]]; then echo "  allowFrom[0] khác VOICE_USER_ID cũ, dừng"; exit 1; fi
echo "  voice-chat-id OK, allowFrom[0] khớp ID voice cũ"
echo "5) Tắt auto-update marketplace claude-plugins-official"
K=~/.claude/plugins/known_marketplaces.json
jq '."claude-plugins-official".autoUpdate = false' "$K" > "$K.tmp" && mv "$K.tmp" "$K"
jq -r '."claude-plugins-official".autoUpdate' "$K"
echo "6) Apply overlay vào cache"
~/collab-hub/plugin-overlay.sh apply
EOF
echo "Backup: ~/backups/$BK (+ ~/backups/plugin-overlay-* do apply tạo)"

if [[ "$MODE" == "--restart" ]]; then
  echo "7) Restart claude-collab"
  "${SSH[@]}" "systemctl --user restart claude-collab.service; sleep 25; systemctl --user is-active claude-collab.service; pgrep -af \"claude .*--channels\" | grep -o \"\-\-model [^ ]* \-\-effort [^ ]*\" || true"
else
  echo "Chưa restart: phiên đang chạy vẫn dùng code cũ đã nạp trong RAM. Chạy lại với --restart khi có GO."
fi
