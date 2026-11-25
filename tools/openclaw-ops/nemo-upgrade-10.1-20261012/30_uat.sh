#!/bin/bash
# 30 — UAT sau cutover (chỉ đọc + 2 lượt agent nhỏ trong Nemo). Chạy sau 20_cutover.sh CUTOVER_OK.
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 30_uat.sh
# Lượt 1: model mặc định (Muse). Lượt 2: ép fallback Sol 6.1 bằng --model (override CHỈ cho lượt đó, không ghim session).
set -u
S=/home/hung/sandbox-nemo
oc(){ docker exec nemo-sandbox node /sandbox/runtime/node_modules/openclaw/dist/entry.js "$@" < /dev/null 2>&1; }
echo "version: $(oc --version | head -1)"
echo "config: $(jq -c '{primary:.agents.defaults.model.primary,fb:.agents.defaults.model.fallbacks,sol61:.agents.defaults.models["openai/gpt-6.1-sol"],stream:.channels.telegram.streaming.mode}' $S/config/openclaw.json)"
echo "--- models status (rút gọn, không in secret)"
oc models status --plain | grep -viE "token|secret|key|@" | head -25
echo "--- plugins"; oc plugins list 2>&1 | grep -iE "codex|perplexity|typesafe|telegram" | head -8
echo "--- UAT 1: mặc định"
oc agent --agent main -m "UAT nâng cấp 10.1: trả lời đúng một dòng 'UAT_DEFAULT_OK' và tên model bạn đang chạy." --json | python3 -c "import json,sys;d=json.loads(sys.stdin.read());print({k:d.get(k) for k in ('status','model','provider')}, str(d.get('text') or d.get('reply') or '')[:160])" 2>&1 | tail -2
echo "--- UAT 2: ép openai/gpt-6.1-sol"
oc agent --agent main --model openai/gpt-6.1-sol -m "UAT fallback: trả lời đúng một dòng 'UAT_SOL61_OK'." --json | python3 -c "import json,sys;d=json.loads(sys.stdin.read());print({k:d.get(k) for k in ('status','model','provider')}, str(d.get('text') or d.get('reply') or '')[:160])" 2>&1 | tail -2
echo "--- logs 10 phút (model/route/lỗi)"
docker logs --since 10m nemo-sandbox 2>&1 | grep -E "agent model|codex|openrouter|fallback|401|ERROR|error" | grep -viE "token|secret|key=" | cut -c1-200 | tail -12
docker stats --no-stream --format '{{.Name}} {{.MemUsage}}' nemo-sandbox
echo "UAT_SCRIPT_DONE — báo Claude Code đọc kết quả"
