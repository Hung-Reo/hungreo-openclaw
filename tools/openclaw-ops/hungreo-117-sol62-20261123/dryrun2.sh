#!/usr/bin/env bash
# Offline rehearsal of cutover.sh phases MIGRATE + PLUGINS on a copy. Never touches the live profile.
set -Eeuo pipefail; umask 077
P=/home/hung/.openclaw-hungreo; U=/home/hung/openclaw-upgrade-hungreo-20261123-117
R=$1; C=$R/profile; O=$R/out; OPS=$R/ops
NODE=/home/hung/openclaw-node-24.22.1/node/bin/node
[[ "$R" == /home/hung/claude-dryrun-117-* && ! -e "$C" ]]
mkdir -p -m 700 "$O" "$R/before/state" "$R/before/workspace" "$R/chome" "$R/ctmp"
step() { printf '%s %s\n' "$(date +%T)" "$*"; }
run() { "$OPS/docker-run.sh" "$@"; }
check() { OC_CHECK_PROFILE="$C" python3 -I "$OPS/profile-check.py" "$@"; }

step COPY
nice -n 10 ionice -c3 rsync -aHAX --numeric-ids --exclude=/tmp/ --exclude=/cache/ --exclude='*-shm' --exclude='*-wal' "$P/" "$C/" >"$O/copy.log" 2>&1 || [[ $? == 24 ]]
nice -n 10 python3 -I "$OPS/snapdb.py" "$P" "$C" >"$O/snapdb.log"
grep -c 'quick_check=ok' "$O/snapdb.log"; ! grep -v 'quick_check=ok' "$O/snapdb.log"
python3 -I - "$C/state/openclaw.sqlite" <<'PY'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])  # copy only: simulate the clean stop that cutover.sh performs
print("leases_removed", db.execute("delete from state_leases").rowcount, db.execute("delete from agent_database_leases").rowcount)
db.execute("update gateway_boot_lifecycle set completed_at_ms=strftime('%s','now')*1000, outcome='clean_stop', reason='dry-run simulated stop' where completed_at_ms is null")
db.commit()
PY
cp -p "$C/openclaw.json" "$R/before/"; cp -p "$C/state/openclaw.sqlite" "$R/before/state/"; cp -p "$C/workspace/HEARTBEAT.md" "$R/before/workspace/"
python3 -I "$OPS/compare.py" snapshot "$C" "$R/before/must-keep.json"
"$NODE" "$OPS/project-heartbeat.mjs" "$U/runtime/node_modules/openclaw/dist" "$C/openclaw.json" "$O/projected-config.json"

step MIGRATE   # same block as cutover.sh
if [[ -d "$C/workspace/skills/nano-banana-pro" ]]; then
  mkdir -p -m 700 "$C/workspace/.retired-skills-117"
  mv -T "$C/workspace/skills/nano-banana-pro" "$C/workspace/.retired-skills-117/nano-banana-pro"
fi
run doctor >"$O/doctor-fix.log" 2>&1; grep -q 'DOCTOR_RC=0' "$O/doctor-fix.log"
check config "$O/projected-config.json" original
check heartbeat "$R/before" "$C"
check batch "$R/before/openclaw.json" "$O/model-batch.json"
run run config set --batch-file /home/hung/out/model-batch.json --dry-run >"$O/model-dryrun.log" 2>&1; grep -q '^RC=0' "$O/model-dryrun.log"

step PLUGINS   # network only for npm; gateway listens on host loopback, unreachable from the bridge
for spec in codex brave-plugin deepseek-provider parallel-plugin typesafe; do
  NET=bridge run run plugins update "@openclaw/$spec@2026.11.7" --dry-run >"$O/$spec.dryrun.log" 2>&1
  grep -q '^RC=0' "$O/$spec.dryrun.log"; grep -Fq '2026.11.7' "$O/$spec.dryrun.log"
done
for spec in codex brave-plugin deepseek-provider parallel-plugin typesafe; do
  NET=bridge run run plugins update "@openclaw/$spec@2026.11.7" >"$O/$spec.update.log" 2>&1; grep -q '^RC=0' "$O/$spec.update.log"
done
run peer-links >"$O/peer-links.log" 2>&1
check config "$O/projected-config.json" original
check heartbeat "$R/before" "$C"
run run config set --batch-file /home/hung/out/model-batch.json >"$O/model-set.log" 2>&1; grep -q '^RC=0' "$O/model-set.log"
run run config validate >"$O/config-validate.log" 2>&1; grep -q '^RC=0' "$O/config-validate.log"
check config "$O/projected-config.json" updated
check db "$C"
python3 -I "$OPS/compare.py" compare "$R/before" "$C" "$U/runtime/node_modules/openclaw/skills" || true
step DRYRUN_OK
