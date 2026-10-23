#!/bin/bash
# 20 — read-only sau 10_apply.sh và sau lượt bấm nút của Hưng:  ssh hungreo-claude-vps 'bash -s' < 20_verify.sh
set -u
export TZ=Asia/Ho_Chi_Minh
P=hungreo; D=$HOME/.openclaw-$P; U=openclaw-gateway-$P.service; PORT=18789
KB=/home/hung/openclaw-shared/kb/education
SINCE=$(systemctl --user show $U -p ActiveEnterTimestamp --value | awk '{print $2" "$3}')
PID=$(systemctl --user show $U -p MainPID --value)
echo "== $P $(systemctl --user is-active $U) since=$SINCE NRestarts=$(systemctl --user show $U -p NRestarts --value) readyz=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/readyz)"
echo "core=$(strings /proc/$PID/environ 2>/dev/null | grep ^OPENCLAW_SERVICE_VERSION= | cut -d= -f2) rss_MiB=$(( $(awk '/VmRSS/{print $2}' /proc/$PID/status 2>/dev/null || echo 0)/1024 ))"
jq -c '{primary:.agents.defaults.model.primary,fb:.agents.defaults.model.fallbacks,slot:.plugins.slots.contextEngine,stream:.channels.telegram.streaming.mode,edu:(.plugins.entries["edu-review"].enabled),allow_edu:(.plugins.allow|index("edu-review")!=null)}' $D/openclaw.json
echo "-- sessions: DM override lệch primary (drift)"
python3 - $D <<'PY'
import json,glob,os,sys
d=sys.argv[1]; prim=json.load(open(d+"/openclaw.json"))["agents"]["defaults"]["model"]["primary"]
n=0
for f in glob.glob(d+"/agents/*/sessions/sessions.json"):
    try: s=json.load(open(f))
    except Exception: continue
    for k,v in (s.items() if isinstance(s,dict) else []):
        if isinstance(v,dict) and v.get("modelOverrideSource")=="auto" and v.get("modelOverride") and v.get("modelOverride")!=prim: n+=1
print("  drift sessions:",n)
PY
J=$(journalctl --user -u $U --since "$SINCE" --no-pager | sed -E -e '/sk-|eyJ/d' -e 's/[0-9]{6,}/<N>/g')
echo "-- log edu-review"; grep -iE 'edu-review|edu_review' <<<"$J" | cut -c1-220 | tail -10 || true
echo "-- lỗi/cảnh báo từ lúc start (bỏ rss_threshold)"; grep -iE 'error|fail|unhandled' <<<"$J" | grep -v rss_threshold | cut -c1-200 | tail -8 || true
echo "-- lượt Telegram: inbound=$(grep -c 'Inbound message' <<<"$J") outbound_ok=$(grep -c 'outbound send ok' <<<"$J")"
echo "-- KB education"; for d in inbox review state approved changes rejected invalid; do printf '  %-9s %s\n' $d "$(ls $KB/$d 2>/dev/null | grep -v offset | tr '\n' ' ')"; done
for f in $KB/state/EDU-*.json; do [ -e "$f" ] && jq -c '{key,status,sha:(.sha256[0:8]),notifiedAt,decidedAt,tried,publicOk}' "$f"; done 2>/dev/null
[ -f $KB/logs/events.jsonl ] && { echo "-- events"; tail -8 $KB/logs/events.jsonl | jq -c '{at,type,key}'; }
free -m | sed -n 2p
