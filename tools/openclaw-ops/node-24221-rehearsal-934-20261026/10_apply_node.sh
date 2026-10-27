#!/usr/bin/env bash
# 10_apply_node.sh — Cutover Node.js v24.21.0 -> v24.22.1 (/home/hung/openclaw-node-24.22.1/node/bin/node)
# cho từng bot (suckhoe trước, hungreo sau) trên nền Core 2026.9.33 + LCM 1.2.0.
# Giữ nguyên tuyệt đối /home/hung/openclaw-upgrade-20261003/node (v24.21.0), openclaw.json, model/auth/fallback/slots, lcm.db.
set -Eeuo pipefail
umask 077
export TZ=Asia/Ho_Chi_Minh
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

P=${1:?Usage: 10_apply_node.sh <suckhoe|hungreo>}
case "$P" in
  suckhoe) PORT=18795; OTHER=hungreo ;;
  hungreo) PORT=18789; OTHER=suckhoe ;;
  *) echo "ABORT: invalid profile $P (must be suckhoe or hungreo)"; exit 1 ;;
esac

exec 9>"/tmp/openclaw-node-24221-apply.lock"
flock -n 9 || { echo "ABORT: một tiến trình 10_apply_node.sh khác đang chạy"; exit 1; }

NEW_NODE_DIR="/home/hung/openclaw-node-24.22.1/node/bin"
NEW_NODE="${NEW_NODE_DIR}/node"
OLD_NODE="/home/hung/openclaw-upgrade-20261003/node/bin/node"
LIVE_GATES_DIR="/home/hung/openclaw-upgrade-20261003/live-gates"
RT_933="/home/hung/openclaw-upgrade-20261018-933/runtime"
OPS_DIR="/home/hung/openclaw-node-24.22.1/ops"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
ROLLBACK_SH="$OPS_DIR/99_rollback_node.sh"
[ -f "$ROLLBACK_SH" ] || [ -z "$SCRIPT_DIR" ] || ROLLBACK_SH="$SCRIPT_DIR/99_rollback_node.sh"

D="/home/hung/.openclaw-$P"
U="openclaw-gateway-$P.service"
OTHER_U="openclaw-gateway-$OTHER.service"
UNITS="/home/hung/.config/systemd/user"
TS=$(date +%Y%m%d-%H%M%S)
B="/home/hung/backups/node-24221-$P-$TS"
PHASE=precheck

on_err() {
  [ "${BASH_SUBSHELL:-0}" -eq 0 ] || exit 1
  local line=$1
  echo "FAILED at line $line (phase=$PHASE, profile=$P)"
  if [ "$PHASE" = "precheck" ]; then
    echo "Chưa thay đổi gì; $U vẫn đang chạy."
  elif [ "$PHASE" = "stop_backup" ]; then
    echo "Chưa sửa drop-in -> bật lại $U và healthcheck timer."
    systemctl --user start "$U" || true
    if [ "${HC_WAS:-active}" = "active" ]; then
      systemctl --user start openclaw-healthcheck.timer || true
    fi
  else
    echo "Lỗi trong pha cutover -> tự động chạy 99_rollback_node.sh $P $B..."
    if [ -f "$ROLLBACK_SH" ]; then
      bash "$ROLLBACK_SH" "$P" "$B" || true
    else
      echo "Chạy thủ công: bash 99_rollback_node.sh $P $B"
    fi
  fi
  exit 1
}
trap 'on_err $LINENO' ERR

