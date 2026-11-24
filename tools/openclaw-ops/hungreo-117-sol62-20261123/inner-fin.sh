#!/usr/bin/env bash
# Inside the isolated container: start 11.7 gateway on the copy (no channels, no cron, no network),
# record hungreo-finance load as TS source, then swap in the esbuild JS bundle and reload.
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
export OPENCLAW_SKIP_CHANNELS=1 OPENCLAW_SKIP_CRON=1 OPENCLAW_SERVICE_VERSION=2026.11.7
export PATH="${NODE%/*}:/usr/bin:/bin" DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent-bus"
cd "$P/workspace"
"$NODE" --import "$U/ops/binding-compat.mjs" "$ENTRY" gateway --port 18789 > /home/hung/out/gateway.log 2>&1 &
gw=$!
for i in $(seq 1 100); do [[ "$(curl -s -o /dev/null -w %{http_code} --max-time 2 http://127.0.0.1:18789/readyz)" == 200 ]] && break; sleep 3; done
echo "READY_AFTER=$((i*3))s"
grep -E "hungreo-finance|http server listening" /home/hung/out/gateway.log | cut -c1-300
echo "=== SWAP TO JS BUNDLE"
mv -T "$P/extensions/hungreo-finance" "$P/extensions/.hungreo-finance-ts"
cp -a /home/hung/finance-js "$P/extensions/hungreo-finance"
timeout 200 "$NODE" "$ENTRY" --profile hungreo plugins reload hungreo-finance --json 2>&1 | tail -12 | cut -c1-400
echo "RELOAD_RC=$?"
grep -E "hungreo-finance" /home/hung/out/gateway.log | tail -4 | cut -c1-300
kill $gw; wait $gw 2>/dev/null; echo GW_STOPPED
