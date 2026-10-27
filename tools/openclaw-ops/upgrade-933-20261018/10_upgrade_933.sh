#!/usr/bin/env bash
# Upgrade suckhoe or hungreo from OpenClaw 2026.9.9 -> 2026.9.33 (extended-stable).
# Keeps lossless-claw@1.1.1 and all model/auth/fallback/channel settings unchanged.
set -Eeuo pipefail
umask 077
export TZ=Asia/Ho_Chi_Minh
export PATH=/home/hung/openclaw-upgrade-20261003/node/bin:/usr/bin:/bin
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

P=${1:?Usage: 10_upgrade_933.sh <suckhoe|hungreo>}
case "$P" in
  suckhoe) PORT=18795; OTHER=hungreo ;;
  hungreo) PORT=18789; OTHER=suckhoe ;;
  *) echo "ABORT: invalid profile $P"; exit 1 ;;
esac

ROOT=/home/hung/openclaw-upgrade-20261018-933
OPS="$ROOT/ops"
D="/home/hung/.openclaw-$P"
U="openclaw-gateway-$P.service"
OTHER_U="openclaw-gateway-$OTHER.service"
UNITS="/home/hung/.config/systemd/user"
TS=$(date +%Y%m%d-%H%M%S)
B="/home/hung/backups/openclaw-$P-pre933-$TS"
PHASE=precheck

on_err() {
  local line=$1
  echo "FAILED at line $line (phase=$PHASE, profile=$P)"
  if [ "$PHASE" = "precheck" ]; then
    echo "No changes made; gateway $P is still running."
  elif [ "$PHASE" = "stop_backup" ]; then
    echo "Plugin/wiring not modified yet -> starting $U and healthcheck timer back up."
    systemctl --user start "$U" || true
    [ "${HC_WAS:-active}" = "active" ] && systemctl --user start openclaw-healthcheck.timer || true
  else
    echo "Rolling back $P automatically from $B..."
    bash "$OPS/99_rollback_933.sh" "$P" "$B" || true
  fi
  exit 1
}
trap 'on_err $LINENO' ERR

echo "== [0] Precheck for $P ($TS) =="
[ "$(hostname)" = "srv1367812" ]
[ "$(systemctl --user is-active "$U")" = "active" ] || { echo "ABORT: $U not active"; exit 1; }
[ "$(systemctl --user is-active "$OTHER_U")" = "active" ] || { echo "ABORT: peer $OTHER_U not active"; exit 1; }
! systemctl --user is-active --quiet openclaw-healthcheck.service || { echo "ABORT: healthcheck.service currently running"; exit 1; }

OTHER_PID_BEFORE=$(systemctl --user show "$OTHER_U" -p MainPID --value)
OTHER_RESTARTS_BEFORE=$(systemctl --user show "$OTHER_U" -p NRestarts --value)

FREE_G=$(df -BG --output=avail / | tail -1 | tr -dc 0-9)
[ "$FREE_G" -ge 5 ] || { echo "ABORT: disk free ${FREE_G}G < 5G"; exit 1; }

node --test /home/hung/openclaw-upgrade-20261003/live-gates/patch-openclaw-plugin-binding-decline-fallback.test.mjs >/dev/null
node /home/hung/openclaw-upgrade-20261003/live-gates/verify-command-registry-98.mjs "$ROOT/runtime/node_modules/openclaw/dist" >/dev/null

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
print("PRECHECK_SQLITE_AND_IDLE_OK")
PY

oc933() {
  (
    set -a
    . "$D/gateway.systemd.env"
    set +a
    export OPENCLAW_STATE_DIR="$D"
    export OPENCLAW_CONFIG_PATH="$D/openclaw.json"
    export OPENCLAW_PROFILE="$P"
    export NODE_OPTIONS="--max-old-space-size=512"
    export npm_config_cache="$ROOT/npm-cache"
    export PATH="$ROOT/runtime/bin:/home/hung/openclaw-upgrade-20261003/node/bin:/usr/bin:/bin"
    cd "$D/workspace"
    timeout 300 "$ROOT/runtime/bin/openclaw" --profile "$P" "$@" < /dev/null
  )
}