echo "== [0] Precheck cho $P ($TS) =="
[ "$(hostname)" = "srv1367812" ]
[ -x "$NEW_NODE" ] && [ "$("$NEW_NODE" -v)" = "v24.22.1" ] || { echo "ABORT: $NEW_NODE chưa ở v24.22.1"; exit 1; }
[ -x "$OLD_NODE" ] || { echo "ABORT: $OLD_NODE phải còn nguyên để rollback"; exit 1; }
[ -f "$ROLLBACK_SH" ] || { echo "ABORT: thiếu $OPS_DIR/99_rollback_node.sh (cần stage trước khi apply)"; exit 1; }
[ "$(systemctl --user is-active "$U")" = "active" ] || { echo "ABORT: $U không active"; exit 1; }
[ "$(systemctl --user is-active "$OTHER_U")" = "active" ] || { echo "ABORT: peer $OTHER_U không active"; exit 1; }
! systemctl --user is-active --quiet openclaw-healthcheck.service || { echo "ABORT: openclaw-healthcheck.service đang chạy"; exit 1; }

OTHER_PID_BEFORE=$(systemctl --user show "$OTHER_U" -p MainPID --value)
OTHER_RESTARTS_BEFORE=$(systemctl --user show "$OTHER_U" -p NRestarts --value)
CFG_SHA_BEFORE=$(sha256sum "$D/openclaw.json" | awk '{print $1}')

FREE_G=$(df -BG --output=avail /home/hung | tail -1 | tr -dc 0-9)
[ "$FREE_G" -ge 5 ] || { echo "ABORT: disk free ${FREE_G}G < 5G"; exit 1; }

"$NEW_NODE" --test "$LIVE_GATES_DIR/patch-openclaw-plugin-binding-decline-fallback.test.mjs" >/dev/null
"$NEW_NODE" "$LIVE_GATES_DIR/verify-command-registry-98.mjs" "$RT_933/node_modules/openclaw/dist" >/dev/null

python3 - "$D" <<'PY'
from contextlib import closing
import json, pathlib, sqlite3, sys
d = pathlib.Path(sys.argv[1])
with closing(sqlite3.connect(f"file:{d}/state/openclaw.sqlite?mode=ro", uri=True)) as db:
    assert db.execute("select count(*) from task_runs where status in ('running','pending','queued','starting')").fetchone()[0] == 0, "in-flight task_runs"
    assert db.execute("select count(*) from operator_approvals where status='pending'").fetchone()[0] == 0, "pending approvals"
    for (raw,) in db.execute("select state_json from cron_jobs where enabled=1"):
        assert not json.loads(raw).get("runningAtMs"), "cron job running"
    assert db.execute("pragma quick_check").fetchone()[0] == "ok"
with closing(sqlite3.connect(f"file:{d}/lcm.db?mode=ro", uri=True)) as lcm:
    assert lcm.execute("pragma quick_check").fetchone()[0] == "ok"
with closing(sqlite3.connect(f"file:{d}/agents/main/agent/openclaw-agent.sqlite?mode=ro", uri=True)) as adb:
    assert adb.execute("pragma quick_check").fetchone()[0] == "ok"
print("  PRECHECK_SQLITE_AND_IDLE_OK")
PY

PHASE=stop_backup
echo "== [1] Stop healthcheck timer + stop $U & Backup vào $B =="
mkdir -p -m 700 "$B"
HC_WAS=$(systemctl --user is-active openclaw-healthcheck.timer || true)
echo "$HC_WAS" > "$B/healthcheck_timer_state"

cp -p "$UNITS/$U.d/zzzzz-upgrade-99.conf" "$B/zzzzz-upgrade-99.conf"
if [ "$P" = "hungreo" ] && [ -f "$UNITS/hungreo-finance-backup.service.d/zz-upgrade-99.conf" ]; then
  cp -p "$UNITS/hungreo-finance-backup.service.d/zz-upgrade-99.conf" "$B/zz-upgrade-99.conf"
fi
cp -p /home/hung/bin/openclaw "$B/openclaw-cli"
cp -p /home/hung/bin/openclaw-healthcheck.sh "$B/openclaw-healthcheck.sh"
cp -p "$D/openclaw.json" "$B/openclaw.json"

systemctl --user stop openclaw-healthcheck.timer openclaw-healthcheck.service || true
systemctl --user stop "$U"

