#!/bin/bash
# 12 — HƯNG CHẠY. Đặt fallback openai/gpt-6-sol (runtime codex, subscription ChatGPT) cho Nemo, bật plugin codex,
# start lại container, chờ ready. Primary Muse giữ nguyên.
set -euo pipefail
trap 'echo "FAILED ở dòng $LINENO — báo Claude Code (Nemo có thể đang dừng: docker start nemo-sandbox)"' ERR
S=/home/hung/sandbox-nemo
B=/home/hung/backups/nemo-sol-fallback-20261007
[ -f "$B/SHA256SUMS" ] || { echo "ABORT: chưa có backup bước 10"; exit 1; }
oc() { docker run --rm --user 1001:1001 --env-file "$S/nemo.env" \
  -v "$S/.npm:/sandbox/.npm" -v "$S/runtime-9.8:/sandbox/runtime:ro" -v "$S/config:/sandbox/config" \
  -v "$S/workspace:/sandbox/workspace" -v "$S/.cache:/sandbox/.cache" -v "$B:/sandbox/batch:ro" \
  node:24.21.0-bookworm-slim node /sandbox/runtime/node_modules/openclaw/dist/entry.js "$@" < /dev/null; }

rm -f "$B/batch.json"; cat > "$B/batch.json" <<'JSON'
[
 {"path":"plugins.entries.codex.enabled","value":true},
 {"path":"agents.defaults.models.openai/gpt-6-sol.agentRuntime.id","value":"codex"},
 {"path":"agents.defaults.model.fallbacks","value":["openai/gpt-6-sol"]}
]
JSON
echo "[1/4] dry-run"; oc config set --batch-file /sandbox/batch/batch.json --dry-run
echo "[2/4] áp dụng"; oc config set --batch-file /sandbox/batch/batch.json
echo "[3/4] DIFF config vs backup"
python3 - "$S/config/openclaw.json" "$B/openclaw.json" <<'PY'
import json, sys
def flat(d, p=""):
    o = {}
    if isinstance(d, dict):
        for k, v in d.items(): o.update(flat(v, p + "." + k))
    else: o[p] = d
    return o
a, b = flat(json.load(open(sys.argv[1]))), flat(json.load(open(sys.argv[2])))
for k in sorted(set(a) | set(b)):
    if a.get(k) != b.get(k):
        s = any(x in k.lower() for x in ("token", "key", "secret", "password"))
        print("  ", k, "| old=", "<R>" if s else b.get(k), "| new=", "<R>" if s else a.get(k))
PY
echo "[4/4] start Nemo"
SINCE=$(date +%s)
docker start nemo-sandbox >/dev/null
for i in $(seq 1 36); do docker logs --since "$SINCE" nemo-sandbox 2>&1 | grep -q "\[gateway\] ready" && { echo "  ready sau ~$((i*5))s"; break; }; sleep 5; done
docker logs --since "$SINCE" nemo-sandbox 2>&1 | grep -E "http server listening|Cannot find module|Invalid|error" | cut -c1-200 | head -5
echo "OK 12 — báo Claude Code kiểm + UAT"