DRY=$(oc933 plugins update "@openclaw/codex@2026.9.33" --dry-run 2>&1 | grep -vE 'sk-|eyJ' || true)
echo "  dry-run: $(grep -i 'Would update codex' <<<"$DRY" || true)"
grep -q "Would update codex: 2026.9.9 -> 2026.9.33" <<<"$DRY"

PHASE=stop_backup
echo "== [1] Stop healthcheck timer + stop $U & Backup to $B =="
mkdir -p -m 700 "$B"
HC_WAS=$(systemctl --user is-active openclaw-healthcheck.timer || true)
echo "$HC_WAS" > "$B/healthcheck_timer_state"

cp -p "$UNITS/$U.d/zzzzz-upgrade-99.conf" "$B/zzzzz-upgrade-99.conf"
if [ "$P" = "hungreo" ] && [ -f "$UNITS/hungreo-finance-backup.service.d/zz-upgrade-99.conf" ]; then
  cp -p "$UNITS/hungreo-finance-backup.service.d/zz-upgrade-99.conf" "$B/zz-upgrade-99.conf"
fi
cp -p /home/hung/bin/openclaw "$B/openclaw-cli"
cp -p /home/hung/bin/openclaw-healthcheck.sh "$B/openclaw-healthcheck.sh"

systemctl --user stop openclaw-healthcheck.timer openclaw-healthcheck.service || true
systemctl --user stop "$U"

for _ in $(seq 1 15); do
  if [ "$(systemctl --user show "$U" -p MainPID --value)" = "0" ] && ! ss -ltn "sport = :$PORT" | grep -q LISTEN; then
    break
  fi
  sleep 1
done
[ "$(systemctl --user show "$U" -p MainPID --value)" = "0" ]
! ss -ltn "sport = :$PORT" | grep -q LISTEN

python3 - "$D" "$B" <<'PY'
from contextlib import closing
import json, os, pathlib, shutil, sqlite3, sys, time
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

shutil.copy2(d / "openclaw.json", b / "openclaw.json")
with closing(sqlite3.connect(f"file:{d}/state/openclaw.sqlite?mode=ro", uri=True)) as src:
    row = src.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()
    assert row
    records = json.loads(row[0])["index"]["installRecords"]
    (b / "peer-records-before.json").write_text(json.dumps(records, indent=2))
    with closing(sqlite3.connect(b / "canonical-before.sqlite")) as dst:
        src.backup(dst)
with closing(sqlite3.connect(f"file:{b}/canonical-before.sqlite?mode=ro", uri=True)) as chk:
    assert chk.execute("pragma quick_check").fetchone()[0] == "ok"
print("STOPPED_BACKUP_SQLITE_OK")
PY

(cd "$B" && find . -maxdepth 1 -type f ! -name SHA256SUMS -exec sha256sum {} \; | sort -k2 > SHA256SUMS && sha256sum -c --quiet SHA256SUMS)

PHASE=upgrade
echo "== [2] Update @openclaw/codex@2026.9.33 & Relink Peer Dependencies =="
oc933 plugins update "@openclaw/codex@2026.9.33" > "$B/codex-933-update.log" 2>&1

node --input-type=module - "$D" "$B/peer-records-before.json" <<'MJS'
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const [stateDir, recordsPath] = process.argv.slice(2);
const root933 = "/home/hung/openclaw-upgrade-20261018-933/runtime/node_modules/openclaw";
const { acquireGatewayLock } = await import(pathToFileURL(path.join(root933, "dist/gateway-lock-FzObkmzB.mjs")));
const { s: repair, r: audit } = await import(pathToFileURL(path.join(root933, "dist/plugin-peer-link-JG-fspRW.mjs")));
const records = JSON.parse(fs.readFileSync(recordsPath, "utf8"));
const env = { ...process.env, OPENCLAW_STATE_DIR: stateDir, OPENCLAW_CONFIG_PATH: path.join(stateDir, "openclaw.json") };
const lock = await acquireGatewayLock({ env, role: "sqlite-maintenance", timeoutMs: 5000, pollIntervalMs: 50, allowInTests: true });
if (!lock) throw new Error("Maintenance lock unavailable");
try {
  await lock.run(async () => {
    const results = [];
    for (const [id, r] of Object.entries(records)) {
      if (id === "codex" || !r.installPath || !r.installPath.includes("/npm/projects/")) continue;
      const project = path.resolve(r.installPath, "../../..");
      const warnings = [];
      const res = await repair({
        npmRoot: project,
        beforePersistentApply: () => lock.assertCurrent(),
        logger: { info() {}, warn: m => warnings.push(m) },
        onPackageReadError: e => warnings.push(String(e)),
      });
      if (warnings.length || await audit({ packageDir: r.installPath, packageName: id })) {
        throw new Error("Peer repair failed for " + id + ": " + warnings.join("; "));
      }
      results.push({ id, repaired: res.repaired, checked: res.checked });
    }
    console.log("PEER_REPAIR_933_OK", JSON.stringify(results));
  });
} finally {
  await lock.release();
}
MJS

