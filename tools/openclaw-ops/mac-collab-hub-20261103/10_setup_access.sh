#!/usr/bin/env bash
set -euo pipefail

# Script thiết lập .env và access.json (ngoài git repo) cho Claude & Codex trên Mac.
# Có tính năng TỰ ĐỘNG DÒ User ID & Group ID từ tin nhắn mới nhất gửi cho Bot (qua Telegram getUpdates API chính thức).
# Hỗ trợ chuyển nhanh giữa Giai đoạn 1 (allowBots=none) và Giai đoạn 2 (allowBots=mentions):
#   bash 10_setup_access.sh --set-stage 1
#   bash 10_setup_access.sh --set-stage 2

BUN_BIN="/Users/hungdinh/.nvm/versions/node/v22.16.0/bin/bun"
CLAUDE_STATE_DIR="$HOME/.claude/channels/telegram-collab"
CODEX_STATE_DIR="$HOME/.codex/channels/telegram-collab"

mkdir -p "$CLAUDE_STATE_DIR" "$CODEX_STATE_DIR"
chmod 700 "$CLAUDE_STATE_DIR" "$CODEX_STATE_DIR"

if [[ "${1:-}" == "--set-stage" ]]; then
  STAGE="${2:-1}"
  if [[ "$STAGE" != "1" && "$STAGE" != "2" ]]; then
    echo "Usage: $0 --set-stage <1|2>" >&2
    exit 1
  fi
  ALLOW_BOTS="none"
  [[ "$STAGE" == "2" ]] && ALLOW_BOTS="mentions"

  for f in "$CLAUDE_STATE_DIR/access.json" "$CODEX_STATE_DIR/access.json"; do
    if [[ -f "$f" ]]; then
      FILE_ALLOW_BOTS="$ALLOW_BOTS"
      [[ "$f" == "$CODEX_STATE_DIR/access.json" ]] && FILE_ALLOW_BOTS="none"
      "$BUN_BIN" -e '
        import { readFileSync, writeFileSync } from "fs";
        const file = process.argv[1];
        const mode = process.argv[2];
        const a = JSON.parse(readFileSync(file, "utf8"));
        for (const gid of Object.keys(a.groups || {})) {
          a.groups[gid].allowBots = mode;
          a.groups[gid].botsRequireMention = true;
          a.groups[gid].requireMention = true;
        }
        writeFileSync(file, JSON.stringify(a, null, 2) + "\n", { mode: 0o600 });
      ' "$f" "$FILE_ALLOW_BOTS"
      echo "Updated $f -> Stage $STAGE (allowBots=$FILE_ALLOW_BOTS, botsRequireMention=true)"
    else
      echo "Skip $f (chưa tạo)"
    fi
  done
  exit 0
fi

echo "=== Thiết lập Bot Token & Access Policy cho Mac Collaboration Hub ==="
echo "(Mọi thông tin nhạy cảm được lưu tại ~/.claude và ~/.codex với quyền 0600, KHÔNG lưu vào git repo)"
echo ""

read -rsp "1. Nhập TELEGRAM_BOT_TOKEN cho Claude trên Mac (Enter để giữ nguyên nếu đã có): " CLAUDE_TOKEN
echo ""
if [[ -n "$CLAUDE_TOKEN" ]]; then
  umask 077
  printf "TELEGRAM_BOT_TOKEN=%s\n" "$CLAUDE_TOKEN" > "$CLAUDE_STATE_DIR/.env"
  chmod 600 "$CLAUDE_STATE_DIR/.env"
  echo "   -> Đã lưu token Claude (sha256 prefix: $(printf '%s' "$CLAUDE_TOKEN" | shasum -a 256 | cut -c1-8))"
fi

read -rsp "2. Nhập TELEGRAM_BOT_TOKEN cho Codex trên Mac (Enter để bỏ qua nếu chưa tạo bot Codex): " CODEX_TOKEN
echo ""
if [[ -n "$CODEX_TOKEN" ]]; then
  umask 077
  printf "TELEGRAM_BOT_TOKEN=%s\n" "$CODEX_TOKEN" > "$CODEX_STATE_DIR/.env"
  chmod 600 "$CODEX_STATE_DIR/.env"
  echo "   -> Đã lưu token Codex (sha256 prefix: $(printf '%s' "$CODEX_TOKEN" | shasum -a 256 | cut -c1-8))"
fi

