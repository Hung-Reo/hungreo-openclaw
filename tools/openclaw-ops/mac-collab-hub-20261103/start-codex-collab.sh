#!/usr/bin/env bash
set -euo pipefail

# Khởi chạy Codex Telegram Bridge trên Mac (dùng binary codex trong ChatGPT.app).
# Mặc định chạy ở chế độ sandbox read-only (Review/Verify).
# Truyền "--workspace-write" nếu Hưng muốn cho phép Codex sửa file trong workspace.

HUB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUN_BIN="/Users/hungdinh/.nvm/versions/node/v22.16.0/bin/bun"
export PATH="/Users/hungdinh/.nvm/versions/node/v22.16.0/bin:$PATH"
export CODEX_TELEGRAM_STATE_DIR="${CODEX_TELEGRAM_STATE_DIR:-$HOME/.codex/channels/telegram-collab}"
export COLLAB_WORKSPACE_DIR="${COLLAB_WORKSPACE_DIR:-/Users/hungdinh/Development/hungreo-openclaw}"
export CODEX_SANDBOX_MODE="read-only"

if [[ "${1:-}" == "--workspace-write" ]]; then
  export CODEX_SANDBOX_MODE="workspace-write"
  shift
fi

if [[ ! -f "$CODEX_TELEGRAM_STATE_DIR/.env" ]]; then
  echo "Chưa có $CODEX_TELEGRAM_STATE_DIR/.env. Hãy chạy: bash $HUB_DIR/10_setup_access.sh" >&2
  exit 1
fi

echo "🚀 Đang mở Codex Telegram Bridge (sandbox=$CODEX_SANDBOX_MODE, state=$CODEX_TELEGRAM_STATE_DIR)..."
exec "$BUN_BIN" run "$HUB_DIR/codex-telegram-bridge/server.ts" "$@"
