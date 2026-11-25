#!/usr/bin/env bash
# 40_upgrade_934.sh — Nâng cấp suckhoe hoặc hungreo từ OpenClaw 2026.9.33 -> 2026.9.34 (extended-stable)
# trên nền Node.js v24.22.1 + lossless-claw@1.2.0.
# Bao gồm:
# - Precheck idle + SQLite quick_check + Live-Gates 9.34 + dry-run toàn bộ plugin official (@openclaw/*@2026.9.34)
# - Stop-first + Full SQLite backup (state/openclaw.sqlite + openclaw-agent.sqlite + lcm.db) + npm-projects-before.tgz + SHA256SUMS
# - Update toàn bộ plugin official lên 2026.9.34 + Relink cả 2 tầng node_modules/openclaw (outer & inner) + Audit peer links
# - Hỗ trợ chạy song song (suckhoe ở 9.34, hungreo ở 9.33 hoặc cả 2 ở 9.34) trong /home/hung/bin/openclaw & healthcheck
# - Tự động gọi 98_rollback_934.sh nếu bất kỳ gate nào FAIL sau khi chạm vào cấu hình/plugin.
set -Eeuo pipefail
umask 077
export TZ=Asia/Ho_Chi_Minh
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

P=${1:?Usage: 40_upgrade_934.sh <suckhoe|hungreo>}
case "$P" in
  suckhoe)
    PORT=18795
    OTHER=hungreo
    PLUGINS=(
      "codex:@openclaw/codex@2026.9.34"
      "brave:@openclaw/brave-plugin@2026.9.34"
      "deepseek:@openclaw/deepseek-provider@2026.9.34"
    )
    ;;
  hungreo)
    PORT=18789
    OTHER=suckhoe
    PLUGINS=(
      "codex:@openclaw/codex@2026.9.34"
      "brave:@openclaw/brave-plugin@2026.9.34"
      "deepseek:@openclaw/deepseek-provider@2026.9.34"
      "parallel:@openclaw/parallel-plugin@2026.9.34"
      "typesafe:@openclaw/typesafe@2026.9.34"
    )
    ;;
  *)
    echo "ABORT: invalid profile $P (must be suckhoe or hungreo)"
    exit 1
    ;;
esac

exec 9>"/tmp/openclaw-934-apply.lock"
flock -n 9 || { echo "ABORT: một tiến trình 40_upgrade_934.sh khác đang chạy"; exit 1; }

NODE_DIR="/home/hung/openclaw-node-24.22.1/node/bin"
NODE_BIN="${NODE_DIR}/node"
export PATH="${NODE_DIR}:/usr/bin:/bin"

ROOT_934="/home/hung/openclaw-upgrade-20261026-934"
RT_934="${ROOT_934}/runtime"
OC_934="${RT_934}/node_modules/openclaw"
RT_933="/home/hung/openclaw-upgrade-20261018-933/runtime"
LIVE_GATES_DIR="/home/hung/openclaw-upgrade-20261003/live-gates"
OPS_DIR="/home/hung/openclaw-node-24.22.1/ops"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
ROLLBACK_SH="$OPS_DIR/98_rollback_934.sh"
[ -f "$ROLLBACK_SH" ] || [ -z "$SCRIPT_DIR" ] || ROLLBACK_SH="$SCRIPT_DIR/98_rollback_934.sh"

D="/home/hung/.openclaw-$P"
U="openclaw-gateway-$P.service"
OTHER_U="openclaw-gateway-$OTHER.service"
UNITS="/home/hung/.config/systemd/user"
TS=$(date +%Y%m%d-%H%M%S)
B="/home/hung/backups/openclaw-$P-pre934-$TS"
PHASE=precheck

on_err() {
  [ "${BASH_SUBSHELL:-0}" -eq 0 ] || exit 1
  local line=$1
  echo "FAILED at line $line (phase=$PHASE, profile=$P)"
  if [ "$PHASE" = "precheck" ]; then
    echo "Chưa thay đổi gì; $U vẫn đang chạy."
  elif [ "$PHASE" = "stop_backup" ]; then
    echo "Chưa sửa plugin/drop-in -> bật lại $U và healthcheck timer."
    systemctl --user start "$U" || true
    if [ "${HC_WAS:-active}" = "active" ]; then
      systemctl --user start openclaw-healthcheck.timer || true
    fi
  else
    echo "Đang tự động rollback $P về 2026.9.33 từ $B..."
    bash "$ROLLBACK_SH" "$P" "$B" || true
  fi
  exit 1
}
trap 'on_err $LINENO' ERR
trap 'on_err $LINENO' INT TERM HUP

