#!/usr/bin/env bash
# Chạy trên Mac. Giảm context nền của bot Claude VPS (Hưng GO 25/11: PA2 trước, đo lại, không ổn lùi PA1).
#   bash 50_trim_context.sh pa2        → tắt 5 plugin synced (collab-settings.json) + tắt connector "claude.ai Vercel" cho project bot
#   bash 50_trim_context.sh pa1        → chỉ 5 plugin, bật lại Vercel
#   bash 50_trim_context.sh rollback <thư mục backup>   → trả 2 file về backup
# Mỗi lần: backup có tên → stop service → sửa → start. ~/.claude.json chỉ sửa khi service đã dừng.
set -euo pipefail
MODE="${1:?pa1|pa2|rollback}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SSH=(ssh -o ConnectTimeout=10 -i "$HOME/.ssh/hostinger_kvm2" claudebot@72.61.123.33)
SCP=(scp -q -o ConnectTimeout=10 -i "$HOME/.ssh/hostinger_kvm2")
NEW="$HERE/vps-bundle/hub/collab-settings.json"
jq -e '.enabledPlugins["small-business@synced"] == false' "$NEW" >/dev/null
OLD_HASH=5e01521ae1f0db3f016cf174ce7c49cc1be02d9f8e5c1d472cdc97776b14b033   # bản trước đợt này
NEW_HASH="$(shasum -a 256 "$NEW" | cut -d' ' -f1)"

if [[ "$MODE" != rollback ]]; then
  "${SCP[@]}" "$NEW" claudebot@72.61.123.33:collab-hub/collab-settings.json.new
fi
"${SSH[@]}" bash -s "$MODE" "${2:--}" "$OLD_HASH" "$NEW_HASH" <<'REMOTE'  # "-": ssh nối tham số, chuỗi rỗng sẽ biến mất
set -euo pipefail
MODE=$1 BK_ARG=$2 OLD=$3 NEWH=$4
H=~/collab-hub; CJ=~/.claude.json; P=/home/claudebot/collab-bot; VERCEL="claude.ai Vercel"
if [[ "$MODE" == rollback ]]; then
  B=~/backups/$BK_ARG; [[ -f "$B/collab-settings.json" && -f "$B/claude.json" ]] || { echo "thiếu backup $B"; exit 1; }
  systemctl --user stop claude-collab.service
  cp -p "$B/collab-settings.json" $H/collab-settings.json; cp -p "$B/claude.json" $CJ
  systemctl --user start claude-collab.service; sleep 20; systemctl --user is-active claude-collab.service; exit 0
fi
CUR=$(sha256sum $H/collab-settings.json | cut -d' ' -f1)
[[ "$CUR" == "$OLD" || "$CUR" == "$NEWH" ]] || { echo "collab-settings.json trên VPS khác bản đã đo ($CUR), dừng"; rm -f $H/collab-settings.json.new; exit 1; }
[[ "$(sha256sum $H/collab-settings.json.new | cut -d' ' -f1)" == "$NEWH" ]] || { echo "file chép lên hỏng"; exit 1; }
jq -e . $H/collab-settings.json.new >/dev/null
BK=trim-context-$(date +%Y%m%d-%H%M%S); mkdir -p ~/backups/$BK
cp -p $H/collab-settings.json ~/backups/$BK/collab-settings.json; cp -p $CJ ~/backups/$BK/claude.json
echo "backup → ~/backups/$BK"
systemctl --user stop claude-collab.service
install -m 0644 $H/collab-settings.json.new $H/collab-settings.json && rm $H/collab-settings.json.new
if [[ "$MODE" == pa2 ]]; then
  jq --arg p "$P" --arg v "$VERCEL" '.projects[$p].disabledMcpServers = (((.projects[$p].disabledMcpServers // []) + [$v]) | unique)' $CJ > $CJ.tmp
else
  jq --arg p "$P" --arg v "$VERCEL" '.projects[$p].disabledMcpServers = ((.projects[$p].disabledMcpServers // []) - [$v])' $CJ > $CJ.tmp
fi
jq -e . $CJ.tmp >/dev/null && chmod 600 $CJ.tmp && mv $CJ.tmp $CJ
jq -c --arg p "$P" '.projects[$p].disabledMcpServers' $CJ
jq -c '.enabledPlugins' $H/collab-settings.json
systemctl --user start claude-collab.service; sleep 25; systemctl --user is-active claude-collab.service
REMOTE
