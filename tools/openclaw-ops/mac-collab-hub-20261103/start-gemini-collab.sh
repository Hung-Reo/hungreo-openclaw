#!/usr/bin/env bash
set -euo pipefail

# Khởi chạy phiên Gemini Telegram Bridge trên Mac nối vào Group Telegram / DM.
# - Sử dụng Antigravity CLI (~/.gemini/bin/agy) với tài khoản Google / Gemini của Hưng.
# - Quản lý an toàn bằng collab-gate.ts (chống loop, kiểm soát người gọi, ẩn secret).
# - Trạng thái, token và thread lưu tại ~/.gemini/channels/telegram-collab/ (mode 0700/0600).

HUB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="${COLLAB_WORKSPACE_DIR:-/Users/hungdinh/Development/hungreo-openclaw}"
BRIDGE_SCRIPT="$HUB_DIR/gemini-telegram-bridge/server.ts"
BUN_BIN="/Users/hungdinh/.nvm/versions/node/v22.16.0/bin/bun"
STATE_DIR="${GEMINI_TELEGRAM_STATE_DIR:-$HOME/.gemini/channels/telegram-collab}"

if [[ ! -x "$BUN_BIN" ]]; then
  echo "Không tìm thấy bun tại $BUN_BIN" >&2
  exit 1
fi

if [[ ! -f "$STATE_DIR/.env" ]]; then
  echo "Chưa có $STATE_DIR/.env." >&2
  echo "Hãy chạy: bash $HUB_DIR/setup_gemini_token.sh để thiết lập bot token." >&2
  exit 1
fi

export GEMINI_TELEGRAM_STATE_DIR="$STATE_DIR"
export COLLAB_WORKSPACE_DIR="$WORKSPACE_DIR"
export GEMINI_MODEL="${GEMINI_MODEL:-gemini-4-hydrogen-high}"
export GEMINI_MODE="${GEMINI_MODE:-accept-edits}"
export GEMINI_SETTINGS_FILE="${GEMINI_SETTINGS_FILE:-$HUB_DIR/gemini-collab-settings.json}"
export GEMINI_IDLE_TIMEOUT_MS="${GEMINI_IDLE_TIMEOUT_MS:-300000}"
export GEMINI_MAX_TIMEOUT_MS="${GEMINI_MAX_TIMEOUT_MS:-900000}"
export GEMINI_WARN_TOKENS="${GEMINI_WARN_TOKENS:-524000,629000,734000}"
export GEMINI_AUTO_HANDOVER_TOKENS="${GEMINI_AUTO_HANDOVER_TOKENS:-734000}"

echo "🚀 Đang mở Gemini Telegram Bridge (model=$GEMINI_MODEL, mode=$GEMINI_MODE, idle=${GEMINI_IDLE_TIMEOUT_MS}ms, max=${GEMINI_MAX_TIMEOUT_MS}ms, autoHandover=${GEMINI_AUTO_HANDOVER_TOKENS})..."
exec "$BUN_BIN" run "$BRIDGE_SCRIPT"
