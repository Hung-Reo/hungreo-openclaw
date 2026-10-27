#!/bin/bash
# 20_verify.sh — READ-ONLY xác minh sau khi chạy 10_apply.sh cho từng bot (suckhoe | hungreo).
set -euo pipefail
export TZ=Asia/Ho_Chi_Minh

P=${1:?bot (suckhoe|hungreo)}
case "$P" in
  suckhoe) PORT=18795 ;;
  hungreo) PORT=18789 ;;
  *) echo "ABORT: dùng suckhoe hoặc hungreo"; exit 1 ;;
esac

D=$HOME/.openclaw-$P
U=openclaw-gateway-$P.service
OC=/home/hung/bin/openclaw

oc() {
  (
    for v in $(compgen -v OPENCLAW_ 2>/dev/null || true); do unset "$v"; done
    unset TELEGRAM_BOT_TOKEN
    set -a
    [ -f "$D/gateway.systemd.env" ] && . "$D/gateway.systemd.env"
    set +a
    OPENCLAW_PROFILE="$P" OPENCLAW_STATE_DIR="$D" OPENCLAW_CONFIG_PATH="$D/openclaw.json" \
      OPENCLAW_GATEWAY_PORT="$PORT" OPENCLAW_SYSTEMD_UNIT="$U" \
      timeout 180 "$OC" --profile "$P" "$@" < /dev/null
  )
}

SINCE=$(systemctl --user show "$U" -p ActiveEnterTimestamp --value | awk '{print $2" "$3}')
PID=$(systemctl --user show "$U" -p MainPID --value)
echo "== $P $(systemctl --user is-active "$U") pid=$PID since=$SINCE NRestarts=$(systemctl --user show "$U" -p NRestarts --value) KillMode=$(systemctl --user show "$U" -p KillMode --value) readyz=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/readyz")"
echo "   core=$(strings "/proc/$PID/environ" 2>/dev/null | grep ^OPENCLAW_SERVICE_VERSION= | cut -d= -f2) rss_MiB=$(( $(awk '/VmRSS/{print $2}' "/proc/$PID/status" 2>/dev/null || echo 0)/1024 ))"
jq -c '{primary:.agents.defaults.model.primary,fb:.agents.defaults.model.fallbacks,slot:.plugins.slots.contextEngine,stream:.channels.telegram.streaming.mode}' "$D/openclaw.json"

# Env check (chỉ đếm/in tên biến thiếu, không in giá trị)
miss=$(for v in $(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$D/gateway.systemd.env" | cut -d= -f1); do strings "/proc/$PID/environ" | grep -q "^$v=" || echo -n "$v "; done)
deg=$(journalctl --user -u "$U" --since "$SINCE" --no-pager | grep -cE 'SECRETS_(DEGRADED|OWNER_UNAVAILABLE)' || true)
echo "   env_missing=[${miss}] secrets_degraded=${deg}"

echo "-- gateway status --deep:"
oc gateway status --deep 2>&1 | grep -vE 'sk-|eyJ'

echo "-- channels status --probe:"
oc channels status --probe 2>&1 | grep -vE 'sk-|eyJ'

echo "-- SQLite quick_check & installedIndex:"
python3 - "$D/state/openclaw.sqlite" "$D/lcm.db" <<'PY'
import sqlite3, sys, json
for db in sys.argv[1:]:
    con = sqlite3.connect("file:" + db + "?mode=ro", uri=True)
    try:
        print(f"  quick_check {db.split('/')[-1]}:", con.execute("pragma quick_check").fetchone()[0])
    finally:
        con.close()

con = sqlite3.connect("file:" + sys.argv[1] + "?mode=ro", uri=True)
try:
    def walk(o):
        if isinstance(o, dict):
            for k, v in sorted(o.items()):
                if isinstance(v, dict) and "spec" in v and "installPath" in v:
                    print(f"  plugin {k}: spec={v.get('spec')} version={v.get('version')}")
                else:
                    walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)
    for (v,) in con.execute("select value_json from config_machine_state"):
        try:
            walk(json.loads(v))
        except Exception:
            pass
finally:
    con.close()
PY

J=$(journalctl --user -u "$U" --since "$SINCE" --no-pager)
echo "-- log từ lúc start: dòng lỗi/cảnh báo (ngoài rss_threshold):"
grep -iE 'error|fail|warn|unhandled' <<<"$J" | grep -v rss_threshold | cut -c1-220 | tail -12 || true
free -m | sed -n 2,3p