for _ in $(seq 1 15); do
  if [ "$(systemctl --user show "$U" -p MainPID --value)" = "0" ] && ! ss -ltn "sport = :$PORT" | grep -q LISTEN; then
    break
  fi
  sleep 1
done
[ "$(systemctl --user show "$U" -p MainPID --value)" = "0" ] || { echo "ABORT: $U vẫn đang chạy"; false; }
if ss -ltn "sport = :$PORT" | grep -q LISTEN; then
  echo "ABORT: cổng $PORT vẫn đang LISTEN"
  false
fi

python3 - "$D" "$B" <<'PY'
from contextlib import closing
import os, pathlib, sqlite3, sys, time
d, b = map(pathlib.Path, sys.argv[1:3])
for _ in range(10):
    owners = []
    for proc in pathlib.Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                target = os.readlink(fd)
                if target.startswith(str(d)) and target.endswith((".sqlite", ".sqlite-wal", ".db", ".db-wal")):
                    owners.append(int(proc.name))
        except Exception:
            continue
    if not owners:
        break
    time.sleep(1)
assert not owners, f"Surviving DB owners: {sorted(set(owners))}"

with closing(sqlite3.connect(f"file:{d}/state/openclaw.sqlite?mode=ro", uri=True)) as src:
    with closing(sqlite3.connect(b / "canonical-before.sqlite")) as dst:
        src.backup(dst)
with closing(sqlite3.connect(f"file:{b}/canonical-before.sqlite?mode=ro", uri=True)) as chk:
    assert chk.execute("pragma quick_check").fetchone()[0] == "ok"
rm_shm = b / "canonical-before.sqlite-shm"
if rm_shm.exists():
    rm_shm.unlink()
print("  STOPPED_BACKUP_SQLITE_OK")
PY

(cd "$B" && find . -maxdepth 1 -type f ! -name SHA256SUMS ! -name '*.sqlite-shm' -exec sha256sum {} \; | sort -k2 > SHA256SUMS && sha256sum -c --quiet SHA256SUMS)

PHASE=cutover
echo "== [2] Cập nhật systemd drop-in, /home/hung/bin/openclaw & /home/hung/bin/openclaw-healthcheck.sh sang Node v24.22.1 =="
cat << EOF_DROPIN > "$UNITS/$U.d/zzzzz-upgrade-99.conf.tmp"
# Managed 2026.9.33 runtime + Node v24.22.1 drop-in for $P. Retain all existing EnvironmentFile/OOM/other drop-ins.
[Unit]
Description=OpenClaw Gateway (profile: $P, v2026.9.33, node-v24.22.1)

[Service]
ExecStartPre=
ExecStartPre=${NEW_NODE} --test ${LIVE_GATES_DIR}/patch-openclaw-plugin-binding-decline-fallback.test.mjs
ExecStartPre=${NEW_NODE} ${LIVE_GATES_DIR}/verify-command-registry-98.mjs ${RT_933}/node_modules/openclaw/dist
ExecStart=
ExecStart=${NEW_NODE} --import ${LIVE_GATES_DIR}/patch-binding-loader-hook.mjs ${RT_933}/node_modules/openclaw/dist/index.js gateway --port $PORT
Environment=OPENCLAW_SERVICE_VERSION=2026.9.33
Environment=PATH=${RT_933}/bin:${NEW_NODE_DIR}:${RT_933}/node_modules/.bin:/usr/bin:/home/hung/.local/bin:/home/hung/.npm-global/bin:/home/hung/bin:/home/hung/.volta/bin:/home/hung/.asdf/shims:/home/hung/.bun/bin:/home/hung/.nvm/current/bin:/home/hung/.fnm/current/bin:/home/hung/.local/share/pnpm:/usr/local/bin:/bin
EOF_DROPIN
chmod 600 "$UNITS/$U.d/zzzzz-upgrade-99.conf.tmp"
mv "$UNITS/$U.d/zzzzz-upgrade-99.conf.tmp" "$UNITS/$U.d/zzzzz-upgrade-99.conf"

