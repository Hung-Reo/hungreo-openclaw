#!/usr/bin/env bash
set -euo pipefail

# Khôi phục nguyên trạng cấu hình plugin & settings Claude trên Mac về trước khi cài đặt Mac Collab Hub.

CACHE_DIR="$HOME/.claude/plugins/cache/claude-plugins-official/telegram/0.0.7"
if [[ -f "$CACHE_DIR/server.ts.orig-20261103" ]]; then
  cp "$CACHE_DIR/server.ts.orig-20261103" "$CACHE_DIR/server.ts"
  rm -f "$CACHE_DIR/collab-gate.ts" "$CACHE_DIR/collab-gate.ts.bak-20261103"
fi
if [[ -f "$CACHE_DIR/.mcp.json.orig-20261103" ]]; then
  cp "$CACHE_DIR/.mcp.json.orig-20261103" "$CACHE_DIR/.mcp.json"
fi
if [[ -f "$HOME/.claude/plugins/installed_plugins.json.bak-20261103" ]]; then
  cp "$HOME/.claude/plugins/installed_plugins.json.bak-20261103" "$HOME/.claude/plugins/installed_plugins.json"
fi
if [[ -f "$HOME/.claude/settings.json.bak-20261103" ]]; then
  cp "$HOME/.claude/settings.json.bak-20261103" "$HOME/.claude/settings.json"
fi

echo "Đã rollback cấu hình plugin và ~/.claude/settings.json trên Mac về nguyên trạng."
