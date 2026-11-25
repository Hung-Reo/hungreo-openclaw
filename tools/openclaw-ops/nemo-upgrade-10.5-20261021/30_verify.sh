#!/usr/bin/env bash
# 30 — CLAUDE CHẠY (read-only) sau cutover và trong soak: ssh … 'bash -s' < 30_verify.sh
set -u
export TZ=Asia/Ho_Chi_Minh
S=/home/hung/sandbox-nemo
echo "now=$(date '+%F %T')"
docker inspect nemo-sandbox --format 'started={{.State.StartedAt}} running={{.State.Running}} restarts={{.RestartCount}} oom={{.State.OOMKilled}}'
echo "core=$(docker exec nemo-sandbox node -e 'console.log(require("/sandbox/runtime/node_modules/openclaw/package.json").version)') readyz=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18796/readyz)"
docker stats --no-stream --format 'mem={{.MemUsage}} pids={{.PIDs}} cpu={{.CPUPerc}}' nemo-sandbox
echo "codex_app_server=$(docker exec nemo-sandbox sh -c 'grep -l "[a]pp-server" /proc/[0-9]*/cmdline 2>/dev/null | wc -l')  (#178804: phải ổn định, không tăng dần; image không có ps nên đếm qua /proc)"
python3 - "$S/config" <<'PY'
import sqlite3,json,sys,pathlib
c=pathlib.Path(sys.argv[1])
db=sqlite3.connect((c/'state/openclaw.sqlite').as_uri()+'?mode=ro',uri=True)
idx=json.loads(db.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()[0])['index']['installRecords']
print("plugins:",{k:idx[k].get('version') for k in ('codex','lossless-claw') if k in idx})
l=sqlite3.connect((c/'lcm.db').as_uri()+'?mode=ro',uri=True)
q=lambda s:l.execute(s).fetchone()[0]
print(f"lcm: quick_check={q('pragma quick_check')} msgs={q('select count(*) from messages')} summaries={q('select count(*) from summaries')} last_msg={q('select max(created_at) from messages')}")
cfg=json.loads((c/'openclaw.json').read_text())
print("model:",cfg['agents']['defaults']['model'].get('primary'),"fb:",cfg['agents']['defaults']['model'].get('fallbacks'),"sessionCatalog:",cfg['plugins']['entries'].get('codex',{}).get('config',{}).get('sessionCatalog','<default>'))
PY
ST=$(docker inspect nemo-sandbox --format '{{.State.StartedAt}}')
L=$(docker logs --since "$ST" nemo-sandbox 2>&1)
echo "-- log từ lúc start: rss_threshold=$(grep -c rss_threshold <<<"$L") session-rebound=$(grep -c 'session-rebound' <<<"$L") (#178608) inbound=$(grep -c 'Inbound message' <<<"$L") outbound_ok=$(grep -c 'outbound send ok' <<<"$L")"
echo "-- lỗi/cảnh báo (bỏ rss_threshold)"
grep -iE 'error|fail|unhandled|EAGAIN' <<<"$L" | grep -v rss_threshold | sed -E 's/chatId=[0-9]+/chatId=<R>/g; s/bot[0-9]+:[A-Za-z0-9_-]+/bot<R>/g; s/sk-or-[^ "]+/<R>/g' | cut -c1-200 | tail -10 || true
echo "-- plugin khởi động"; grep -E 'http server listening' <<<"$L" | tail -1 | cut -c1-220
echo "-- H/S/Hermes"; for u in openclaw-gateway-hungreo openclaw-gateway-suckhoe hermes-gateway; do echo "$u $(systemctl --user show $u.service -p MainPID --value) NRestarts=$(systemctl --user show $u.service -p NRestarts --value) $(systemctl --user is-active $u.service)"; done
free -m | sed -n 2,3p