echo "== [0] Precheck cho $P ($TS) =="
[ "$(hostname)" = "srv1367812" ]
[ -x "$NODE_BIN" ] || { echo "ABORT: thiếu $NODE_BIN"; exit 1; }
[ "$("$NODE_BIN" -v)" = "v24.22.1" ] || { echo "ABORT: $NODE_BIN version != v24.22.1"; exit 1; }
[ -f "$OC_934/package.json" ] && [ "$(jq -r .version "$OC_934/package.json")" = "2026.9.34" ] || { echo "ABORT: thiếu openclaw@2026.9.34 tại $OC_934"; exit 1; }
[ -f "$ROLLBACK_SH" ] || { echo "ABORT: thiếu $ROLLBACK_SH"; exit 1; }
[ "$(systemctl --user is-active "$U")" = "active" ] || { echo "ABORT: $U không active"; exit 1; }
[ "$(systemctl --user is-active "$OTHER_U")" = "active" ] || { echo "ABORT: peer $OTHER_U không active"; exit 1; }
if systemctl --user is-active --quiet openclaw-healthcheck.service; then
  echo "ABORT: openclaw-healthcheck.service đang chạy"
  exit 1
fi

OTHER_PID_BEFORE=$(systemctl --user show "$OTHER_U" -p MainPID --value)
OTHER_RESTARTS_BEFORE=$(systemctl --user show "$OTHER_U" -p NRestarts --value)

FREE_G=$(df -BG --output=avail /home/hung | tail -1 | tr -dc 0-9)
[ "$FREE_G" -ge 5 ] || { echo "ABORT: disk free ${FREE_G}G < 5G"; exit 1; }

"$NODE_BIN" --test "$LIVE_GATES_DIR/patch-openclaw-plugin-binding-decline-fallback.test.mjs" >/dev/null
"$NODE_BIN" "$LIVE_GATES_DIR/verify-command-registry-98.mjs" "$OC_934/dist" >/dev/null

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
    assert adb.execute("pragma user_version").fetchone()[0] == 24, "agent DB user_version != 24"
print("  PRECHECK_SQLITE_AND_IDLE_OK")
PY

oc934() {
  (
    for v in $(compgen -v OPENCLAW_ 2>/dev/null || true); do unset "$v"; done
    unset TELEGRAM_BOT_TOKEN
    set -a
    . "$D/gateway.systemd.env"
    set +a
    export OPENCLAW_STATE_DIR="$D"
    export OPENCLAW_CONFIG_PATH="$D/openclaw.json"
    export OPENCLAW_PROFILE="$P"
    export NODE_OPTIONS="--max-old-space-size=512"
    export npm_config_cache="$ROOT_934/npm-cache"
    export PATH="$RT_934/bin:$NODE_DIR:/usr/bin:/bin"
    cd "$D/workspace"
    timeout 300 "$RT_934/bin/openclaw" --profile "$P" "$@" < /dev/null
  )
}