if [ "$P" = "hungreo" ]; then
  cat << EOF_FIN > "$UNITS/hungreo-finance-backup.service.d/zz-upgrade-99.conf.tmp"
[Service]
EnvironmentFile=-/home/hung/.openclaw-hungreo/gateway.systemd.env
ExecStart=
ExecStart=${NEW_NODE} ${RT_933}/node_modules/openclaw/dist/index.js finance backup --keep 30
EOF_FIN
  chmod 600 "$UNITS/hungreo-finance-backup.service.d/zz-upgrade-99.conf.tmp"
  mv "$UNITS/hungreo-finance-backup.service.d/zz-upgrade-99.conf.tmp" "$UNITS/hungreo-finance-backup.service.d/zz-upgrade-99.conf"
fi

cat << 'EOF_CLI' > /home/hung/bin/openclaw.tmp
#!/usr/bin/env bash
set -euo pipefail
explicit_profile=""
take_next=false
for argument in "$@"; do
  if $take_next; then explicit_profile="$argument"; take_next=false; continue; fi
  case "$argument" in
    --profile) take_next=true ;;
    --profile=*) explicit_profile="${argument#--profile=}" ;;
  esac
done
if $take_next; then echo 'Missing --profile value' >&2; exit 64; fi
selected="${explicit_profile:-${OPENCLAW_PROFILE:-}}"
state_profile=""
case "${OPENCLAW_STATE_DIR:-}" in
  /home/hung/.openclaw-hungreo|/home/hung/.openclaw-hungreo/) state_profile=hungreo ;;
  /home/hung/.openclaw-suckhoe|/home/hung/.openclaw-suckhoe/) state_profile=suckhoe ;;
esac
config_profile=""
case "${OPENCLAW_CONFIG_PATH:-}" in
  /home/hung/.openclaw-hungreo/openclaw.json) config_profile=hungreo ;;
  /home/hung/.openclaw-suckhoe/openclaw.json) config_profile=suckhoe ;;
esac
for hint in "$state_profile" "$config_profile"; do
  [[ -n "$hint" ]] || continue
  if [[ -n "$selected" && "$selected" != "$hint" ]]; then
    echo 'Conflicting profile/state/config selectors; refusing dispatch' >&2
    exit 64
  fi
  selected="$hint"
done
entry=/home/hung/openclaw-upgrade-20261003/runtime/node_modules/openclaw/dist/index.js
node_bin=/home/hung/openclaw-upgrade-20261003/node/bin/node
if [[ -x /home/hung/openclaw-node-24.22.1/node/bin/node ]]; then
  node_bin=/home/hung/openclaw-node-24.22.1/node/bin/node
fi
if [[ "$selected" == hungreo || "$selected" == suckhoe ]]; then
  dropin="/home/hung/.config/systemd/user/openclaw-gateway-${selected}.service.d/zzzzz-upgrade-99.conf"
  if grep -q 'openclaw-upgrade-20261026-934' "$dropin" 2>/dev/null; then
    entry=/home/hung/openclaw-upgrade-20261026-934/runtime/node_modules/openclaw/dist/index.js
  elif grep -q 'openclaw-upgrade-20261018-933' "$dropin" 2>/dev/null; then
    entry=/home/hung/openclaw-upgrade-20261018-933/runtime/node_modules/openclaw/dist/index.js
  else
    entry=/home/hung/openclaw-upgrade-20261008-99/runtime/node_modules/openclaw/dist/index.js
  fi
  if grep -q 'openclaw-node-24.22.1' "$dropin" 2>/dev/null && [[ -x /home/hung/openclaw-node-24.22.1/node/bin/node ]]; then
    node_bin=/home/hung/openclaw-node-24.22.1/node/bin/node
  elif grep -q 'openclaw-upgrade-20261003/node' "$dropin" 2>/dev/null; then
    node_bin=/home/hung/openclaw-upgrade-20261003/node/bin/node
  fi
