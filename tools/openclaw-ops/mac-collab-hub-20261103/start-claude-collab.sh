#!/usr/bin/env bash
set -euo pipefail

# Khởi chạy phiên Claude Code trên Mac nối vào Group Telegram (CLAUDE-BOT-CAPS-20261112).
# - --setting-sources user (KHÔNG nạp .claude/settings.local.json của repo)
# - --settings <hub>/collab-settings.json (telegram plugin, owner-gate hook, allow/ask/deny, sandbox)
# - INBOX tách sang ~/collab-bot/inbox (ngoài ~/.claude/channels vốn bị deny để bảo vệ .env token)
# - Token ưu tiên lấy từ macOS Keychain (claude-collab-oauth, tạo từ `claude setup-token`),
#   fallback sang Claude Desktop RAM nếu Keychain chưa cài.

HUB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="${COLLAB_WORKSPACE_DIR:-/Users/hungdinh/Development/hungreo-openclaw}"
SETTINGS_FILE="$HUB_DIR/collab-settings.json"
export PATH="/Users/hungdinh/.nvm/versions/node/v22.16.0/bin:$PATH"
export TELEGRAM_STATE_DIR="${TELEGRAM_STATE_DIR:-$HOME/.claude/channels/telegram-collab}"
export TELEGRAM_INBOX_DIR="${TELEGRAM_INBOX_DIR:-$HOME/collab-bot/inbox}"
export TELEGRAM_INBOX_RETENTION_DAYS="${TELEGRAM_INBOX_RETENTION_DAYS:-7}"

CLAUDE_BIN="$HOME/.local/bin/claude"
SECURITY_BIN="${COLLAB_SECURITY_BIN:-/usr/bin/security}"
if [[ ! -x "$CLAUDE_BIN" ]]; then
  echo "Không tìm thấy $CLAUDE_BIN" >&2
  exit 1
fi

if [[ ! -f "$TELEGRAM_STATE_DIR/.env" ]]; then
  echo "Chưa có $TELEGRAM_STATE_DIR/.env. Hãy chạy: bash $HUB_DIR/10_setup_access.sh" >&2
  exit 1
fi

# 1) Ưu tiên token subscription dài hạn trong Keychain (để autostart chạy được khi Desktop chưa mở)
if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
  KC_TOK="$("$SECURITY_BIN" find-generic-password -s "claude-collab-oauth" -a "$USER" -w 2>/dev/null || true)"
  if [[ -n "$KC_TOK" ]]; then
    # 17/11/2026: Keychain từng chứa chuỗi 13 ký tự / token copy thiếu dòng đầu → bot chạy với token hỏng.
    # Token `setup-token` dạng sk-ant-oat01-…, dài ~108. Sai dạng thì dừng hẳn, không rơi sang fallback.
    if [[ ! "$KC_TOK" =~ ^sk-ant-oat01-[A-Za-z0-9_-]{80,}$ ]]; then
      echo "Token trong Keychain claude-collab-oauth sai dạng (len=${#KC_TOK}, cần sk-ant-oat01-…, ~108 ký tự); dừng." >&2
      echo "Sửa: ~/.local/bin/claude setup-token, rồi lưu lại bằng lệnh read -rs + security add-generic-password -U (kb/lessons/2026-11-17-collab-bot-keychain-token.md)." >&2
      unset KC_TOK
      exit 1
    fi
    export CLAUDE_CODE_OAUTH_TOKEN="$KC_TOK"
  fi
  unset KC_TOK
fi

# 2) Fallback: mượn OAuth env trong RAM từ Claude Desktop đang mở
if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
  DESKTOP_PID="$(pgrep -f "Claude/claude-code/.*/claude.app/Contents/MacOS/claude" | head -n 1 || true)"
  if [[ -n "$DESKTOP_PID" ]]; then
    while IFS='=' read -r k v; do
      if [[ -n "$k" && -n "$v" ]]; then
        export "$k=$v"
      fi
    done < <(
      ps eww -p "$DESKTOP_PID" \
        | tr ' ' '\n' \
        | grep -E '^(CLAUDE_CODE_OAUTH_TOKEN|CLAUDE_CODE_OAUTH_SCOPES|CLAUDE_CODE_ACCOUNT_UUID|CLAUDE_CODE_ORGANIZATION_UUID|CLAUDE_CODE_SUBSCRIPTION_TYPE|CLAUDE_CODE_USER_EMAIL)=' || true
    )
  fi
fi

PERM_MODE="auto"
DISALLOWED_TOOLS=()
ALLOWED_TOOLS=("--allowedTools" "mcp__plugin_telegram_telegram__reply,mcp__plugin_telegram_telegram__react,mcp__plugin_telegram_telegram__edit_message,mcp__plugin_telegram_telegram__download_attachment")

while [[ $# -gt 0 ]]; do
  case "$1" in
    --read-only)
      PERM_MODE="default"
      DISALLOWED_TOOLS=("--disallowedTools" "Bash,Edit,Write,NotebookEdit")
      shift
      ;;
    *)
      break
      ;;
  esac
done

PROTOCOL_TEXT="$(cat "$HUB_DIR/COLLAB_PROTOCOL.md")"

cd "$WORKSPACE_DIR"
if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
  echo "Không có token subscription (Keychain claude-collab-oauth hoặc Claude Desktop); dừng để tránh chạy bằng API key" >&2
  exit 1
fi
mkdir -p "$HOME/collab-bot/memory" "$HOME/collab-bot/.claude/skills" "$TELEGRAM_INBOX_DIR" "$HOME/collab-bot/logs"
chmod 700 "$TELEGRAM_INBOX_DIR"
echo "🚀 Đang mở Claude Code Collab Session (mode=$PERM_MODE, inbox=$TELEGRAM_INBOX_DIR, settings=$SETTINGS_FILE)..."
exec "$CLAUDE_BIN" \
  --setting-sources user \
  --settings "$SETTINGS_FILE" \
  --channels "plugin:telegram@claude-plugins-official" \
  --permission-mode "$PERM_MODE" \
  ${DISALLOWED_TOOLS[@]+"${DISALLOWED_TOOLS[@]}"} \
  --add-dir "$HOME/collab-bot" \
  "${ALLOWED_TOOLS[@]}" \
  --append-system-prompt "$PROTOCOL_TEXT" \
  -n "telegram-collab-claude" \
  "$@"
