#!/usr/bin/env bash
# 00_precheck.sh — READ-ONLY Precheck trên VPS cho:
#   - Pha A: Nâng Node.js v24.21.0 -> v24.22.1 (cô lập đường dẫn mới) cho suckhoe & hungreo (giữ core 2026.9.33 + LCM 1.2.0)
#   - Pha B1: Stage & Rehearsal cô lập OpenClaw 2026.9.34 (extended-stable) + Node 24.22.1 + LCM 1.2.0
# Tuyệt đối chỉ đọc, không sửa file/state/config, không in secret/token/chatId.
set -euo pipefail
export TZ=Asia/Ho_Chi_Minh
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

redact_stream() {
  sed -E 's/sessionKey=[^ ]+/sessionKey=<R>/g; s/chatId=[0-9-]+/chatId=<R>/g; s/telegram:(direct:|group:)?[0-9-]+/telegram:<R>/g; s/bot[0-9]+:[A-Za-z0-9_-]+/bot<R>/g; s/sk-[^ "]+/<R>/g; s/eyJ[^ "]+/<R>/g'
}

echo "== [0] Host, Arch, Time & Resources ($(date '+%F %T %Z')) =="
echo "hostname=$(hostname) arch=$(uname -m) kernel=$(uname -r)"
free -m
df -Th / /tmp /home/hung

echo ""
echo "== [1] Current Node & OpenClaw Runtime Paths =="
export PATH="/home/hung/openclaw-upgrade-20260924/node/bin:/home/hung/openclaw-upgrade-20261003/node/bin:/home/hung/.npm-global/bin:/usr/local/bin:/usr/bin:/bin"
OLD_NODE="/home/hung/openclaw-upgrade-20261003/node/bin/node"
OLD_NPM="$(command -v npm)"
RT_933="/home/hung/openclaw-upgrade-20261018-933/runtime"
echo "old_node=$OLD_NODE realpath=$(readlink -f "$OLD_NODE") version=$($OLD_NODE -v) npm=$OLD_NPM ($($OLD_NPM -v))"
echo "rt_933=$RT_933 openclaw_ver=$(jq -r .version "$RT_933/node_modules/openclaw/package.json")"

echo ""
echo "== [2] References to old Node binary in ~/.config/systemd/user and ~/bin =="
grep -rn "openclaw-upgrade-20261003/node" /home/hung/.config/systemd/user /home/hung/bin 2>/dev/null | redact_stream || true

echo ""
echo "== [3] Live Gates Check on Current Node ($($OLD_NODE -v)) =="
"$OLD_NODE" --test /home/hung/openclaw-upgrade-20261003/live-gates/patch-openclaw-plugin-binding-decline-fallback.test.mjs >/dev/null
"$OLD_NODE" /home/hung/openclaw-upgrade-20261003/live-gates/verify-command-registry-98.mjs "$RT_933/node_modules/openclaw/dist"
echo "LIVE_GATES_CURRENT_NODE_OK"

