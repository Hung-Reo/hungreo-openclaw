#!/usr/bin/env bash
# Hưng GO 24/11 17:53: switch Rùa primary to openai/gpt-6.2-sol (fallback unchanged).
set -Eeuo pipefail; umask 077
P=/home/hung/.openclaw-hungreo; U=/home/hung/openclaw-upgrade-hungreo-20261123-117
NODE=/home/hung/openclaw-node-24.22.1/node/bin/node; ENTRY=$U/runtime/node_modules/openclaw/dist/index.js
UNIT=openclaw-gateway-hungreo.service; TIMER=openclaw-healthcheck.timer; D=/home/hung/backups/hungreo-sol62-20261124
ready() { curl -sS --max-time 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:18789/readyz 2>/dev/null; }
oc() (
  for item in $(compgen -v OPENCLAW_ || true); do unset "$item"; done
  unset TELEGRAM_BOT_TOKEN OPENAI_API_KEY
  set -a; source "$P/gateway.systemd.env"; set +a; unset OPENAI_API_KEY
  export OPENCLAW_PROFILE=hungreo OPENCLAW_STATE_DIR="$P" OPENCLAW_CONFIG_PATH="$P/openclaw.json" OPENCLAW_GATEWAY_PORT=18789 OPENCLAW_SYSTEMD_UNIT=$UNIT
  export PATH="${NODE%/*}:/usr/bin:/bin" DBUS_SESSION_BUS_ADDRESS="unix:path=$U/missing-user-bus"
  cd "$P/workspace"; timeout --kill-after=30 "${T:-300}" "$NODE" "$ENTRY" --profile hungreo "$@" </dev/null
)
state() { python3 -I -c "
import sqlite3,json
db=sqlite3.connect('file:$P/state/openclaw.sqlite?mode=ro',uri=True)
s=json.loads(db.execute(\"select state_json from cron_jobs where name='heartbeat-main'\").fetchone()[0])
busy=db.execute(\"select count(*) from task_runs where status in ('running','pending','queued','starting')\").fetchone()[0]
print(s.get('lastRunAtMs') or 0, 1 if s.get('runningAtMs') else 0, busy)"; }
start_back() { systemctl --user start "$UNIT"; for i in $(seq 1 60); do [[ "$(ready)" == 200 ]] && break; sleep 3; done; systemctl --user start "$TIMER"; }
restore() { trap - ERR; echo "RESTORE_BEGIN"; systemctl --user stop "$UNIT" || true; cp -p "$D/openclaw.json.pre-sol62" "$P/openclaw.json"; start_back; echo "RESTORED readyz=$(ready)"; exit 1; }
last=0; running=1; busy=1
target=$(( $(date -d 18:33:18 +%s) * 1000 )); deadline=$(date -d 18:55 +%s)
while (( $(date +%s) < deadline )); do read last running busy < <(state); (( last >= target - 60000 && running == 0 && busy == 0 )) && break; sleep 15; done
echo "$(date +%T) heartbeat last=$last running=$running busy=$busy"
(( last >= target - 60000 && running == 0 && busy == 0 ))
cp -p "$P/openclaw.json" "$D/openclaw.json.pre-sol62"
python3 -I "$U/ops/profile-check.py" batch "$P/openclaw.json" "$D/model-batch.json"
trap restore ERR
systemctl --user stop "$TIMER" openclaw-healthcheck.service; systemctl --user stop "$UNIT"; echo "$(date +%T) stopped"
oc config set --batch-file "$D/model-batch.json" --dry-run > "$D/dryrun.log" 2>&1; tail -2 "$D/dryrun.log" | cut -c1-200
oc config set --batch-file "$D/model-batch.json" > "$D/set.log" 2>&1; tail -2 "$D/set.log" | cut -c1-200
oc config validate > "$D/validate.log" 2>&1; tail -1 "$D/validate.log"
jq -c '.agents.defaults.model' "$P/openclaw.json"
start_back; echo "$(date +%T) readyz=$(ready)"
probe=$(cat /proc/sys/kernel/random/uuid)
T=150 oc agent --agent main --session-id "$probe" --model openai/gpt-6.2-sol --thinking medium \
  --message 'Reply with exactly RUA_SOL62_OK. Do not use tools or send any messages.' --json --timeout 105 > "$D/receipt.json" 2> "$D/receipt.err"
python3 -I "$U/ops/profile-check.py" receipt "$D/receipt.json"
journalctl --user -u "$UNIT" --since "-4 min" --no-pager | grep "http server listening" | tail -1 | cut -c60-260
echo "TIMER=$(systemctl --user is-active $TIMER) SUCKHOE=$(curl -s -o /dev/null -w %{http_code} http://127.0.0.1:18795/readyz)"
echo SWITCH_OK