for entry in "${PLUGINS[@]}"; do
  ID=${entry%%:*}
  SPEC=${entry#*:}
  DRY=$(oc934 plugins update "$SPEC" --dry-run 2>&1 | grep -vE 'sk-|eyJ' || true)
  echo "  dry-run $ID: $(grep -i 'Would update' <<<"$DRY" | head -1 || true)"
  grep -q "2026.9.33 -> 2026.9.34" <<<"$DRY" || { echo "ABORT: dry-run $SPEC không báo 2026.9.33 -> 2026.9.34"; echo "$DRY" | tail -15; exit 1; }
done

PHASE=stop_backup
echo "== [1] Stop healthcheck timer + stop $U & Full Backup vào $B =="
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

for _ in $(seq 1 20); do
  if [ "$(systemctl --user show "$U" -p MainPID --value)" = "0" ]; then
    if ! ss -ltn "sport = :$PORT" | grep -q LISTEN; then
      break
    fi
  fi
  sleep 1
done
[ "$(systemctl --user show "$U" -p MainPID --value)" = "0" ] || { echo "ABORT: $U MainPID != 0"; false; }
if ss -ltn "sport = :$PORT" | grep -q LISTEN; then
  echo "ABORT: cổng $PORT vẫn đang LISTEN"
  false
fi

python3 - "$D" "$B" <<'PY'
from contextlib import closing
import json, os, pathlib, shutil, sqlite3, sys, time
d, b = map(pathlib.Path, sys.argv[1:3])
for _ in range(12):
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
with closing(sqlite3.connect(f"file:{d}/agents/main/agent/openclaw-agent.sqlite?mode=ro", uri=True)) as asrc:
    with closing(sqlite3.connect(b / "agent-before.sqlite")) as adst:
        asrc.backup(adst)
with closing(sqlite3.connect(f"file:{d}/lcm.db?mode=ro", uri=True)) as lsrc:
    with closing(sqlite3.connect(b / "lcm-before.db")) as ldst:
        lsrc.backup(ldst)

for fname in ("canonical-before.sqlite", "agent-before.sqlite", "lcm-before.db"):
    with closing(sqlite3.connect(f"file:{b / fname}?mode=ro", uri=True)) as chk:
        assert chk.execute("pragma quick_check").fetchone()[0] == "ok", f"{fname} quick_check failed"
for shm in b.glob("*-shm"):
    shm.unlink()
print("  STOPPED_FULL_BACKUP_SQLITE_OK")
PY

tar -czf "$B/npm-projects-before.tgz" -C "$D/npm" projects
(cd "$B" && find . -maxdepth 1 -type f ! -name SHA256SUMS ! -name '*-shm' -exec sha256sum {} \; | sort -k2 > SHA256SUMS && sha256sum -c --quiet SHA256SUMS)

PHASE=upgrade
echo "== [2] Cập nhật toàn bộ plugin official lên 2026.9.34 & Relink Peer Dependencies 2 tầng =="
for entry in "${PLUGINS[@]}"; do
  ID=${entry%%:*}
  SPEC=${entry#*:}
  echo "  -> updating $ID ($SPEC)..."
  oc934 plugins update "$SPEC" > "$B/${ID}-934-update.log" 2>&1 || {
    grep -vE 'sk-|eyJ' "$B/${ID}-934-update.log" | tail -15 || true
    echo "ABORT: plugins update $SPEC lỗi"
    false
  }
done

python3 - "$D" "$OC_934" <<'PY'
import json, os, pathlib, shutil, sqlite3, sys
root = pathlib.Path(sys.argv[1])
target_rt = sys.argv[2]
c = sqlite3.connect(f"file:{root}/state/openclaw.sqlite?mode=ro", uri=True)
idx = json.loads(c.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()[0])["index"]["installRecords"]
c.close()

def force_link(peer: pathlib.Path):
    assert str(peer).startswith(str(root) + "/npm/projects/"), f"Unsafe peer path: {peer}"
    peer.parent.mkdir(parents=True, exist_ok=True)
    if peer.is_symlink() or peer.is_file():
        peer.unlink()
    elif peer.is_dir():
        shutil.rmtree(peer)
    os.symlink(target_rt, str(peer))

all_links = 0
for p in (root / "npm/projects").rglob("openclaw"):
    if p.is_symlink():
        force_link(p)
        all_links += 1

relinked = []
for pid, rec in idx.items():
    ipath = rec.get("installPath") or ""
    if not ipath.startswith(str(root)) or "/npm/projects/" not in ipath:
        continue
    pkg_dir = pathlib.Path(ipath)
    assert (pkg_dir / "package.json").is_file(), f"Missing package.json in {pkg_dir}"
    nm = pkg_dir.parent
    if nm.name.startswith("@"):
        nm = nm.parent
    force_link(nm / "openclaw")
    force_link(pkg_dir / "node_modules/openclaw")
    relinked.append(pid)
print(f"  PEER_RELINK_2TIER_934_OK (rglob_links={all_links}, plugins={relinked})")
PY

"$NODE_BIN" --input-type=module - "$D" "$OC_934" <<'MJS'
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { DatabaseSync } from "node:sqlite";

const [stateDir, oc934] = process.argv.slice(2);
const peerLinkFiles = fs.readdirSync(path.join(oc934, "dist")).filter(f => f.startsWith("plugin-peer-link-") && f.endsWith(".mjs"));
if (peerLinkFiles.length !== 1) throw new Error("Expected 1 plugin-peer-link module, found: " + peerLinkFiles.join(","));
const { r: audit } = await import(pathToFileURL(path.join(oc934, "dist", peerLinkFiles[0])));

const db = new DatabaseSync(path.join(stateDir, "state/openclaw.sqlite"), { open: true, readOnly: true });
const row = db.prepare("select value_json from config_machine_state where state_key='plugins.installedIndex'").get();
db.close();
const records = JSON.parse(row.value_json).index.installRecords;
for (const [id, r] of Object.entries(records)) {
  if (!r.installPath || !r.installPath.includes("/npm/projects/")) continue;
  const issue = await audit({ packageDir: r.installPath, packageName: id });
  if (issue) throw new Error(`Peer audit failed for ${id}: ${JSON.stringify(issue)}`);
}
console.log("  PEER_AUDIT_934_OK");
MJS

python3 - "$D" "$B" "${PLUGINS[@]}" <<'PY'
from contextlib import closing
import json, pathlib, sqlite3, sys
d, b = map(pathlib.Path, sys.argv[1:3])
plugin_entries = sys.argv[3:]
before = json.loads((b / "openclaw.json").read_text())
after = json.loads((d / "openclaw.json").read_text())
changed = [k for k in sorted(set(before) | set(after)) if before.get(k) != after.get(k)]
assert set(changed) <= {"meta"}, f"Unexpected config changes: {changed}"
assert before["agents"]["defaults"]["model"] == after["agents"]["defaults"]["model"], "model config drifted!"
assert before["plugins"]["slots"] == after["plugins"]["slots"], "plugin slots drifted!"
with closing(sqlite3.connect(f"file:{d}/state/openclaw.sqlite?mode=ro", uri=True)) as db:
    row = db.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()
    idx = json.loads(row[0])["index"]["installRecords"]
    for item in plugin_entries:
        pid, spec = item.split(":", 1)
        rec = idx.get(pid)
        assert rec and rec.get("version") == "2026.9.34", f"{pid} record={rec}"
        pkg_ver = json.loads((pathlib.Path(rec["installPath"]) / "package.json").read_text())["version"]
        assert pkg_ver == "2026.9.34", f"{pid} package.json version={pkg_ver}"
    assert idx["lossless-claw"]["version"] == "1.2.0", idx["lossless-claw"]
    assert db.execute("pragma quick_check").fetchone()[0] == "ok"
print("  INDEX_AND_CONFIG_VERIFIED_934_OK")
PY

echo "== [3] Cập nhật systemd drop-in, /home/hung/bin/openclaw & /home/hung/bin/openclaw-healthcheck.sh =="
cat << EOF_DROPIN > "$UNITS/$U.d/zzzzz-upgrade-99.conf.tmp"
# Managed 2026.9.34 + Node v24.22.1 runtime drop-in for $P. Retain all existing EnvironmentFile/OOM/other drop-ins.
[Unit]
Description=OpenClaw Gateway (profile: $P, v2026.9.34, node v24.22.1)

[Service]
KillMode=mixed
TimeoutStopSec=340
ExecStartPre=
ExecStartPre=/home/hung/openclaw-node-24.22.1/node/bin/node --test /home/hung/openclaw-upgrade-20261003/live-gates/patch-openclaw-plugin-binding-decline-fallback.test.mjs
ExecStartPre=/home/hung/openclaw-node-24.22.1/node/bin/node /home/hung/openclaw-upgrade-20261003/live-gates/verify-command-registry-98.mjs /home/hung/openclaw-upgrade-20261026-934/runtime/node_modules/openclaw/dist
ExecStart=
ExecStart=/home/hung/openclaw-node-24.22.1/node/bin/node --import /home/hung/openclaw-upgrade-20261003/live-gates/patch-binding-loader-hook.mjs /home/hung/openclaw-upgrade-20261026-934/runtime/node_modules/openclaw/dist/index.js gateway --port $PORT
Environment=OPENCLAW_SERVICE_VERSION=2026.9.34
Environment=PATH=/home/hung/openclaw-upgrade-20261026-934/runtime/bin:/home/hung/openclaw-node-24.22.1/node/bin:/home/hung/openclaw-upgrade-20261026-934/runtime/node_modules/.bin:/usr/bin:/home/hung/.local/bin:/home/hung/.npm-global/bin:/home/hung/bin:/home/hung/.bun/bin:/home/hung/.local/share/pnpm:/usr/local/bin:/bin
EOF_DROPIN
chmod 600 "$UNITS/$U.d/zzzzz-upgrade-99.conf.tmp"
mv "$UNITS/$U.d/zzzzz-upgrade-99.conf.tmp" "$UNITS/$U.d/zzzzz-upgrade-99.conf"

if [ "$P" = "hungreo" ] && [ -d "$UNITS/hungreo-finance-backup.service.d" ]; then
  cat << 'EOF_FIN' > "$UNITS/hungreo-finance-backup.service.d/zz-upgrade-99.conf.tmp"
[Service]
EnvironmentFile=-/home/hung/.openclaw-hungreo/gateway.systemd.env
ExecStart=
ExecStart=/home/hung/openclaw-node-24.22.1/node/bin/node /home/hung/openclaw-upgrade-20261026-934/runtime/node_modules/openclaw/dist/index.js finance backup --keep 30
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
entry=/home/hung/openclaw-upgrade-20261018-933/runtime/node_modules/openclaw/dist/index.js
node_bin=/home/hung/openclaw-node-24.22.1/node/bin/node
if [[ "$selected" == hungreo || "$selected" == suckhoe ]]; then
  dropin="/home/hung/.config/systemd/user/openclaw-gateway-${selected}.service.d/zzzzz-upgrade-99.conf"
  if grep -q 'openclaw-upgrade-20261026-934' "$dropin" 2>/dev/null; then
    entry=/home/hung/openclaw-upgrade-20261026-934/runtime/node_modules/openclaw/dist/index.js
  elif grep -q 'openclaw-upgrade-20261018-933' "$dropin" 2>/dev/null; then
    entry=/home/hung/openclaw-upgrade-20261018-933/runtime/node_modules/openclaw/dist/index.js
  else
    entry=/home/hung/openclaw-upgrade-20261008-99/runtime/node_modules/openclaw/dist/index.js
  fi
  if ! grep -q 'openclaw-node-24.22.1' "$dropin" 2>/dev/null; then
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

echo "== [4] Start $U và xác minh readyz + OpenClaw 2026.9.34 + Node v24.22.1 =="
SINCE=$(date '+%F %T')
systemctl --user start "$U"

READY_OK=0
for i in $(seq 1 60); do
  if [ "$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/readyz" || true)" = "200" ]; then
    READY_OK=1
    echo "  $P readyz=200 sau $((i*3))s"
    break
  fi
  [ "$(systemctl --user is-active "$U")" != "failed" ] || { echo "ABORT: $U failed"; false; }
  sleep 3
done
[ "$READY_OK" = "1" ] || { echo "ABORT: $P không ready sau 180s"; false; }

J=$(journalctl --user -u "$U" --since "$SINCE" --no-pager)
grep -q "PLUGIN_BINDING_DECLINE_FALLBACK_IN_MEMORY" <<<"$J" || { echo "ABORT: thiếu loader hook marker"; false; }
grep -q "lossless-claw" <<<"$J" || { echo "ABORT: thiếu lossless-claw trong startup log"; false; }
if grep -qE "SECRETS_(DEGRADED|OWNER_UNAVAILABLE)" <<<"$J"; then
  echo "ABORT: phát hiện SECRETS_DEGRADED/OWNER_UNAVAILABLE trong journal"
  false
fi
if grep -q 'degraded to "legacy"' <<<"$J"; then
  echo "ABORT: phát hiện lossless-claw degraded to legacy"
  false
fi

NEW_PID=$(systemctl --user show "$U" -p MainPID --value)
ACTUAL_EXE=$(readlink -f "/proc/$NEW_PID/exe")
[ "$ACTUAL_EXE" = "$NODE_BIN" ] || { echo "ABORT: /proc/$NEW_PID/exe = $ACTUAL_EXE (!= $NODE_BIN)"; false; }
SERVING_VER=$(tr '\0' '\n' < "/proc/$NEW_PID/environ" | grep '^OPENCLAW_SERVICE_VERSION=' | cut -d= -f2 || true)
[ "$SERVING_VER" = "2026.9.34" ] || { echo "ABORT: OPENCLAW_SERVICE_VERSION=$SERVING_VER (!= 2026.9.34)"; false; }

python3 - "$D" <<'PY'
from contextlib import closing
import pathlib, sqlite3, sys
d = pathlib.Path(sys.argv[1])
for rel in ("state/openclaw.sqlite", "lcm.db", "agents/main/agent/openclaw-agent.sqlite"):
    with closing(sqlite3.connect(f"file:{d / rel}?mode=ro", uri=True)) as db:
        assert db.execute("pragma quick_check").fetchone()[0] == "ok", f"{rel} quick_check != ok"
PY

OTHER_PID_AFTER=$(systemctl --user show "$OTHER_U" -p MainPID --value)
OTHER_RESTARTS_AFTER=$(systemctl --user show "$OTHER_U" -p NRestarts --value)
[ "$OTHER_PID_BEFORE" = "$OTHER_PID_AFTER" ] || { echo "ABORT: peer $OTHER_U đổi PID"; false; }
[ "$OTHER_RESTARTS_BEFORE" = "$OTHER_RESTARTS_AFTER" ] || { echo "ABORT: peer $OTHER_U tăng NRestarts"; false; }

PHASE=done
if [ "$HC_WAS" = "active" ]; then
  systemctl --user start openclaw-healthcheck.timer
fi
echo "UPGRADE_934_OK profile=$P pid=$NEW_PID node=v24.22.1 core=$SERVING_VER backup=$B"