# Tự động dò User ID và Group ID qua Telegram getUpdates nếu đã có token Claude
DETECTED_USER_ID=""
DETECTED_GROUP_ID=""
if [[ -f "$CLAUDE_STATE_DIR/.env" ]]; then
  echo ""
  echo "💡 Mẹo tự động lấy ID: Hãy thêm bot Claude vừa tạo vào Group Telegram và nhắn 1 tin bất kỳ (vd: hello) trong Group đó."
  read -rp "   Bấm Enter sau khi bạn đã nhắn 1 tin trong Group để script tự động dò User ID & Group ID..." _
  DETECT_OUT="$("$BUN_BIN" -e '
    import { readFileSync } from "fs";
    const envText = readFileSync(process.argv[1], "utf8");
    const m = envText.match(/^TELEGRAM_BOT_TOKEN=(.+)$/m);
    if (!m) process.exit(0);
    const token = m[1].trim();
    const res = await fetch(`https://api.telegram.org/bot${token}/getUpdates?limit=20`);
    const data = await res.json() as any;
    if (!data.ok || !Array.isArray(data.result)) process.exit(0);
    let userId = "";
    let userLabel = "";
    let groupId = "";
    let groupTitle = "";
    for (const u of [...data.result].reverse()) {
      const msg = u.message || u.edited_message || u.my_chat_member;
      if (!msg) continue;
      if (!userId && msg.from && !msg.from.is_bot) {
        userId = String(msg.from.id);
        userLabel = msg.from.username ? `@${msg.from.username}` : (msg.from.first_name || "");
      }
      if (!groupId && msg.chat && (msg.chat.type === "group" || msg.chat.type === "supergroup")) {
        groupId = String(msg.chat.id);
        groupTitle = msg.chat.title || "";
      }
    }
    console.log(JSON.stringify({ userId, userLabel, groupId, groupTitle }));
  ' "$CLAUDE_STATE_DIR/.env" 2>/dev/null || echo '{}')"

  DETECTED_USER_ID="$("$BUN_BIN" -e 'console.log(JSON.parse(process.argv[1]).userId || "")' "$DETECT_OUT" 2>/dev/null || true)"
  DETECTED_USER_LABEL="$("$BUN_BIN" -e 'console.log(JSON.parse(process.argv[1]).userLabel || "")' "$DETECT_OUT" 2>/dev/null || true)"
  DETECTED_GROUP_ID="$("$BUN_BIN" -e 'console.log(JSON.parse(process.argv[1]).groupId || "")' "$DETECT_OUT" 2>/dev/null || true)"
  DETECTED_GROUP_TITLE="$("$BUN_BIN" -e 'console.log(JSON.parse(process.argv[1]).groupTitle || "")' "$DETECT_OUT" 2>/dev/null || true)"

  if [[ -n "$DETECTED_USER_ID" || -n "$DETECTED_GROUP_ID" ]]; then
    echo "   ✨ Đã tự động dò thấy từ Telegram Bot API:"
    [[ -n "$DETECTED_USER_ID" ]] && echo "      - User ID của Hưng ($DETECTED_USER_LABEL): $DETECTED_USER_ID"
    [[ -n "$DETECTED_GROUP_ID" ]] && echo "      - Group ID (\"$DETECTED_GROUP_TITLE\"): $DETECTED_GROUP_ID"
  else
    echo "   (Chưa thấy tin nhắn mới trong getUpdates — bạn có thể nhập tay bên dưới)"
  fi
fi

echo ""
read -rp "3. Nhập Telegram Numeric User ID của Hưng [${DETECTED_USER_ID:-nhập số}]: " HUNG_ID
HUNG_ID="${HUNG_ID:-$DETECTED_USER_ID}"

read -rp "4. Nhập Telegram Group ID của phòng họp (bắt đầu bằng dấu trừ -...) [${DETECTED_GROUP_ID:-nhập số âm}]: " GROUP_ID
GROUP_ID="${GROUP_ID:-$DETECTED_GROUP_ID}"

read -rp "5. Nhập danh sách Bot User IDs được phép trong Group ở Giai đoạn 2 (cách nhau dấu phẩy, vd ID của Hermes; Enter để trống): " PEER_BOT_IDS
read -rp "6. Chọn giai đoạn khởi đầu [1 = Chỉ Hưng gọi từng bot (Khuyến nghị), 2 = Bật Bot-to-Bot có giới hạn]: " INIT_STAGE
INIT_STAGE="${INIT_STAGE:-1}"
ALLOW_BOTS="none"
[[ "$INIT_STAGE" == "2" ]] && ALLOW_BOTS="mentions"

for dir in "$CLAUDE_STATE_DIR" "$CODEX_STATE_DIR"; do
  DIR_ALLOW_BOTS="$ALLOW_BOTS"
  DIR_PEERS="$PEER_BOT_IDS"
  if [[ "$dir" == "$CODEX_STATE_DIR" ]]; then
    DIR_ALLOW_BOTS="none"
    DIR_PEERS=""
  fi
  "$BUN_BIN" -e '
    import { writeFileSync } from "fs";
    const [file, hungId, groupId, peerBotsRaw, allowBots] = process.argv.slice(1);
    const peerIds = peerBotsRaw.split(",").map(s => s.trim()).filter(Boolean);
    const groupAllow = Array.from(new Set([hungId, ...peerIds].filter(Boolean)));
    const access = {
      dmPolicy: "allowlist",
      allowFrom: hungId ? [hungId] : [],
      groups: groupId ? {
        [groupId]: {
          requireMention: true,
          botsRequireMention: true,
          allowBots,
          allowFrom: groupAllow,
        }
      } : {},
      pending: {},
      ackReaction: "👀",
      replyToMode: "first",
      textChunkLimit: 4000,
      chunkMode: "newline",
      botLoopGuard: {
        maxEventsPerWindow: 4,
        windowMs: 120000,
        cooldownMs: 180000
      }
    };
    writeFileSync(file, JSON.stringify(access, null, 2) + "\n", { mode: 0o600 });
  ' "$dir/access.json" "$HUNG_ID" "$GROUP_ID" "$DIR_PEERS" "$DIR_ALLOW_BOTS"
  chmod 600 "$dir/access.json"
done

echo ""
echo "✅ Đã tạo xong access.json (mode 0600) cho cả Claude & Codex ở Giai đoạn $INIT_STAGE (allowBots=$ALLOW_BOTS)."