fi
export PATH="$(dirname "$node_bin"):$PATH"
exec "$node_bin" "$entry" "$@"
EOF_CLI
chmod 700 /home/hung/bin/openclaw.tmp
bash -n /home/hung/bin/openclaw.tmp
mv /home/hung/bin/openclaw.tmp /home/hung/bin/openclaw

cat << 'EOF_HC' > /home/hung/bin/openclaw-healthcheck.sh.tmp
#!/usr/bin/env bash
set -euo pipefail
umask 077
export PATH="/home/hung/openclaw-node-24.22.1/node/bin:/home/hung/openclaw-upgrade-20261003/node/bin:$PATH"

LOG="${OPENCLAW_HEALTH_LOG:-$HOME/backups/openclaw/healthcheck.log}"
STATE_FILE="${OPENCLAW_HEALTH_STATE:-$HOME/backups/openclaw/healthcheck.state.json}"
CLI="${OPENCLAW_HEALTH_CLI:-$HOME/bin/openclaw}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$(dirname "$LOG")" "$(dirname "$STATE_FILE")"
exec 9>"${STATE_FILE}.run.lock"
flock -n 9 || exit 0

FAIL=0
FAILED_ARGS=()
now() { date '+%Y-%m-%dT%H:%M:%S%z'; }
log_line() { echo "$(now) $*" | tee -a "$LOG"; }

check_profile() {
  local profile="$1"
  local service="openclaw-gateway-$profile.service"
  local state="$HOME/.openclaw-$profile"
  local profile_fail=0

  if ! systemctl --user is-active --quiet "$service"; then
    log_line "[$profile] service down, restarting"
    systemctl --user restart "$service" || true
    profile_fail=1
    sleep 2
  fi

  local cli="$CLI"
  local dropin="$HOME/.config/systemd/user/openclaw-gateway-$profile.service.d/zzzzz-upgrade-99.conf"
  if grep -q 'openclaw-upgrade-20261026-934' "$dropin" 2>/dev/null && [[ -x "/home/hung/openclaw-upgrade-20261026-934/runtime/bin/openclaw" ]]; then
    cli="/home/hung/openclaw-upgrade-20261026-934/runtime/bin/openclaw"
  elif grep -q 'openclaw-upgrade-20261018-933' "$dropin" 2>/dev/null && [[ -x "/home/hung/openclaw-upgrade-20261018-933/runtime/bin/openclaw" ]]; then
    cli="/home/hung/openclaw-upgrade-20261018-933/runtime/bin/openclaw"
  elif [[ -f "$state/openclaw.json" ]] && grep -q '"lastTouchedVersion": "2026.9.9"' "$state/openclaw.json" && [[ -x "/home/hung/openclaw-upgrade-20261008-99/runtime/bin/openclaw" ]]; then
    cli="/home/hung/openclaw-upgrade-20261008-99/runtime/bin/openclaw"
  elif [[ -f "$state/openclaw.json" ]] && grep -q '"lastTouchedVersion": "2026.9.8"' "$state/openclaw.json" && [[ -x "/home/hung/openclaw-upgrade-20261003/runtime/bin/openclaw" ]]; then
    cli="/home/hung/openclaw-upgrade-20261003/runtime/bin/openclaw"
  fi
  if OPENCLAW_STATE_DIR="$state" OPENCLAW_CONFIG_PATH="$state/openclaw.json" \
    "$cli" channels status --probe >/dev/null 2>&1; then
    log_line "[$profile] probe ok"
  else
    log_line "[$profile] probe failed"
    profile_fail=1
  fi

  if [[ "$profile_fail" -ne 0 ]]; then
    FAIL=1
    FAILED_ARGS+=(--failed-profile "$profile")
  fi
}

