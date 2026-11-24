#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
export TZ=Asia/Ho_Chi_Minh

UPGRADE=/home/hung/openclaw-upgrade-hungreo-20261123-117
OLD=/home/hung/openclaw-upgrade-20261111-936/runtime
RUNTIME="$UPGRADE/runtime"
NODE=/home/hung/openclaw-node-24.22.1/node/bin/node
ENTRY="$RUNTIME/node_modules/openclaw/dist/index.js"
PROFILE=/home/hung/.openclaw-hungreo
OPS="$UPGRADE/ops"
UNIT=openclaw-gateway-hungreo.service
PEER_UNIT=openclaw-gateway-suckhoe.service
TIMER=openclaw-healthcheck.timer
TIMER_WORKER=openclaw-healthcheck.service
FINANCE=hungreo-finance-backup.service
UNITS=/home/hung/.config/systemd/user
DROP="$UNITS/$UNIT.d/zzzzz-upgrade-99.conf"
HOLD="$UNITS/$UNIT.d/zzzzzz-hungreo-117-maintenance.conf"
FINANCE_DROP="$UNITS/$FINANCE.d/zz-upgrade-99.conf"
WRAPPER=/home/hung/bin/openclaw
BACKUP_ROOT=/home/hung/backups/hungreo-rollback-openclaw-117
export PATH="${NODE%/*}:/usr/bin:/bin"

check() { python3 "$OPS/profile-check.py" "$@"; }
unit() { systemctl --user "$@"; }
ready() { curl -sS --max-time 3 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$1/readyz" 2>/dev/null; }
pid() { unit show "$1" -p MainPID --value; }
listener() { ss -H -ltn "sport = :$1" | grep -q .; }

wait_ready() {
  local expect=$1 running i
  for ((i=0; i<90; i++)); do
    running=$(pid "$UNIT")
    if [[ "$running" != 0 && "$(ready 18789 || true)" == 200 ]] &&
       grep -zFxq -- "$expect" "/proc/$running/cmdline" 2>/dev/null; then
      return 0
    fi
    sleep 3
  done
  echo "Rùa chưa ready với runtime dự kiến"
  return 1
}

wait_stopped() {
  [[ "$(pid "$UNIT")" == 0 ]] && ! listener 18789 && ! listener 8787
}

atomic_copy() {
  local source=$1 destination=$2 temp
  temp=$(mktemp "${destination}.117.XXXXXXXX")
  cp -p -- "$source" "$temp"
  mv -fT -- "$temp" "$destination"
}

phase() {
  echo "$1" > "$B/phase.tmp"
  mv -fT "$B/phase.tmp" "$B/phase"
  sync -f "$B"
  printf '%s %s\n' "$(date -Iseconds)" "$1"
}

restore_timer() {
  if [[ "$(cat "$B/timer-state")" == active ]]; then
    unit start "$TIMER" && unit is-active --quiet "$TIMER"
  fi
}

start_old_gateway() {
  # Let systemd queue the start, then verify the old executable and the live
  # probe before restoring the shared healthcheck schedule.
  unit start --no-block "$UNIT" &&
    wait_ready "$OLD/node_modules/openclaw/dist/index.js" &&
    restore_timer
}

rollback() {
  trap - ERR INT TERM HUP
  if [[ "$(cat "$B/phase")" == ROLLED_BACK ]]; then
    wait_ready "$OLD/node_modules/openclaw/dist/index.js" && restore_timer
    return $?
  fi
  local post
  echo "ROLLBACK_BEGIN backup=$B"
  unit stop "$TIMER" "$TIMER_WORKER" || return 1
  unit stop "$UNIT" || return 1
  wait_stopped || return 1
  if [[ "$(cat "$B/phase")" == STOP_BACKUP && ! -e "$B/profile" && -d "$PROFILE" ]]; then
    # Cutover never touched the active files. Restore availability even if the
    # aborted check was the writer inspection itself.
    start_old_gateway || return 1
    phase ROLLED_BACK
    return
  fi

  if [[ -d "$B/profile" ]]; then
    (cd "$B/profile" && sha256sum -c --quiet "$B/critical.sha256") || return 1
    if [[ -e "$PROFILE" ]]; then
      post=$(mktemp -d "$B/post-cutover.XXXXXXXX") || return 1
      mv -T "$PROFILE" "$post/profile" || return 1
      echo "POST_CUTOVER_PRESERVED $post/profile"
    fi
    mv -T "$B/profile" "$PROFILE" || return 1
  fi
  [[ -f "$PROFILE/openclaw.json" ]] || return 1
  atomic_copy "$B/old-gateway.conf" "$DROP" || return 1
  atomic_copy "$B/old-finance.conf" "$FINANCE_DROP" || return 1
  atomic_copy "$B/old-cli" "$WRAPPER" || return 1
  if [[ -f "$HOLD" ]]; then
    post=$(mktemp "$B/maintenance.XXXXXXXX.conf") || return 1
    mv -T "$HOLD" "$post" || return 1
  fi
  unit daemon-reload || return 1
  start_old_gateway || return 1
  phase ROLLED_BACK
}

failed() {
  local rc=$1 line=$2
  if ((BASH_SUBSHELL > 0)); then
    exit "$rc"
  fi
  trap - ERR INT TERM HUP
  echo "CUTOVER_FAILED rc=$rc line=$line phase=$(cat "$B/phase")"
  case "$(cat "$B/phase")" in
    PRECOPY|PRECHECK) echo "Rùa vẫn trên runtime cũ." ;;
    OPEN_TRAFFIC|SUCCESS) echo "TRAFFIC_MAY_HAVE_RUN. Preserve and inspect post-cutover state before restoring." ;;
    *) rollback || echo "ROLLBACK_FAILED backup=$B" ;;
  esac
  exit "$rc"
}