python3 - "$D" "$B" <<'PY'
from contextlib import closing
import json, pathlib, sqlite3, sys
d, b = map(pathlib.Path, sys.argv[1:3])
before = json.loads((b / "openclaw.json").read_text())
after = json.loads((d / "openclaw.json").read_text())
changed = [k for k in sorted(set(before) | set(after)) if before.get(k) != after.get(k)]
assert set(changed) <= {"meta"}, f"Unexpected config changes: {changed}"
with closing(sqlite3.connect(f"file:{d}/state/openclaw.sqlite?mode=ro", uri=True)) as db:
    row = db.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()
    idx = json.loads(row[0])["index"]["installRecords"]
    assert idx["codex"]["version"] == "2026.9.33", idx["codex"]
    assert idx["lossless-claw"]["version"] == "1.1.1", idx["lossless-claw"]
    assert db.execute("pragma quick_check").fetchone()[0] == "ok"
print("INDEX_AND_CONFIG_VERIFIED_933_OK")
PY

echo "== [3] Update systemd drop-in, /home/hung/bin/openclaw, and healthcheck =="
cat << EOF_DROPIN > "$UNITS/$U.d/zzzzz-upgrade-99.conf.tmp"
# Managed 2026.9.33 runtime drop-in for $P. Retain all existing EnvironmentFile/OOM/other drop-ins.
[Unit]
Description=OpenClaw Gateway (profile: $P, v2026.9.33)

[Service]
ExecStartPre=
ExecStartPre=/home/hung/openclaw-upgrade-20261003/node/bin/node --test /home/hung/openclaw-upgrade-20261003/live-gates/patch-openclaw-plugin-binding-decline-fallback.test.mjs
ExecStartPre=/home/hung/openclaw-upgrade-20261003/node/bin/node /home/hung/openclaw-upgrade-20261003/live-gates/verify-command-registry-98.mjs /home/hung/openclaw-upgrade-20261018-933/runtime/node_modules/openclaw/dist
ExecStart=
ExecStart=/home/hung/openclaw-upgrade-20261003/node/bin/node --import /home/hung/openclaw-upgrade-20261003/live-gates/patch-binding-loader-hook.mjs /home/hung/openclaw-upgrade-20261018-933/runtime/node_modules/openclaw/dist/index.js gateway --port $PORT
Environment=OPENCLAW_SERVICE_VERSION=2026.9.33
Environment=PATH=/home/hung/openclaw-upgrade-20261018-933/runtime/bin:/home/hung/openclaw-upgrade-20261003/node/bin:/home/hung/openclaw-upgrade-20261018-933/runtime/node_modules/.bin:/usr/bin:/home/hung/.local/bin:/home/hung/.npm-global/bin:/home/hung/bin:/home/hung/.volta/bin:/home/hung/.asdf/shims:/home/hung/.bun/bin:/home/hung/.nvm/current/bin:/home/hung/.fnm/current/bin:/home/hung/.local/share/pnpm:/usr/local/bin:/bin
EOF_DROPIN
chmod 600 "$UNITS/$U.d/zzzzz-upgrade-99.conf.tmp"
mv "$UNITS/$U.d/zzzzz-upgrade-99.conf.tmp" "$UNITS/$U.d/zzzzz-upgrade-99.conf"

