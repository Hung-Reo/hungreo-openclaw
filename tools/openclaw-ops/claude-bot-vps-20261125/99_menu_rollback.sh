#!/usr/bin/env bash
# Hoàn tác 40_menu_overlay_deploy.sh. Chạy trên Mac.
#   bash 99_menu_rollback.sh menu-overlay-YYYYMMDD-HHMMSS plugin-overlay-YYYYMMDD-HHMMSS
# Trả launcher + known_marketplaces.json + file cache plugin về bản backup, gỡ plugin-overlay, rồi restart.
set -euo pipefail
BK="${1:?thiếu tên backup menu-overlay-*}"
PBK="${2:?thiếu tên backup plugin-overlay-*}"
ssh -o ConnectTimeout=10 -i "$HOME/.ssh/hostinger_kvm2" claudebot@72.61.123.33 bash -s "$BK" "$PBK" <<'EOF'
set -euo pipefail
B=~/backups/$1; P=~/backups/$2
C=~/.claude/plugins/cache/claude-plugins-official/telegram/0.0.7
[[ -d "$B" && -d "$P" ]] || { echo "không thấy $B hoặc $P"; exit 1; }
cp -p "$B/start-claude-collab.sh" ~/collab-hub/start-claude-collab.sh
cp -p "$B/known_marketplaces.json" ~/.claude/plugins/known_marketplaces.json
cp -pR "$P"/. "$C/"
rm -f "$C/commands.ts"
rm -rf ~/collab-hub/plugin-overlay ~/collab-hub/plugin-overlay.sh
systemctl --user restart claude-collab.service
sleep 25
systemctl --user is-active claude-collab.service
sha256sum "$C/server.ts"
EOF
