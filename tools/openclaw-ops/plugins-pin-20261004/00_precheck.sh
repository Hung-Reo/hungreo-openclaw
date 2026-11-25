#!/bin/bash
# 00 — READ-ONLY (Claude Code chạy). Chụp trạng thái trước bảo trì + bằng chứng 403 Suckhoe (A1/A2) trước khi restart xoá trạng thái trong process.
# Chạy: ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 00_precheck.sh | tee evidence/00_precheck.txt
export TZ=Asia/Ho_Chi_Minh
OC=/home/hung/bin/openclaw
date
echo "== services"
for s in hungreo suckhoe; do
  u=openclaw-gateway-$s.service
  echo "$s $(systemctl --user is-active $u) pid=$(systemctl --user show $u -p MainPID --value) since=$(systemctl --user show $u -p ActiveEnterTimestamp --value)"
done
systemctl --user is-active openclaw-healthcheck.timer
df -h / | tail -1
echo "== config sha + key fields"
for p in hungreo suckhoe; do
  sha256sum ~/.openclaw-$p/openclaw.json | cut -c1-16
  jq -c "{p:\"$p\",primary:.agents.defaults.model.primary,fb:.agents.defaults.model.fallbacks,timeout:.agents.defaults.timeoutSeconds}" ~/.openclaw-$p/openclaw.json
done
echo "== plugin versions (global origin)"
for p in hungreo suckhoe; do
  OPENCLAW_STATE_DIR=$HOME/.openclaw-$p timeout 90 $OC --profile $p plugins list --json 2>/dev/null |
    python3 -c 'import json,sys;d=json.load(sys.stdin);ps=d.get("plugins",d);print(sys.argv[1],{x["id"]:x.get("version") for x in ps if x.get("origin")=="global"})' $p
done
echo "== suckhoe auth (no tokens)"
OPENCLAW_STATE_DIR=$HOME/.openclaw-suckhoe timeout 60 $OC --profile suckhoe models auth list 2>&1 | sed -E 's/(ey[A-Za-z0-9_-]{10,}|sk-[A-Za-z0-9_-]+)/<R>/g'
echo "== suckhoe 403 occurrences today"
journalctl --user -u openclaw-gateway-suckhoe.service --since today --no-pager | grep "403 Forbidden" | cut -c1-16 | uniq -c
echo "== suckhoe memory index"
OPENCLAW_STATE_DIR=$HOME/.openclaw-suckhoe OPENCLAW_CONFIG_PATH=$HOME/.openclaw-suckhoe/openclaw.json timeout 90 $OC --profile suckhoe memory status --agent main 2>&1 | grep -iE "files|chunks|dirty|vector|provider" | head -8