if [ "$P" = "hungreo" ]; then
  cat << 'EOF_FIN' > "$UNITS/hungreo-finance-backup.service.d/zz-upgrade-99.conf.tmp"
[Service]
EnvironmentFile=-/home/hung/.openclaw-hungreo/gateway.systemd.env
ExecStart=
ExecStart=/home/hung/openclaw-upgrade-20261003/node/bin/node /home/hung/openclaw-upgrade-20261018-933/runtime/node_modules/openclaw/dist/index.js finance backup --keep 30
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
if [[ "$selected" == hungreo || "$selected" == suckhoe ]]; then
  if grep -q 'openclaw-upgrade-20261018-933' "/home/hung/.config/systemd/user/openclaw-gateway-${selected}.service.d/zzzzz-upgrade-99.conf" 2>/dev/null; then
    entry=/home/hung/openclaw-upgrade-20261018-933/runtime/node_modules/openclaw/dist/index.js
  else
    entry=/home/hung/openclaw-upgrade-20261008-99/runtime/node_modules/openclaw/dist/index.js
  fi
fi
exec /home/hung/openclaw-upgrade-20261003/node/bin/node "$entry" "$@"
EOF_CLI
chmod 700 /home/hung/bin/openclaw.tmp
bash -n /home/hung/bin/openclaw.tmp
mv /home/hung/bin/openclaw.tmp /home/hung/bin/openclaw

cat << 'EOF_HC' > /home/hung/bin/openclaw-healthcheck.sh.tmp
#!/usr/bin/env bash
set -euo pipefail
umask 077

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
  if grep -q 'openclaw-upgrade-20261018-933' "$HOME/.config/systemd/user/openclaw-gateway-$profile.service.d/zzzzz-upgrade-99.conf" 2>/dev/null && [[ -x "/home/hung/openclaw-upgrade-20261018-933/runtime/bin/openclaw" ]]; then
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

echo "== [4] Start $U and wait for readyz =="
SINCE=$(date '+%F %T')
systemctl --user start "$U"

READY_OK=0
for i in $(seq 1 60); do
  if [ "$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/readyz" || true)" = "200" ]; then
    READY_OK=1
    echo "  $P readyz=200 after $((i*3))s"
    break
  fi
  [ "$(systemctl --user is-active "$U")" != "failed" ]
  sleep 3
done
[ "$READY_OK" = "1" ]

J=$(journalctl --user -u "$U" --since "$SINCE" --no-pager)
grep -q "PLUGIN_BINDING_DECLINE_FALLBACK_IN_MEMORY" <<<"$J"

NEW_PID=$(systemctl --user show "$U" -p MainPID --value)
SERVING_VER=$(strings "/proc/$NEW_PID/environ" | grep '^OPENCLAW_SERVICE_VERSION=' | cut -d= -f2)
[ "$SERVING_VER" = "2026.9.33" ]

python3 - "$D" <<'PY'
from contextlib import closing
import pathlib, sqlite3, sys
d = pathlib.Path(sys.argv[1])
with closing(sqlite3.connect(f"file:{d}/state/openclaw.sqlite?mode=ro", uri=True)) as db:
    assert db.execute("pragma quick_check").fetchone()[0] == "ok"
with closing(sqlite3.connect(f"file:{d}/lcm.db?mode=ro", uri=True)) as lcm:
    assert lcm.execute("pragma quick_check").fetchone()[0] == "ok"
PY

OTHER_PID_AFTER=$(systemctl --user show "$OTHER_U" -p MainPID --value)
OTHER_RESTARTS_AFTER=$(systemctl --user show "$OTHER_U" -p NRestarts --value)
[ "$OTHER_PID_BEFORE" = "$OTHER_PID_AFTER" ]
[ "$OTHER_RESTARTS_BEFORE" = "$OTHER_RESTARTS_AFTER" ]

PHASE=done
[ "$HC_WAS" = "active" ] && systemctl --user start openclaw-healthcheck.timer
echo "UPGRADE_933_OK profile=$P pid=$NEW_PID version=$SERVING_VER backup=$B"