check_profile hungreo
check_profile suckhoe

ALERT_STATUS=0
OPENCLAW_HEALTH_LOG="$LOG" OPENCLAW_HEALTH_STATE="$STATE_FILE" \
  python3 "$SCRIPT_DIR/openclaw_healthcheck.py" ${FAILED_ARGS[@]+"${FAILED_ARGS[@]}"} || ALERT_STATUS=$?
if [[ "$ALERT_STATUS" -ne 0 ]]; then
  exit "$ALERT_STATUS"
fi
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
EOF_HC
chmod 700 /home/hung/bin/openclaw-healthcheck.sh.tmp
bash -n /home/hung/bin/openclaw-healthcheck.sh.tmp
mv /home/hung/bin/openclaw-healthcheck.sh.tmp /home/hung/bin/openclaw-healthcheck.sh

systemctl --user daemon-reload

echo "== [3] Start $U và xác minh readyz + Node v24.22.1 =="
SINCE=$(date '+%F %T')
systemctl --user start "$U"

READY_OK=0
for i in $(seq 1 60); do
  if [ "$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/readyz" || true)" = "200" ]; then
    READY_OK=1
    echo "  $P readyz=200 sau $((i*3))s"
    break
  fi
  [ "$(systemctl --user is-active "$U")" != "failed" ]
  sleep 3
done
[ "$READY_OK" = "1" ]

J=$(journalctl --user -u "$U" --since "$SINCE" --no-pager)
grep -q "PLUGIN_BINDING_DECLINE_FALLBACK_IN_MEMORY" <<<"$J"
grep -q "lossless-claw" <<<"$J"
[ "$(grep -c 'readSessionTranscriptVisibleMessageDelta is required' <<<"$J" || true)" = "0" ]
[ "$(grep -cE 'SECRETS_(DEGRADED|OWNER_UNAVAILABLE)' <<<"$J" || true)" = "0" ]

NEW_PID=$(systemctl --user show "$U" -p MainPID --value)
EXE_PATH=$(readlink -f "/proc/$NEW_PID/exe")
echo "  pid=$NEW_PID exe=$EXE_PATH version=$("$EXE_PATH" -v)"
[ "$EXE_PATH" = "$NEW_NODE" ]

SERVING_VER=$(strings "/proc/$NEW_PID/environ" | grep '^OPENCLAW_SERVICE_VERSION=' | cut -d= -f2 || true)
[ "$SERVING_VER" = "2026.9.33" ]

CFG_SHA_AFTER=$(sha256sum "$D/openclaw.json" | awk '{print $1}')
[ "$CFG_SHA_BEFORE" = "$CFG_SHA_AFTER" ]

python3 - "$D" <<'PY'
from contextlib import closing
import pathlib, sqlite3, sys
d = pathlib.Path(sys.argv[1])
for rel in ("state/openclaw.sqlite", "lcm.db", "agents/main/agent/openclaw-agent.sqlite"):
    with closing(sqlite3.connect(f"file:{d / rel}?mode=ro", uri=True)) as db:
        assert db.execute("pragma quick_check").fetchone()[0] == "ok", f"quick_check failed on {rel}"
PY

OTHER_PID_AFTER=$(systemctl --user show "$OTHER_U" -p MainPID --value)
OTHER_RESTARTS_AFTER=$(systemctl --user show "$OTHER_U" -p NRestarts --value)
[ "$OTHER_PID_BEFORE" = "$OTHER_PID_AFTER" ]
[ "$OTHER_RESTARTS_BEFORE" = "$OTHER_RESTARTS_AFTER" ]

PHASE=done
if [ "$HC_WAS" = "active" ]; then
  systemctl --user start openclaw-healthcheck.timer
fi
echo "NODE_24221_CUTOVER_OK profile=$P pid=$NEW_PID node=$("$EXE_PATH" -v) core=$SERVING_VER backup=$B"
