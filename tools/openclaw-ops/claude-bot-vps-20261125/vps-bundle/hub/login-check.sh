#!/usr/bin/env bash
# Mỗi sáng kiểm hạn đăng nhập claude.ai của bot. Còn ≤ 5 ngày (hoặc đã mất login) thì DM nhắc Hưng qua chính bot.
# Không in token. Chạy bằng user claudebot (systemd --user claude-login-check.timer).
set -euo pipefail
WARN_DAYS=5
ST="$HOME/.claude/channels/telegram-collab"
J="$("$HOME/.local/bin/claude" auth status --json 2>/dev/null || echo '{}')"
METHOD="$(jq -r '.authMethod // "none"' <<<"$J")"
EXP="$(jq -r '.loginExpiresAt // empty' <<<"$J")"
NOW=$(date -u +%s)
if [[ "$METHOD" != "claude.ai" || -z "$EXP" ]]; then
  MSG="⚠️ Bot Claude trên VPS mất đăng nhập claude.ai (authMethod=$METHOD). Hưng làm: sudo -iu claudebot rồi ~/.local/bin/claude auth login, xong systemctl --user restart claude-collab."
else
  DAYS=$(( ( $(date -u -d "$EXP" +%s) - NOW ) / 86400 ))
  echo "login còn $DAYS ngày (hết $EXP)"
  (( DAYS <= WARN_DAYS )) || exit 0
  MSG="⏰ Đăng nhập claude.ai của bot Claude trên VPS còn $DAYS ngày (hết $(date -d "$EXP" '+%d/%m %H:%M')). Hưng làm: sudo -iu claudebot rồi ~/.local/bin/claude auth login (không tốn phí), xong systemctl --user restart claude-collab."
fi
CHAT="$(jq -r '.allowFrom[0]' "$ST/access.json")"
TOKEN="$(sed -n 's/^TELEGRAM_BOT_TOKEN=//p' "$ST/.env")"
curl -fsS -o /dev/null --max-time 20 "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${CHAT}" --data-urlencode "text=${MSG}"
unset TOKEN
echo "đã nhắc Hưng"
