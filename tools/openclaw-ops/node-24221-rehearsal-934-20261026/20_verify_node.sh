#!/usr/bin/env bash
# 20_verify_node.sh — READ-ONLY Verify sau khi nâng Node v24.22.1 cho suckhoe hoặc hungreo.
set -euo pipefail
export TZ=Asia/Ho_Chi_Minh
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

P=${1:?Usage: 20_verify_node.sh <suckhoe|hungreo>}
case "$P" in
  suckhoe) PORT=18795 ;;
  hungreo) PORT=18789 ;;
  *) echo "ABORT: invalid profile $P"; exit 1 ;;
esac

D="/home/hung/.openclaw-$P"
U="openclaw-gateway-$P.service"
EXPECTED_NODE="/home/hung/openclaw-node-24.22.1/node/bin/node"

redact_stream() {
  sed -E 's/sessionKey=[^ ]+/sessionKey=<R>/g; s/chatId=[0-9-]+/chatId=<R>/g; s/telegram:(direct:|group:)?[0-9-]+/telegram:<R>/g; s/bot[0-9]+:[A-Za-z0-9_-]+/bot<R>/g; s/sk-[^ "]+/<R>/g; s/eyJ[^ "]+/<R>/g'
}

oc_profile() {
  (
    for v in $(compgen -v OPENCLAW_ 2>/dev/null || true); do unset "$v"; done
    unset TELEGRAM_BOT_TOKEN
    set -a
    [ -f "$D/gateway.systemd.env" ] && . "$D/gateway.systemd.env"
    set +a
    OPENCLAW_PROFILE="$P" \
    OPENCLAW_STATE_DIR="$D" \
    OPENCLAW_CONFIG_PATH="$D/openclaw.json" \
    OPENCLAW_GATEWAY_PORT="$PORT" \
    OPENCLAW_SYSTEMD_UNIT="$U" \
      timeout 120 /home/hung/bin/openclaw --profile "$P" "$@" < /dev/null
  )
}

ACT=$(systemctl --user is-active "$U")
PID=$(systemctl --user show "$U" -p MainPID --value)
SINCE=$(systemctl --user show "$U" -p ActiveEnterTimestamp --value)
NR=$(systemctl --user show "$U" -p NRestarts --value)
RZ=$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/readyz" || echo err)
EXE=$(readlink -f "/proc/$PID/exe")
NVER=$("$EXE" -v)
OSSL=$("$EXE" -p 'process.versions.openssl')
CORE_VER=$(strings "/proc/$PID/environ" | grep '^OPENCLAW_SERVICE_VERSION=' | cut -d= -f2 || true)
RSS=$(( $(awk '/VmRSS/{print $2}' "/proc/$PID/status") / 1024 ))
SWP=$(( $(awk '/VmSwap/{print $2}' "/proc/$PID/status") / 1024 ))

echo "== $P: active=$ACT pid=$PID since='$SINCE' NRestarts=$NR readyz=$RZ =="
echo "   node_exe=$EXE node_ver=$NVER openssl=$OSSL core=$CORE_VER rss=${RSS}MiB swap=${SWP}MiB"
[ "$ACT" = "active" ]
[ "$RZ" = "200" ]
[ "$EXE" = "$EXPECTED_NODE" ]
[ "$NVER" = "v24.22.1" ]
[ "$CORE_VER" = "2026.9.33" ]

jq -c '{primary:.agents.defaults.model.primary,fb:.agents.defaults.model.fallbacks,slot:.plugins.slots.contextEngine,stream:.channels.telegram.streaming.mode}' "$D/openclaw.json"

miss=$(for v in $(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$D/gateway.systemd.env" | cut -d= -f1); do strings "/proc/$PID/environ" | grep -q "^$v=" || echo -n "$v "; done)
deg=$(journalctl --user -u "$U" --since "$SINCE" --no-pager | grep -cE 'SECRETS_(DEGRADED|OWNER_UNAVAILABLE)' || true)
echo "   env_missing=[${miss}] secrets_degraded=${deg}"
[ -z "$miss" ]
[ "$deg" = "0" ]

python3 - "$D" <<'PY'
from contextlib import closing
import json, pathlib, sqlite3, sys
d = pathlib.Path(sys.argv[1])
with closing(sqlite3.connect(f"file:{d}/state/openclaw.sqlite?mode=ro", uri=True)) as sdb:
    qc_s = sdb.execute("pragma quick_check").fetchone()[0]
    row = sdb.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()
    idx = json.loads(row[0])["index"]["installRecords"] if row else {}
    codex_v = idx.get("codex", {}).get("version")
    lcm_v = idx.get("lossless-claw", {}).get("version")
with closing(sqlite3.connect(f"file:{d}/lcm.db?mode=ro", uri=True)) as ldb:
    qc_l = ldb.execute("pragma quick_check").fetchone()[0]
    msgs = ldb.execute("select count(*) from messages").fetchone()[0]
    cursors = ldb.execute("select origin, mode, count(*) from conversation_transcript_cursors group by 1, 2").fetchall()
    dup_eid = ldb.execute("select count(*) from (select conversation_id, transcript_entry_id from messages where transcript_entry_id is not null group by 1,2 having count(*)>1)").fetchone()[0]
with closing(sqlite3.connect(f"file:{d}/agents/main/agent/openclaw-agent.sqlite?mode=ro", uri=True)) as adb:
    qc_a = adb.execute("pragma quick_check").fetchone()[0]
print(f"   sqlite quick_check: state={qc_s} lcm={qc_l} agent={qc_a} | codex={codex_v} lcm={lcm_v} msgs={msgs} cursors={cursors} dup_entry_id={dup_eid}")
assert qc_s == "ok" and qc_l == "ok" and qc_a == "ok" and dup_eid == 0
PY

echo "   -- CLI probe (oc_profile $P channels status --probe):"
PROBE_OUT=$(oc_profile channels status --probe 2>&1 | redact_stream || true)
echo "$PROBE_OUT" | tail -8
grep -q "works" <<<"$PROBE_OUT"
echo "OK 20_VERIFY_NODE_PASS profile=$P"