echo ""
echo "== [4] Health & State of suckhoe, hungreo, nemo-sandbox, hermes-gateway =="
for p in suckhoe hungreo; do
  U="openclaw-gateway-$p.service"
  D="/home/hung/.openclaw-$p"
  PORT=$([ "$p" = suckhoe ] && echo 18795 || echo 18789)
  PID=$(systemctl --user show "$U" -p MainPID --value)
  SINCE=$(systemctl --user show "$U" -p ActiveEnterTimestamp --value)
  NR=$(systemctl --user show "$U" -p NRestarts --value)
  RZ=$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/readyz" || echo err)
  EXE=$(readlink -f "/proc/$PID/exe" 2>/dev/null || echo unknown)
  RSS=$(( $(awk '/VmRSS/{print $2}' "/proc/$PID/status" 2>/dev/null || echo 0) / 1024 ))
  SWP=$(( $(awk '/VmSwap/{print $2}' "/proc/$PID/status" 2>/dev/null || echo 0) / 1024 ))
  echo "-- $p: active=$(systemctl --user is-active "$U") pid=$PID since='$SINCE' NRestarts=$NR readyz=$RZ rss=${RSS}MiB swap=${SWP}MiB exe=$EXE"
  jq -c '{primary:.agents.defaults.model.primary,fb:.agents.defaults.model.fallbacks,slot:.plugins.slots.contextEngine,stream:.channels.telegram.streaming.mode}' "$D/openclaw.json"
  miss=$(for v in $(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$D/gateway.systemd.env" | cut -d= -f1); do strings "/proc/$PID/environ" | grep -q "^$v=" || echo -n "$v "; done)
  deg=$(journalctl --user -u "$U" --since "$SINCE" --no-pager | grep -cE 'SECRETS_(DEGRADED|OWNER_UNAVAILABLE)' || true)
  echo "   env_missing=[${miss}] secrets_degraded=${deg}"

  python3 - "$D" <<'PY'
from contextlib import closing
import json, pathlib, sqlite3, sys, time
d = pathlib.Path(sys.argv[1])
with closing(sqlite3.connect(f"file:{d}/state/openclaw.sqlite?mode=ro", uri=True)) as sdb:
    qc_s = sdb.execute("pragma quick_check").fetchone()[0]
    in_flight = sdb.execute("select count(*) from task_runs where status in ('running','pending','queued','starting')").fetchone()[0]
    pending_app = sdb.execute("select count(*) from operator_approvals where status='pending'").fetchone()[0]
    row = sdb.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()
    idx = json.loads(row[0])["index"]["installRecords"] if row else {}
    codex_v = idx.get("codex", {}).get("version")
    lcm_v = idx.get("lossless-claw", {}).get("version")
    exps = []
    def walk(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if k.lower() in ("expires", "expiresat", "expires_at") and isinstance(v, (int, float)):
                    ts = v / 1000.0 if v > 1e11 else float(v)
                    if ts > 1700000000:
                        exps.append(ts)
                else:
                    walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)
    for (val,) in sdb.execute("select value_json from config_machine_state"):
        try:
            walk(json.loads(val))
        except Exception:
            pass
    min_oauth_h = round((min(exps) - time.time()) / 3600.0, 1) if exps else None
with closing(sqlite3.connect(f"file:{d}/lcm.db?mode=ro", uri=True)) as ldb:
    qc_l = ldb.execute("pragma quick_check").fetchone()[0]
    msgs = ldb.execute("select count(*) from messages").fetchone()[0]
    cursors = ldb.execute("select origin, mode, count(*) from conversation_transcript_cursors group by 1, 2").fetchall()
    gaps = ldb.execute("select count(*), coalesce(sum(entry_count),0) from conversation_transcript_gaps").fetchone()
    dup_eid = ldb.execute("select count(*) from (select conversation_id, transcript_entry_id from messages where transcript_entry_id is not null group by 1,2 having count(*)>1)").fetchone()[0]
with closing(sqlite3.connect(f"file:{d}/agents/main/agent/openclaw-agent.sqlite?mode=ro", uri=True)) as adb:
    qc_a = adb.execute("pragma quick_check").fetchone()[0]
    uv_a = adb.execute("pragma user_version").fetchone()[0]
print(f"   sqlite quick_check: state={qc_s} lcm={qc_l} agent={qc_a}(user_version={uv_a})")
print(f"   in_flight_tasks={in_flight} pending_approvals={pending_app} min_oauth_expires_in_h={min_oauth_h}")
print(f"   plugins: codex={codex_v} lossless-claw={lcm_v} | lcm msgs={msgs} cursors={cursors} gaps={gaps} dup_entry_id={dup_eid}")
PY
done

echo "-- timers & other bots:"
echo "   healthcheck.timer=$(systemctl --user is-active openclaw-healthcheck.timer || true) healthcheck.service=$(systemctl --user is-active openclaw-healthcheck.service || true)"
echo "   hermes-gateway=$(systemctl --user is-active hermes-gateway.service || true) NRestarts=$(systemctl --user show hermes-gateway.service -p NRestarts --value 2>/dev/null || true)"
docker inspect nemo-sandbox --format '   nemo-sandbox: status={{.State.Status}} restarts={{.RestartCount}} oom={{.State.OOMKilled}}' 2>/dev/null || true
echo "   nemo readyz=$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:18796/readyz || echo err)"

echo ""
echo "== [5] Upstream Metadata Check: Node.js v24.22.1 & OpenClaw 2026.9.34 =="
curl -fsSL https://nodejs.org/dist/v24.22.1/SHASUMS256.txt | grep "node-v24.22.1-linux-x64.tar"
"$OLD_NPM" view openclaw dist-tags --json
"$OLD_NPM" view openclaw@2026.9.34 version engines dist.integrity dist.tarball --json
"$OLD_NPM" view @openclaw/codex@2026.9.34 version peerDependencies dist.integrity dist.tarball --json

echo ""
echo "OK 00_PRECHECK_DONE"
