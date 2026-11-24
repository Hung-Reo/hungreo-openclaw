#!/usr/bin/env bash
# Offline rehearsal of cutover.sh phases MIGRATE + PLUGINS on a copy. Never touches the live profile.
set -Eeuo pipefail; umask 077
P=/home/hung/.openclaw-hungreo; U=/home/hung/openclaw-upgrade-hungreo-20261123-117
R=$1; C=$R/profile; O=$R/out; OPS=$R/ops
NODE=/home/hung/openclaw-node-24.22.1/node/bin/node
[[ "$R" == /home/hung/claude-dryrun-117-* && -d "$C" ]]
mkdir -p -m 700 "$O" "$R/before/state" "$R/before/workspace" "$R/chome" "$R/ctmp"
step() { printf '%s %s\n' "$(date +%T)" "$*"; }
run() { "$OPS/docker-run.sh" "$@"; }
check() { OC_CHECK_PROFILE="$C" python3 -I "$OPS/profile-check.py" "$@"; }

step RESUME_AFTER_DOCTOR
check heartbeat "$R/before" "$C"
check batch "$R/before/openclaw.json" "$O/model-batch.json"

step PLUGINS   # offline from the staged npm cache: a networked copy could refresh the live Codex OAuth token
for spec in codex brave-plugin deepseek-provider parallel-plugin typesafe; do
  run run plugins update "@openclaw/$spec@2026.11.7" --dry-run >"$O/$spec.dryrun.log" 2>&1
  grep -q '^RC=0' "$O/$spec.dryrun.log"; grep -Fq '2026.11.7' "$O/$spec.dryrun.log"
done
for spec in codex brave-plugin deepseek-provider parallel-plugin typesafe; do
  run run plugins update "@openclaw/$spec@2026.11.7" >"$O/$spec.update.log" 2>&1; grep -q '^RC=0' "$O/$spec.update.log"
done
run peer-links >"$O/peer-links.log" 2>&1
check config "$O/projected-config.json" original
check heartbeat "$R/before" "$C"
run run config validate >"$O/config-validate.log" 2>&1; grep -q '^RC=0' "$O/config-validate.log"
check db "$C"
python3 -I "$OPS/compare.py" compare "$R/before" "$C" "$U/runtime/node_modules/openclaw/skills" || true
step DRYRUN_OK
