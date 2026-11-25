#!/usr/bin/env bash
# Runs inside the isolated container. $1 = label for the log.
set -uo pipefail
P=/home/hung/.openclaw-hungreo
U=/home/hung/openclaw-upgrade-hungreo-20261123-117
NODE=/home/hung/openclaw-node-24.22.1/node/bin/node
ENTRY=$U/runtime/node_modules/openclaw/dist/index.js
for item in $(compgen -v OPENCLAW_ || true); do unset "$item"; done
unset TELEGRAM_BOT_TOKEN OPENAI_API_KEY
set -a; source "$P/gateway.systemd.env"; set +a
unset OPENAI_API_KEY
export OPENCLAW_PROFILE=hungreo OPENCLAW_STATE_DIR="$P" OPENCLAW_CONFIG_PATH="$P/openclaw.json" OPENCLAW_GATEWAY_PORT=18789
export OPENCLAW_SYSTEMD_UNIT=openclaw-gateway-hungreo.service OPENCLAW_SKIP_CHANNELS=1 OPENCLAW_SKIP_CRON=1
export npm_config_cache="$U/npm-cache" npm_config_registry=https://registry.npmjs.org npm_config_offline="${NPM_OFFLINE:-true}"
export PATH="$U/runtime/node_modules/.bin:${NODE%/*}:/usr/bin:/bin"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent-bus"
cd "$P/workspace"
oc() { timeout --kill-after=45 "${T:-600}" "$NODE" "$ENTRY" --profile hungreo "$@" </dev/null; }
case "$1" in
  version) oc --version ;;
  doctor) start=$(date +%s); oc doctor --fix --non-interactive --no-workspace-suggestions; rc=$?; echo "DOCTOR_RC=$rc elapsed=$(( $(date +%s)-start ))s" ;;
  checks) T=180 oc config validate; echo "VALIDATE_RC=$?"; T=180 oc skills list --json > /home/hung/out/skills.json 2>/home/hung/out/skills.err; echo "SKILLS_RC=$?" ;;
esac
if [[ "$1" == peer-links ]]; then "$NODE" /home/hung/ops/peer-links.mjs "$P" "$U/runtime/node_modules/openclaw"; exit $?; fi
if [[ "$1" == run ]]; then shift; T=${T:-300} oc "$@"; echo "RC=$?"; fi
exit 0
