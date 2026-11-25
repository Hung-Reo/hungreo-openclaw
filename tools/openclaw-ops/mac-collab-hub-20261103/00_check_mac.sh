#!/usr/bin/env bash
set -euo pipefail

HUB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUN_BIN="/Users/hungdinh/.nvm/versions/node/v22.16.0/bin/bun"
CODEX_BIN="/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
CLAUDE_BIN="$(find "$HOME/Library/Application Support/Claude/claude-code" -name claude -type f 2>/dev/null | sort -V | tail -n 1)"

echo "=== [1/6] Kiểm tra Binaries trên Mac (Claude Desktop, Codex App, Bun) ==="
if [[ -z "$CLAUDE_BIN" || ! -x "$CLAUDE_BIN" ]]; then
  echo "FAIL: Không tìm thấy binary claude trong Claude Desktop App" >&2
  exit 1
fi
echo "OK Claude binary: $CLAUDE_BIN ($("$CLAUDE_BIN" --version))"

if ! grep -a -q -- "--channels" "$CLAUDE_BIN"; then
  echo "FAIL: Binary Claude không hỗ trợ cờ --channels" >&2
  exit 1
fi
echo "OK Claude binary hỗ trợ --channels & notifications/claude/channel"

if [[ ! -x "$CODEX_BIN" ]]; then
  echo "FAIL: Không tìm thấy binary codex trong ChatGPT.app ($CODEX_BIN)" >&2
  exit 1
fi
echo "OK Codex binary: $CODEX_BIN ($("$CODEX_BIN" --version))"

if [[ ! -x "$BUN_BIN" ]]; then
  echo "FAIL: Không tìm thấy bun tại $BUN_BIN" >&2
  exit 1
fi
echo "OK Bun binary: $BUN_BIN ($("$BUN_BIN" --version))"

echo ""
echo "=== [2/6] Kiểm tra Global Settings Isolation & collab-settings.json ==="
GLOBAL_TG="$("$BUN_BIN" -e 'import {readFileSync} from "fs"; const s=JSON.parse(readFileSync(process.argv[1],"utf8")); console.log(s.enabledPlugins?.["telegram@claude-plugins-official"]);' "$HOME/.claude/settings.json")"
if [[ "$GLOBAL_TG" != "false" ]]; then
  echo "FAIL: ~/.claude/settings.json vẫn bật telegram@claude-plugins-official=$GLOBAL_TG (cần đặt false để chỉ bật qua collab-settings.json)" >&2
  exit 1
fi
echo "OK ~/.claude/settings.json: telegram@claude-plugins-official = false (không chạy ngầm ở phiên thường)"

if [[ ! -f "$HUB_DIR/collab-settings.json" ]]; then
  echo "FAIL: Thiếu $HUB_DIR/collab-settings.json" >&2
  exit 1
fi
echo "OK collab-settings.json hiện diện & bật telegram plugin riêng cho phiên collab"

echo ""
echo "=== [3/6] Kiểm tra cú pháp & đóng gói TypeScript (Dry-run build) ==="
"$BUN_BIN" build "$HUB_DIR/claude-telegram-plugin/server.ts" --target=bun --outdir=/tmp/mac-collab-check-claude >/dev/null
"$BUN_BIN" build "$HUB_DIR/codex-telegram-bridge/server.ts" --target=bun --outdir=/tmp/mac-collab-check-codex >/dev/null
rm -rf /tmp/mac-collab-check-claude /tmp/mac-collab-check-codex
echo "OK Build check PASS: claude-telegram-plugin/server.ts & codex-telegram-bridge/server.ts"

echo ""
echo "=== [4/6] Chạy 14 Unit Tests cho Security Gate, BotLoopGuard, Codex Sandbox & Redaction ==="
"$BUN_BIN" run "$HUB_DIR/test_gates.ts"

echo ""
echo "=== [5/6] Kiểm tra trạng thái cấu hình State Dir (Không in secret/ID) ==="
for pair in "claude:$HOME/.claude/channels/telegram-collab" "codex:$HOME/.codex/channels/telegram-collab"; do
  name="${pair%%:*}"
  dir="${pair#*:}"
  env_ok="MISSING"
  acc_ok="MISSING"
  stage_info="N/A"
  if [[ -f "$dir/.env" ]] && grep -q '^TELEGRAM_BOT_TOKEN=..*' "$dir/.env"; then
    env_ok="CONFIGURED (mode $(stat -f '%Lp' "$dir/.env"))"
  fi
  if [[ -f "$dir/access.json" ]]; then
    acc_ok="CONFIGURED (mode $(stat -f '%Lp' "$dir/access.json"))"
    stage_info="$("$BUN_BIN" -e '
      import { readFileSync } from "fs";
      const a = JSON.parse(readFileSync(process.argv[1], "utf8"));
      const g = Object.values(a.groups || {})[0] as any;
      console.log(`dm_allow=${(a.allowFrom||[]).length}, groups=${Object.keys(a.groups||{}).length}, allowBots=${g?.allowBots ?? "none"}, botsRequireMention=${g?.botsRequireMention ?? true}`);
    ' "$dir/access.json" 2>/dev/null || echo "PARSE_ERR")"
  fi
  echo "  - $name ($dir): .env=$env_ok | access.json=$acc_ok [$stage_info]"
done

echo ""
echo "=== [6/6] Kết luận: Môi trường Mac SẴN SÀNG ==="
