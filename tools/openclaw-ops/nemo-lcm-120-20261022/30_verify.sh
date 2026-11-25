#!/usr/bin/env bash
# 30 — CLAUDE CHẠY (read-only): soak Nemo (core 10.5) trước/sau LCM 1.2.0. ssh … 'bash -s' < 30_verify.sh
set -u
export TZ=Asia/Ho_Chi_Minh
S=/home/hung/sandbox-nemo
echo "now=$(date '+%F %T')"
docker inspect nemo-sandbox --format 'started={{.State.StartedAt}} running={{.State.Running}} restarts={{.RestartCount}} oom={{.State.OOMKilled}}'
echo "core=$(docker exec nemo-sandbox node -e 'console.log(require("/sandbox/runtime/node_modules/openclaw/package.json").version)') readyz=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18796/readyz)"
docker stats --no-stream --format 'mem={{.MemUsage}} pids={{.PIDs}} cpu={{.CPUPerc}}' nemo-sandbox
ID=$(docker inspect nemo-sandbox --format '{{.Id}}'); CG=/sys/fs/cgroup/system.slice/docker-$ID.scope
echo "cgroup: memory.peak=$(( $(cat $CG/memory.peak 2>/dev/null || echo 0)/1048576 ))MiB swap.peak=$(( $(cat $CG/memory.swap.peak 2>/dev/null || echo 0)/1048576 ))MiB oom_kill=$(awk '/^oom_kill /{print $2}' $CG/memory.events 2>/dev/null)"
echo "codex_app_server=$(docker exec nemo-sandbox sh -c 'grep -l "[a]pp-server" /proc/[0-9]*/cmdline 2>/dev/null | wc -l')  (#178804: không tăng dần)"
python3 - "$S/config" <<'PY'
import sqlite3,json,sys,pathlib
c=pathlib.Path(sys.argv[1])
db=sqlite3.connect((c/'state/openclaw.sqlite').as_uri()+'?mode=ro',uri=True)
idx=json.loads(db.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()[0])['index']['installRecords']
print("plugins:",{k:idx[k].get('version') for k in ('codex','lossless-claw') if k in idx})
l=sqlite3.connect((c/'lcm.db').as_uri()+'?mode=ro',uri=True); q=lambda s:l.execute(s).fetchone()[0]
t={r[0] for r in l.execute("select name from sqlite_master where type='table'")}
print(f"lcm: quick_check={q('pragma quick_check')} msgs={q('select count(*) from messages')} summaries={q('select count(*) from summaries')} last_msg={q('select max(created_at) from messages')}")
print("lcm: dup_entry_id=",q("select count(*) from (select conversation_id,transcript_entry_id from messages where transcript_entry_id is not null group by 1,2 having count(*)>1)"),
      " cursors=",q("select count(*) from conversation_transcript_cursors") if "conversation_transcript_cursors" in t else "(chưa có bảng)",
      " gaps=",q("select count(*) from conversation_transcript_gaps") if "conversation_transcript_gaps" in t else "(chưa có bảng)")
a=sqlite3.connect((c/'agents/main/agent/openclaw-agent.sqlite').as_uri()+'?mode=ro',uri=True)
print("agent_db user_version=",a.execute("pragma user_version").fetchone()[0])
cfg=json.loads((c/'openclaw.json').read_text())
print("model:",cfg['agents']['defaults']['model'].get('primary'),"fb:",cfg['agents']['defaults']['model'].get('fallbacks'))
PY
ST=$(docker inspect nemo-sandbox --format '{{.State.StartedAt}}')
L=$(docker logs --since "$ST" nemo-sandbox 2>&1)
echo "-- log từ lúc start: inbound=$(grep -c 'Inbound message' <<<"$L") outbound_ok=$(grep -c 'outbound send ok' <<<"$L") rss_threshold=$(grep -c rss_threshold <<<"$L") session-rebound=$(grep -c 'session-rebound' <<<"$L")"
echo "-- LCM: cursor_mode_entered=$(grep -c 'transcript cursor mode entered' <<<"$L") resync=$(grep -c '\[lcm\] transcript resync' <<<"$L") capability_error=$(grep -c 'readSessionTranscriptVisibleMessageDelta is required' <<<"$L") lcm_error=$(grep -E '\[lcm\]' <<<"$L" | grep -ciE 'error|fail')"
echo "-- lỗi/cảnh báo (bỏ rss_threshold, operator.read)"
grep -iE 'error|fail|unhandled|EAGAIN' <<<"$L" | grep -vE 'rss_threshold|operator.read' | sed -E 's/chatId=[0-9]+/chatId=<R>/g; s/telegram:[0-9]+/telegram:<R>/g; s/bot[0-9]+:[A-Za-z0-9_-]+/bot<R>/g; s/sk-or-[^ "]+/<R>/g' | cut -c1-200 | tail -10 || true
echo "-- H/S/Hermes"; for u in openclaw-gateway-hungreo openclaw-gateway-suckhoe hermes-gateway; do echo "$u $(systemctl --user show $u.service -p MainPID --value) NRestarts=$(systemctl --user show $u.service -p NRestarts --value) $(systemctl --user is-active $u.service)"; done
free -m | sed -n 2,3p
