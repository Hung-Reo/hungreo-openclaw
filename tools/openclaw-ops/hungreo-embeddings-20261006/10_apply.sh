#!/bin/bash
# 10 — HƯNG CHẠY. Bật embeddings cho memory_search của Hungreo (agent main), dùng chung khoá embeddings-only của Suckhoe.
# Mẫu y hệt Suckhoe 04/10 (openai-compatible + SecretRef file). Không restart gateway, không in khoá.
# Chạy lúc yên (Rùa không đang trả lời): trong lúc dựng lại index, memory_search của Rùa có thể rỗng vài phút.
set -euo pipefail
trap 'echo "FAILED ở dòng $LINENO — gửi output cho Claude Code"' ERR
export TZ=Asia/Ho_Chi_Minh
P=/home/hung/.openclaw-hungreo
KEY_SRC=/home/hung/.openclaw-suckhoe/credentials/memory-embeddings.key
KEY=$P/credentials/memory-embeddings.key
B=/home/hung/backups/hungreo-embeddings-20261006
OC=/home/hung/bin/openclaw
run() { OPENCLAW_STATE_DIR=$P OPENCLAW_CONFIG_PATH=$P/openclaw.json "$OC" --profile hungreo "$@"; }

[ -e "$B" ] && { echo "ABORT: $B đã tồn tại (đã chạy rồi?)"; exit 1; }
[ "$(jq -c '.agents.entries.main.memory // null' $P/openclaw.json)" = "null" ] || { echo "ABORT: memory config Hungreo đã khác null"; exit 1; }

echo "[1/6] backup config + agent DB"
mkdir -p "$B"
cp -p $P/openclaw.json "$B/openclaw.json"
python3 - "$P/agents/main/agent/openclaw-agent.sqlite" "$B/openclaw-agent.sqlite" <<'PY'
import sqlite3, sys
src = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True); dst = sqlite3.connect(sys.argv[2])
src.backup(dst); dst.close(); src.close()
PY
ls -l "$B"

echo "[2/6] chép khoá (không in nội dung)"
( umask 077; cp "$KEY_SRC" "$KEY" ); chmod 600 "$KEY"
stat -c '%a %s bytes %n' "$KEY"

echo "[3/6] batch config: dry-run"
cat > "$B/batch.json" <<JSON
[
 {"path":"secrets.providers.memkey","provider":{"source":"file","path":"$KEY","mode":"singleValue"}},
 {"path":"agents.entries.main.memory.search.provider","value":"openai-compatible"},
 {"path":"agents.entries.main.memory.search.model","value":"text-embedding-3-small"},
 {"path":"agents.entries.main.memory.search.remote.baseUrl","value":"https://api.openai.com/v1"},
 {"path":"agents.entries.main.memory.search.remote.apiKey","ref":{"source":"file","provider":"memkey","id":"value"}}
]
JSON
run config set --batch-file "$B/batch.json" --dry-run

echo "[4/6] áp dụng + secrets reload"
run config set --batch-file "$B/batch.json"
run secrets reload || true
sleep 3

echo "[5/6] dựng lại index (vài phút)"
date +%T
{ run memory index --force --agent main 2>&1 | grep -viE "key|token" | tail -5; } || true
date +%T

echo "[6/6] trạng thái"
{ run memory status --agent main 2>&1 | grep -E "Provider|Model|Indexed|Dirty|Vector|Batch"; } || true
echo "OK 10 — báo Claude Code kiểm"
