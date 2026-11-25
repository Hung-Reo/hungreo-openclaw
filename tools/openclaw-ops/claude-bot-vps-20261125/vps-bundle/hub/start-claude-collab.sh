#!/usr/bin/env bash
# Launcher bot Claude Telegram trên VPS (user claudebot). Port từ mac-collab-hub-20261103/start-claude-collab.sh.
# HARD RULE (Hưng 25/11): chỉ subscription. Không bao giờ API key. Fail-closed.
set -euo pipefail

HUB_DIR="$HOME/collab-hub"
SETTINGS_FILE="$HUB_DIR/collab-settings.json"
CLAUDE_BIN="$HOME/.local/bin/claude"
TOKEN_FILE="$HOME/.config/claude-collab/oauth"
export PATH="$HOME/.local/bin:$HOME/.bun/bin:/usr/bin:/bin"
export TELEGRAM_STATE_DIR="$HOME/.claude/channels/telegram-collab"
export TELEGRAM_INBOX_DIR="$HOME/collab-bot/inbox"
export TELEGRAM_INBOX_RETENTION_DAYS=7

# Không cho đường API key tồn tại
unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX

[[ -x "$CLAUDE_BIN" ]] || { echo "Thiếu $CLAUDE_BIN" >&2; exit 1; }
[[ -f "$TELEGRAM_STATE_DIR/.env" ]] || { echo "Thiếu $TELEGRAM_STATE_DIR/.env" >&2; exit 1; }
# 25/11: setup-token chỉ gọi được model, không tải được policy nên --channels kẹt "waiting for your
# organization's policy" (VERIFIED trên VPS). Vì vậy ưu tiên đăng nhập claude.ai thật (claude auth login,
# vẫn là subscription). Có credentials thì KHÔNG export CLAUDE_CODE_OAUTH_TOKEN (env token đứng trên /login).
CRED_FILE="$HOME/.claude/.credentials.json"
if [[ -f "$CRED_FILE" ]]; then
  unset CLAUDE_CODE_OAUTH_TOKEN
else
  [[ -f "$TOKEN_FILE" ]] || { echo "Chưa đăng nhập: chạy claude auth login" >&2; exit 1; }
  [[ "$(stat -c %a "$TOKEN_FILE")" == "600" ]] || { echo "$TOKEN_FILE phải chmod 600" >&2; exit 1; }
  TOK="$(tr -d '\r\n' < "$TOKEN_FILE")"
  if [[ ! "$TOK" =~ ^sk-ant-oat01-[A-Za-z0-9_-]{80,}$ ]]; then
    echo "Token sai dạng (len=${#TOK}, cần sk-ant-oat01-…); dừng." >&2
    exit 1
  fi
  export CLAUDE_CODE_OAUTH_TOKEN="$TOK"
  unset TOK
fi

AUTH_METHOD="$("$CLAUDE_BIN" auth status --json 2>/dev/null | sed -n 's/.*"authMethod": *"\([^"]*\)".*/\1/p' | head -n1)"
if [[ -z "$AUTH_METHOD" || "$AUTH_METHOD" == "api_key" ]]; then
  echo "authMethod='$AUTH_METHOD' không phải subscription; dừng để tránh tính tiền API." >&2
  exit 1
fi

mkdir -p "$HOME/collab-bot/memory" "$HOME/collab-bot/.claude/skills" "$TELEGRAM_INBOX_DIR" "$HOME/collab-bot/logs"
chmod 700 "$TELEGRAM_INBOX_DIR"
PROTOCOL_TEXT="$(cat "$HUB_DIR/COLLAB_PROTOCOL.md")"
cd "$HOME/collab-bot"
echo "Mở Claude Code collab trên VPS (auth=$AUTH_METHOD, settings=$SETTINGS_FILE)"
exec "$CLAUDE_BIN" \
  --setting-sources user \
  --settings "$SETTINGS_FILE" \
  --channels "plugin:telegram@claude-plugins-official" \
  --permission-mode auto \
  --add-dir "$HOME/collab-bot" \
  --allowedTools "mcp__plugin_telegram_telegram__reply,mcp__plugin_telegram_telegram__react,mcp__plugin_telegram_telegram__edit_message,mcp__plugin_telegram_telegram__download_attachment" \
  --append-system-prompt "$PROTOCOL_TEXT" \
  -n "telegram-collab-claude-vps" \
  "$@"
