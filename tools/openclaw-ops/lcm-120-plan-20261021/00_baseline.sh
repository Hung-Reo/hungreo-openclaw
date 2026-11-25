#!/bin/bash
# 00 — Baseline READ-ONLY trước LCM 1.2.0 (Claude chạy): ssh … 'bash -s' < 00_baseline.sh
# Không in nội dung tin nhắn/secret; chỉ đếm, thời gian, kích thước.
set -u
export TZ=Asia/Ho_Chi_Minh
echo "now=$(date '+%F %T')"
free -m | sed -n 2,3p; cat /proc/swaps | tail -n +2
lcm_stats() {  # $1=label $2=path lcm.db
python3 - "$1" "$2" <<'PY'
import sqlite3,sys,os
lab,db=sys.argv[1:3]
c=sqlite3.connect("file:"+db+"?mode=ro",uri=True)
q=lambda s:c.execute(s).fetchone()[0]
sz=sum(os.path.getsize(db+x) for x in ("","-wal") if os.path.exists(db+x))//2**20
print(f"  [{lab}] lcm.db+wal={sz}MiB conv={q('select count(*) from conversations')} active={q('select count(*) from conversations where active=1')} msgs={q('select count(*) from messages')} summaries={q('select count(*) from summaries')} pending_nodes={q('select count(*) from pending_summary_nodes')}")
print(f"    msgs_no_entry_id={q('select count(*) from messages where transcript_entry_id is null')} dup_entry_id={q('select count(*) from (select conversation_id,transcript_entry_id from messages where transcript_entry_id is not null group by 1,2 having count(*)>1)')} dup_identity={q('select count(*) from (select conversation_id,identity_hash from messages where identity_hash is not null group by 1,2 having count(*)>1)')}")
top=c.execute("select conversation_id,count(*) n from messages group by 1 order by n desc limit 3").fetchall()
print("    top_conv_msgs:",[n for _,n in top], " msgs_last24h:",q("select count(*) from messages where created_at>=datetime('now','-1 day')"))
print("    quick_check:",q("pragma quick_check"))
PY
}
for p in hungreo suckhoe; do
  U=openclaw-gateway-$p.service; D=$HOME/.openclaw-$p; PID=$(systemctl --user show $U -p MainPID --value)
  echo "== $p pid=$PID since=$(systemctl --user show $U -p ActiveEnterTimestamp --value) rss=$(( $(awk '/VmRSS/{print $2}' /proc/$PID/status)/1024 ))MiB swap=$(( $(awk '/VmSwap/{print $2}' /proc/$PID/status)/1024 ))MiB"
  J=$(journalctl --user -u $U --since "-7d" --no-pager -o short-iso 2>/dev/null)
  echo -n "  rss_threshold/ngày:"; grep rss_threshold <<<"$J" | cut -c1-10 | sort | uniq -c | awk '{printf " %s=%s",substr($2,6),$1}'; echo
  echo -n "  rss_peak GiB/ngày:"; grep -oE '^[0-9-]{10}.*rss=[0-9.]+ GiB' <<<"$J" | sed -E 's/^([0-9-]{10}).*rss=([0-9.]+) GiB/\1 \2/' | sort -k1,1 -k2,2n | awk '{m[$1]=$2} END{for(d in m) printf " %s=%s",substr(d,6),m[d]}' | tr ' ' '\n' | sort | tr '\n' ' '; echo
  echo "  reply-resolver totalMs (3 ngày, n/median/p90/max):"
  grep 'reply resolver timings' <<<"$J" | awk -v d="$(date -d '-3 day' +%F)" 'substr($1,1,10)>=d' | grep -oE 'totalMs=[0-9]+' | cut -d= -f2 | sort -n | awk '{a[NR]=$1} END{if(NR) printf "    n=%d med=%d p90=%d max=%d\n",NR,a[int(NR/2)+1],a[((int(NR*0.9)+1)>NR)?NR:(int(NR*0.9)+1)],a[NR]; else print "    (không có)"}'
  echo "  turns: inbound=$(grep -c 'Inbound message' <<<"$J") outbound_ok=$(grep -c 'outbound send ok' <<<"$J") lossless_err=$(grep -iE 'lossless|lcm' <<<"$J" | grep -ciE 'error|fail') compaction=$(grep -ciE 'compact' <<<"$J")"
  DB=$(jq -r '.plugins.entries["lossless-claw"].config.dbPath // empty' $D/openclaw.json); lcm_stats $p "${DB:-$D/lcm.db}"
done
echo "== nemo"
docker inspect nemo-sandbox --format '  started={{.State.StartedAt}} restarts={{.RestartCount}} oom={{.State.OOMKilled}}'
docker stats --no-stream --format '  mem={{.MemUsage}} pids={{.PIDs}}' nemo-sandbox
NL=$(docker logs --timestamps --since 168h nemo-sandbox 2>&1)
echo -n "  rss_threshold/ngày:"; grep rss_threshold <<<"$NL" | cut -c1-10 | sort | uniq -c | awk '{printf " %s=%s",substr($2,6),$1}'; echo
echo "  reply-resolver totalMs (3 ngày):"; grep 'reply resolver timings' <<<"$NL" | awk -v d="$(date -u -d '-3 day' +%F)" 'substr($1,1,10)>=d' | grep -oE 'totalMs=[0-9]+' | cut -d= -f2 | sort -n | awk '{a[NR]=$1} END{if(NR) printf "    n=%d med=%d p90=%d max=%d\n",NR,a[int(NR/2)+1],a[((int(NR*0.9)+1)>NR)?NR:(int(NR*0.9)+1)],a[NR]; else print "    (không có)"}'
echo "  lossless_err=$(grep -iE 'lossless|lcm' <<<"$NL" | grep -ciE 'error|fail')"
NDB=$(docker exec nemo-sandbox sh -c 'ls /sandbox/config/lcm.db 2>/dev/null || find /sandbox/config -maxdepth 2 -name lcm.db | head -1')
HDB=$(docker inspect nemo-sandbox --format '{{range .Mounts}}{{if eq .Destination "/sandbox/config"}}{{.Source}}{{end}}{{end}}')${NDB#/sandbox/config}
[ -f "$HDB" ] && lcm_stats nemo "$HDB" || echo "  nemo lcm.db không đọc được từ host ($HDB)"