# Run admin commands with the correct profile environment and no inherited route.
oc() (
  local item
  for item in $(compgen -v OPENCLAW_ || true); do unset "$item"; done
  unset TELEGRAM_BOT_TOKEN OPENAI_API_KEY
  set -a
  source "$PROFILE/gateway.systemd.env"
  set +a
  unset OPENAI_API_KEY
  export OPENCLAW_PROFILE=hungreo OPENCLAW_STATE_DIR="$PROFILE"
  export OPENCLAW_CONFIG_PATH="$PROFILE/openclaw.json" OPENCLAW_GATEWAY_PORT=18789
  export OPENCLAW_SYSTEMD_UNIT="$UNIT"
  export OPENCLAW_SKIP_CHANNELS=1 OPENCLAW_SKIP_CRON=1
  export npm_config_cache="$UPGRADE/npm-cache" npm_config_registry=https://registry.npmjs.org
  export PATH="$RUNTIME/node_modules/.bin:${NODE%/*}:/usr/bin:/bin"
  if [[ "${OC_OFFLINE_SERVICE:-1}" == 1 ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$UPGRADE/missing-user-bus"
  fi
  cd "$PROFILE/workspace"
  timeout --kill-after=45 "${OC_TIMEOUT_SECONDS:-220}" "$NODE" "$ENTRY" --profile hungreo "$@" </dev/null
)

verify_peer() {
  [[ "$(pid "$PEER_UNIT")" == "$(cat "$B/peer-pid")" ]]
  [[ "$(unit show "$PEER_UNIT" -p NRestarts --value)" == "$(cat "$B/peer-restarts")" ]]
  [[ "$(ready 18795)" == 200 ]]
}

capture_units() {
  cp -a "$UNITS/$UNIT" "$UNITS/$UNIT.d" "$UNITS/$FINANCE" "$UNITS/$FINANCE.d" "$B/"
  cp -p "$DROP" "$B/old-gateway.conf"
  cp -p "$FINANCE_DROP" "$B/old-finance.conf"
  cp -p "$WRAPPER" "$B/old-cli"
}

build_dispatch() {
  python3 - "$B" "$UPGRADE" "$OLD" <<'PY'
from pathlib import Path
import sys
b, stage, old = map(Path, sys.argv[1:])
new = str(stage / "runtime")
current = (b / "old-gateway.conf").read_text()
assert current.count(str(old)) >= 3 and "OPENCLAW_SERVICE_VERSION=2026.9.36" in current
lines = current.replace(str(old), new).replace("2026.9.36", "2026.11.7").splitlines()
new_lines = []
for line in lines:
    if line.startswith("ExecStartPre=") and "verify-command-registry-98.mjs" in line:
        continue
    if line.startswith("ExecStart=") and "patch-binding-loader-hook.mjs" in line:
        old_hook = "/home/hung/openclaw-upgrade-20261003/live-gates/patch-binding-loader-hook.mjs"
        line = line.replace(old_hook, str(stage / "ops/binding-compat.mjs"))
    new_lines.append(line)
assert sum("binding-compat.mjs" in line for line in new_lines) == 1
(b / "new-gateway.conf").write_text("\n".join(new_lines) + "\n")
finance = (b / "old-finance.conf").read_text()
assert finance.count(str(old)) == 1 and "finance backup" in finance
(b / "new-finance.conf").write_text(finance.replace(str(old), new))
wrapper = (b / "old-cli").read_text()
anchor = "  if grep -q 'openclaw-upgrade-20261111-936' \"$dropin\" 2>/dev/null; then"
assert wrapper.count(anchor) == 1
wrapper = wrapper.replace(anchor, (
    "  if [[ \"$selected\" == hungreo ]] && grep -q 'openclaw-upgrade-hungreo-20261123-117' \"$dropin\" 2>/dev/null; then\n"
    f"    entry={new}/node_modules/openclaw/dist/index.js\n"
    + anchor.replace("  if ", "  elif ", 1)
))
(b / "new-cli").write_text(wrapper)
for dest, source in [("new-gateway.conf", "old-gateway.conf"), ("new-finance.conf", "old-finance.conf"), ("new-cli", "old-cli")]:
    (b / dest).chmod((b / source).stat().st_mode & 0o777)
PY
  bash -n "$B/new-cli"
}

[[ "$(hostname -s)" == srv1367812 ]]
[[ -x "$NODE" ]]
exec 9>"$UPGRADE/hungreo-117.lock"
flock -n 9
if [[ "${1:-}" == rollback ]]; then
  B=$(realpath -e -- "${2:?Specify the backup directory}")
  [[ "$B" == "$BACKUP_ROOT/"* && -f "$B/phase" ]]
  rollback
  exit
fi
[[ "${1:-}" == apply-heartbeat ]]
[[ -d "$PROFILE" && ! -L "$PROFILE" ]]
jq -e '.agents.defaults as $a | $a.heartbeat as $h |
  $h.every == "2h" and $h.isolatedSession == true and $h.lightContext == true and
  $h.activeHours == {start:"06:00",end:"23:00",timezone:"Asia/Ho_Chi_Minh"} and
  $h.model == "openai/gpt-5.6-luna" and ($a.modelPolicy.allow | index($h.model)) != null
' "$PROFILE/openclaw.json" >/dev/null
[[ ! -e "$HOLD" && "$(ready 18789)" == 200 && "$(ready 18795)" == 200 ]]
[[ "$(unit is-active "$TIMER")" == active ]]
[[ "$(unit is-active "$FINANCE" || true)" == inactive ]]
grep -q 'openclaw-upgrade-20261111-936' "$DROP"
"$NODE" --import "$OPS/binding-compat.mjs" "$ENTRY" --version | grep -Fq "2026.11.7"
mkdir -p -m 700 "$BACKUP_ROOT"
B=$(mktemp -d "$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S).XXXXXXXX")
echo "BACKUP_DIR=$B"
phase PRECHECK
trap 'failed $? $LINENO' ERR
trap 'failed 130 $LINENO' INT TERM HUP
capture_units
build_dispatch
"$NODE" "$OPS/project-heartbeat.mjs" "${ENTRY%/*}" "$PROFILE/openclaw.json" "$B/projected-config.json"
unit is-active "$TIMER" > "$B/timer-state"
pid "$PEER_UNIT" > "$B/peer-pid"
unit show "$PEER_UNIT" -p NRestarts --value > "$B/peer-restarts"
[[ "$(stat -c %d "$PROFILE")" == "$(stat -c %d "$B")" ]]
required=$(du -sB1 "$PROFILE" | cut -f1)
free=$(df -B1 --output=avail "$B" | tail -1)
previous=""
already_copied=0
if [[ -n "${2:-}" ]]; then
  previous=$(realpath -e -- "$2")
  [[ "$previous" == "$BACKUP_ROOT/"* ]]
  previous_phase=$(cat "$previous/phase")
  [[ "$previous_phase" == ROLLED_BACK || "$previous_phase" == PREPARED ]]
  if [[ "$previous_phase" == PREPARED ]]; then
    [[ "$(cat "$previous/source-profile")" == "$PROFILE" ]]
  fi
  [[ ! -e "$previous/profile" && -d "$previous/working" && ! -L "$previous/working" ]]
  already_copied=$(du -sB1 "$previous/working" | cut -f1)
fi
((free + already_copied > required + 5 * 1024 * 1024 * 1024))
check idle
check writer-scan-access

phase PRECOPY
working="$B/working"
if [[ -n "$previous" ]]; then
  mv -T "$previous/working" "$working"
else
  mkdir -m 700 "$working"
fi
# Pre-copy while serving. The cold pass below replaces all live-read bytes that differ.
rsync -aHAX --numeric-ids --delete --exclude='*-shm' "$PROFILE/" "$working/" >"$B/precopy.log" 2>&1 ||
  [[ $? == 24 ]]
check idle
[[ "$(unit is-active "$FINANCE" || true)" == inactive ]]

phase STOP_BACKUP
unit stop "$TIMER" "$TIMER_WORKER"
unit stop "$UNIT"
wait_stopped
check writers
rsync -aHAXc --numeric-ids --delete --exclude='*-shm' "$PROFILE/" "$working/" >"$B/cold-copy.log" 2>&1
rsync -aHAXcn --numeric-ids --delete --exclude='*-shm' --itemize-changes "$PROFILE/" "$working/" >"$B/copy-compare.log" 2>&1
[[ ! -s "$B/copy-compare.log" ]]
check db "$working"
check writers
(cd "$PROFILE" && for f in openclaw.json gateway.systemd.env state/openclaw.sqlite agents/main/agent/openclaw-agent.sqlite lcm.db; do
  sha256sum "$f"
  if [[ -f "$f-wal" ]]; then sha256sum "$f-wal"; fi
done) > "$B/critical.sha256"
sha256sum "$B/old-gateway.conf" "$B/old-finance.conf" "$B/old-cli" > "$B/unit-cli.sha256"
sync -f "$B"

phase SWAP
mv -T "$PROFILE" "$B/profile"
mv -T "$working" "$PROFILE"

phase MIGRATE
# 11.7 retired the bundled nano-banana-pro skill and Doctor deletes its disable entry.
# Archive the workspace copy (not delete) so it cannot become enabled; the 9.36 original in $B/profile keeps it.
if [[ -d "$PROFILE/workspace/skills/nano-banana-pro" ]]; then
  mkdir -p -m 700 "$PROFILE/workspace/.retired-skills-117"
  mv -T "$PROFILE/workspace/skills/nano-banana-pro" "$PROFILE/workspace/.retired-skills-117/nano-banana-pro"
fi
# The new CLI refuses a forward schema write if the selected service still
# identifies the old runtime. Change its definition while it is stopped.
atomic_copy "$B/new-gateway.conf" "$DROP"
unit daemon-reload
# 24/11 14:12: Doctor 11.7 restarts the service by itself ("Gateway restarted and verified after
# Doctor maintenance"). Hold channels and cron before it can, and stop it again afterwards so the
# offline-only steps below (plugins, models auth) keep exclusive state ownership.
printf '[Service]\nEnvironment=OPENCLAW_SKIP_CHANNELS=1 OPENCLAW_SKIP_CRON=1\n' >"$HOLD"
unit daemon-reload
OC_TIMEOUT_SECONDS=600 oc doctor --fix --non-interactive --no-workspace-suggestions >"$B/doctor-fix.log" 2>&1
if [[ "$(pid "$UNIT")" != 0 ]]; then
  echo "doctor_restarted_gateway=yes, stopping again"
  unit stop "$UNIT"
fi
wait_stopped
check config "$B/projected-config.json" original
check heartbeat "$B/profile" "$PROFILE"
# 24/11: Hưng chose to keep Sol 6.1 (the Codex account does not offer gpt-6.2-sol yet); no model change here.

plugins=(
  @openclaw/codex@2026.11.7
  @openclaw/brave-plugin@2026.11.7
  @openclaw/deepseek-provider@2026.11.7
  @openclaw/parallel-plugin@2026.11.7
  @openclaw/typesafe@2026.11.7
)
phase PLUGINS
for spec in "${plugins[@]}"; do
  label=${spec#@openclaw/}
  oc plugins update "$spec" --dry-run > "$B/$label.dryrun.log" 2>&1
  grep -Fq '2026.11.7' "$B/$label.dryrun.log"
done
# 24/11 12:49: Doctor already converges all five to 2026.11.7, and a real update on the
# host is refused ("requires exclusive offline state ownership"). Update only what is behind.
for spec in "${plugins[@]}"; do
  label=${spec#@openclaw/}
  if grep -Fq "is up to date (2026.11.7)" "$B/$label.dryrun.log"; then
    echo "$label already 2026.11.7, update skipped"
    continue
  fi
  oc plugins update "$spec" > "$B/$label.update.log" 2>&1
done
"$NODE" "$OPS/peer-links.mjs" "$PROFILE" "$RUNTIME/node_modules/openclaw"
check config "$B/projected-config.json" original
check heartbeat "$B/profile" "$PROFILE"
oc config validate >"$B/config-validate.log" 2>&1
check config "$B/projected-config.json" original
check db "$PROFILE"

# 24/11 13:19: on 11.7 `models auth` is offline-only (refused while any Gateway owns the
# state). Verify the OAuth-only route while the gateway is still stopped; retry briefly in case a
# child process of the previous CLI call still holds the embedded owner lock.
for attempt in 1 2 3; do
  if oc models auth list --json >"$B/auth.json" 2>"$B/auth.err"; then break; fi
  ((attempt < 3)) && sleep 20
done
python3 "$OPS/verify-auth.py" "$B/auth.json"

phase START_RESTRICTED
atomic_copy "$B/new-finance.conf" "$FINANCE_DROP"
atomic_copy "$B/new-cli" "$WRAPPER"
printf '[Service]\nEnvironment=OPENCLAW_SKIP_CHANNELS=1 OPENCLAW_SKIP_CRON=1\n' >"$HOLD"
unit daemon-reload
unit start "$UNIT"
wait_ready "$ENTRY"
! listener 8787
verify_peer
"$WRAPPER" --profile hungreo --version | grep -Fq '2026.11.7'
"$WRAPPER" --profile suckhoe --version | grep -Fq '2026.9.36'

phase MODEL_CHECK
probe_id=$(cat /proc/sys/kernel/random/uuid)
oc agent --agent main --session-id "$probe_id" --model openai/gpt-6.1-sol --thinking medium \
  --message 'Reply with exactly RUA_SOL61_OK. Do not use tools or send any messages.' --json --timeout 105 \
  >"$B/sol61-receipt.json" 2>"$B/sol61-receipt.err"
check receipt "$B/sol61-receipt.json" gpt-6.1-sol RUA_SOL61_OK
check heartbeat "$B/profile" "$PROFILE" verify-next-run

phase OPEN_TRAFFIC
unit stop "$UNIT"
wait_stopped
mv -T "$HOLD" "$B/maintenance-used.conf"
unit daemon-reload
unit start "$UNIT"
wait_ready "$ENTRY"
for ((i=0; i<40; i++)); do
  listener 8787 && break
  sleep 2
done
listener 8787
verify_peer
check config "$B/projected-config.json" original
check heartbeat "$B/profile" "$PROFILE"
oc channels status --probe --json > "$B/channels-status.json" 2>"$B/channels-status.err"
python3 "$OPS/verify-channel.py" "$B/channels-status.json"
restore_timer
phase SUCCESS
echo "UPGRADE_OK backup=$B"
