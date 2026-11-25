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
oc() { timeout --kill-after=30 "${T:-300}" "$NODE" "$ENTRY" --profile hungreo "$@" </dev/null; }
ready() { "$NODE" -e 'fetch("http://127.0.0.1:18789/readyz").then(r=>process.exit(r.status==200?0:1),()=>process.exit(1))'; }
# Gateway is stopped here. Put the JS bundle in place and move the TS original out of the scan root.
if [[ -d "$P/extensions/.hungreo-finance-ts" ]]; then mv -T "$P/extensions/.hungreo-finance-ts" /home/hung/finance-ts-orig; fi
echo "entry: $(grep -o '"./[^"]*"' $P/extensions/hungreo-finance/package.json | head -1)"
oc plugins registry --refresh > /home/hung/out/registry-refresh.log 2>&1; echo "REGISTRY_RC=$?"; tail -3 /home/hung/out/registry-refresh.log | cut -c1-300
"$NODE" --import "$U/ops/binding-compat.mjs" "$ENTRY" gateway --port 18789 > /home/hung/out/gateway2.log 2>&1 &
gw=$!
for i in $(seq 1 100); do ready && break; sleep 3; done
echo "READY_AFTER=$((i*3))s"
grep -E "hungreo-finance|http server listening" /home/hung/out/gateway2.log | cut -c1-300
T=120 oc plugins inspect hungreo-finance > /home/hung/out/inspect.log 2>&1; echo "INSPECT_RC=$?"; grep -iE "status|loaded|error|entry|source" /home/hung/out/inspect.log | head -8 | cut -c1-200
kill $gw; wait $gw 2>/dev/null; echo GW_STOPPED
