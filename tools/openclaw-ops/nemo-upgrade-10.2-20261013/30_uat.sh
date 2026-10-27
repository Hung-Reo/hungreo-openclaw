#!/bin/bash
# 30 — UAT sau cutover 10.2 (chỉ đọc + 2 lượt agent nhỏ trong Nemo). Chạy sau 20_cutover.sh CUTOVER_OK.
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 30_uat.sh
# Lượt 1: model mặc định (Muse). Lượt 2: ép fallback Sol 6.1 bằng --model (override chỉ cho lượt đó).
set -u
S=/home/hung/sandbox-nemo
oc(){ docker exec nemo-sandbox node /sandbox/runtime/node_modules/openclaw/dist/entry.js "$@" < /dev/null 2>&1; }
pick(){ python3 -c "import json,sys;t=sys.stdin.read();i=t.find('{');d=json.loads(t[i:]) if i>=0 else {};print({k:d.get(k) for k in ('status','model','provider')}, str(d.get('text') or d.get('reply') or t[:200])[:200])" 2>&1 | tail -2; }
echo "version: $(oc --version | head -1)"
echo "config: $(jq -c '{primary:.agents.defaults.model.primary,fb:.agents.defaults.model.fallbacks,stream:.channels.telegram.streaming.mode}' $S/config/openclaw.json)"
echo "--- channels status --probe"; oc channels status --probe | grep -viE "token|secret|key" | head -10
echo "--- plugins"; oc plugins list 2>&1 | grep -iE "codex|openrouter|typesafe|telegram|memory" | head -8
echo "--- UAT 1: mặc định"
oc agent --agent main -m "UAT nâng cấp 10.2: trả lời đúng một dòng 'UAT_DEFAULT_OK' và tên model bạn đang chạy." --json | pick
echo "--- UAT 2: ép openai/gpt-6.1-sol"
oc agent --agent main --model openai/gpt-6.1-sol -m "UAT fallback: trả lời đúng một dòng 'UAT_SOL61_OK'." --json | pick
echo "--- logs 10 phút (model/route/lỗi)"
docker logs --since 10m nemo-sandbox 2>&1 | grep -E "agent model|codex|openrouter|fallback|401|ERROR|error" | grep -viE "token|secret|key=" | cut -c1-200 | tail -12
docker stats --no-stream --format '{{.Name}} {{.MemUsage}}' nemo-sandbox
echo "UAT_SCRIPT_DONE"
