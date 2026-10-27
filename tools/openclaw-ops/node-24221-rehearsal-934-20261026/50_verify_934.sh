#!/usr/bin/env bash
# 50_verify_934.sh — READ-ONLY Verify 3 tầng sau khi nâng OpenClaw 2026.9.34 + Node v24.22.1 + LCM 1.2.0.
set -euo pipefail
export TZ=Asia/Ho_Chi_Minh
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

P=${1:?Usage: 50_verify_934.sh <suckhoe|hungreo>}
case "$P" in
  suckhoe)
    PORT=18795
    EXPECTED_PLUGINS=("codex" "brave" "deepseek")
    ;;
  hungreo)
    PORT=18789
    EXPECTED_PLUGINS=("codex" "brave" "deepseek" "parallel" "typesafe")
    ;;
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
NR=$(systemctl --user show "$U" -p NRestarts --value)
SINCE=$(systemctl --user show "$U" -p ActiveEnterTimestamp --value)
RZ=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/readyz" || true)
EXE=$(readlink -f "/proc/$PID/exe")
NVER=$("$EXE" -v)
OSSL=$("$EXE" -p 'process.versions.openssl')
CVER=$(tr '\0' '\n' < "/proc/$PID/environ" | grep '^OPENCLAW_SERVICE_VERSION=' | cut -d= -f2 || true)
RSS=$(( $(awk '/VmRSS/{print $2}' "/proc/$PID/status")/1024 ))
SWP=$(( $(awk '/VmSwap/{print $2}' "/proc/$PID/status")/1024 ))

echo "== $P: active=$ACT pid=$PID since='$SINCE' NRestarts=$NR readyz=$RZ =="
echo "   node_exe=$EXE node_ver=$NVER openssl=$OSSL core=$CVER rss=${RSS}MiB swap=${SWP}MiB"

[ "$ACT" = "active" ] || { echo "FAIL: $U not active"; exit 1; }
[ "$RZ" = "200" ] || { echo "FAIL: readyz=$RZ"; exit 1; }
[ "$NR" = "0" ] || { echo "FAIL: NRestarts=$NR"; exit 1; }
[ "$EXE" = "$EXPECTED_NODE" ] || { echo "FAIL: exe=$EXE != $EXPECTED_NODE"; exit 1; }
[ "$NVER" = "v24.22.1" ] || { echo "FAIL: node_ver=$NVER"; exit 1; }
[ "$OSSL" = "3.5.9" ] || { echo "FAIL: openssl=$OSSL"; exit 1; }
[ "$CVER" = "2026.9.34" ] || { echo "FAIL: core=$CVER != 2026.9.34"; exit 1; }

jq -c '{primary:.agents.defaults.model.primary, fb:.agents.defaults.model.fallbacks, slot:.plugins.slots.contextEngine, stream:.channels.telegram.streaming}' "$D/openclaw.json"

ENV_FILE="$D/gateway.systemd.env"
ENV_MISSING=$(comm -23 <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$ENV_FILE" | cut -d= -f1 | sort -u) <(tr '\0' '\n' < "/proc/$PID/environ" | cut -d= -f1 | sort -u) || true)
J=$(journalctl --user -u "$U" --since "$SINCE" --no-pager -o short-iso)
SDEG=$(grep -cE 'SECRETS_(DEGRADED|OWNER_UNAVAILABLE)' <<<"$J" || true)
LDEG=$(grep -c 'degraded to "legacy"' <<<"$J" || true)
echo "   env_missing=[$ENV_MISSING] secrets_degraded=$SDEG degraded_legacy=$LDEG"
[ -z "$ENV_MISSING" ] || { echo "FAIL: env_missing=$ENV_MISSING"; exit 1; }
[ "$SDEG" = "0" ] || { echo "FAIL: secrets_degraded=$SDEG"; exit 1; }
[ "$LDEG" = "0" ] || { echo "FAIL: degraded_legacy=$LDEG"; exit 1; }

python3 - "$D" "${EXPECTED_PLUGINS[@]}" <<'PY'
import json, pathlib, sqlite3, sys
d = pathlib.Path(sys.argv[1])
expected_plugins = sys.argv[2:]
s = sqlite3.connect(f"file:{d}/state/openclaw.sqlite?mode=ro", uri=True)
l = sqlite3.connect(f"file:{d}/lcm.db?mode=ro", uri=True)
a = sqlite3.connect(f"file:{d}/agents/main/agent/openclaw-agent.sqlite?mode=ro", uri=True)
sqc = s.execute("pragma quick_check").fetchone()[0]
lqc = l.execute("pragma quick_check").fetchone()[0]
aqc = a.execute("pragma quick_check").fetchone()[0]
auv = a.execute("pragma user_version").fetchone()[0]
idx = json.loads(s.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()[0])["index"]["installRecords"]
pvers = {k: idx.get(k, {}).get("version") for k in expected_plugins}
lcm_v = idx.get("lossless-claw", {}).get("version")
msgs = l.execute("select count(*) from messages").fetchone()[0]
cur = l.execute("select origin, mode, count(*) from conversation_transcript_cursors group by 1,2").fetchall()
dup = l.execute("select count(*) from (select conversation_id, transcript_entry_id from messages where transcript_entry_id is not null group by 1,2 having count(*)>1)").fetchone()[0]
s.close(); l.close(); a.close()
print(f"   sqlite quick_check: state={sqc} lcm={lqc} agent={aqc}(uv={auv}) | plugins={pvers} lcm={lcm_v} msgs={msgs} cursors={cur} dup_entry_id={dup}")
assert sqc == "ok" and lqc == "ok" and aqc == "ok", "quick_check != ok"
assert auv == 24, f"user_version={auv} != 24"
for k, v in pvers.items():
    assert v == "2026.9.34", f"{k}={v} != 2026.9.34"
assert lcm_v == "1.2.0" and dup == 0
PY

echo "   -- CLI probe (oc_profile $P channels status --probe):"
PROBE_OUT=$(oc_profile channels status --probe 2>&1 | redact_stream || true)
echo "$PROBE_OUT" | tail -12
grep -q "works" <<<"$PROBE_OUT" || { echo "FAIL: channels status --probe không báo works"; exit 1; }

GW_DEEP=$(oc_profile gateway status --deep 2>&1 | redact_stream || true)
if grep -qE "Plugin version drift:|Service config issue:" <<<"$GW_DEEP"; then
  echo "FAIL: phát hiện cảnh báo trong gateway status --deep:"
  grep -E "Plugin version drift:|Service config issue:" <<<"$GW_DEEP" || true
  exit 1
fi
echo "   -- gateway status --deep: 0 plugin drift, 0 service config issues"

echo "OK 50_VERIFY_934_PASS profile=$P"
