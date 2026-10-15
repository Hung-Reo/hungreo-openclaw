#!/bin/bash
# 20 — CLAUDE CHẠY (read-only) sau 10_upgrade.sh và sau lượt Telegram của Hưng:  ssh … 'bash -s suckhoe' < 20_verify.sh
set -u
export TZ=Asia/Ho_Chi_Minh
P=${1:?bot}; D=$HOME/.openclaw-$P; U=openclaw-gateway-$P.service
case "$P" in suckhoe) PORT=18795 ;; hungreo) PORT=18789 ;; esac
SINCE=$(systemctl --user show $U -p ActiveEnterTimestamp --value | awk '{print $2" "$3}')
PID=$(systemctl --user show $U -p MainPID --value)
echo "== $P $(systemctl --user is-active $U) since=$SINCE NRestarts=$(systemctl --user show $U -p NRestarts --value) readyz=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/readyz)"
echo "core=$(strings /proc/$PID/environ | grep ^OPENCLAW_SERVICE_VERSION= | cut -d= -f2) rss_MiB=$(( $(awk '/VmRSS/{print $2}' /proc/$PID/status)/1024 ))"
jq -c '{primary:.agents.defaults.model.primary,fb:.agents.defaults.model.fallbacks,slot:.plugins.slots.contextEngine,stream:.channels.telegram.streaming.mode}' $D/openclaw.json
DB=$(jq -r '.plugins.entries["lossless-claw"].config.dbPath // empty' $D/openclaw.json); DB=${DB:-$D/lcm.db}
python3 - "$D/state/openclaw.sqlite" "$DB" <<'PY'
import sqlite3,sys,re,json
c=sqlite3.connect("file:"+sys.argv[1]+"?mode=ro",uri=True)
for (v,) in c.execute("select value_json from config_machine_state"):
    m=re.search(r'"lossless-claw":\{"source":"npm","spec":"([^"]+)","installPath":"([^"]+)"',v)
    if m: print("index:",m.group(1),"package:",json.load(open(m.group(2)+"/package.json"))["version"]); break
d=sqlite3.connect("file:"+sys.argv[2]+"?mode=ro",uri=True)
print("lcm quick_check:",d.execute("pragma quick_check").fetchone()[0])
print("ordinal cols:",[r[1] for r in d.execute("pragma table_info(pending_summary_nodes)") if "ordinal" in r[1]])
for t in("conversations","messages","summaries","pending_summary_nodes"): print(f"  {t}: {d.execute(f'select count(*) from {t}').fetchone()[0]}")
try:
    r=d.execute("select max(created_at) from messages").fetchone()[0]; print("  last message created_at:",r)
except Exception as e: print("  last message:",e)
PY
J=$(journalctl --user -u $U --since "$SINCE" --no-pager)
echo "-- log từ lúc start: dòng lỗi/cảnh báo (không tính rss_threshold)"
grep -iE 'error|fail|warn|unhandled' <<<"$J" | grep -v rss_threshold | cut -c1-220 | tail -12 || true
echo "-- LCM activity"
grep -iE 'lossless|lcm|foreground compaction|assemble' <<<"$J" | cut -c1-200 | tail -8 || true
echo "-- rss_threshold warnings: $(grep -c rss_threshold <<<"$J")"
echo "-- lượt Telegram: inbound=$(grep -c 'Inbound message' <<<"$J") outbound_ok=$(grep -c 'outbound send ok' <<<"$J")"
free -m | sed -n 2,3p
