#!/usr/bin/env bash
# Writes only to the isolated rehearsal state. No exposed ports, Telegram token blank.
set -Eeuo pipefail
S=/home/hung/sandbox-nemo; T=$S/ops-10.3-lcm-20261014; R=$S/runtime-10.3
IMG=node:24.21.0-bookworm-slim; CA=/etc/ssl/certs/ca-certificates.crt
oc(){ docker run --rm --user 1001:1001 --cpus 1 --memory 1100m --memory-swap 1100m \
 --env-file "$S/nemo.env" -e TELEGRAM_BOT_TOKEN= -e HOME=/sandbox/config \
 -e OPENCLAW_STATE_DIR=/sandbox/config -e OPENCLAW_CONFIG_PATH=/sandbox/config/openclaw.json \
 -e SSL_CERT_FILE="$CA" -e NODE_OPTIONS=--max-old-space-size=640 \
 -v "$CA:$CA:ro" -v "$R:/sandbox/runtime:ro" -v "$T/rehearsal-config:/sandbox/config" \
 -v "$T/rehearsal-workspace:/sandbox/rehearsal-workspace" \
 "$IMG" node /sandbox/runtime/node_modules/openclaw/openclaw.mjs "$@" < /dev/null; }
oc config validate > "$T/rehearsal-validate-before.log" 2>&1
oc plugins update codex --dry-run > "$T/rehearsal-codex-dryrun.log" 2>&1
oc plugins update codex > "$T/rehearsal-codex-update.log" 2>&1
oc plugins install @martian-engineering/lossless-claw@1.1.1 --pin --force --accept-capabilities > "$T/rehearsal-lcm-install.log" 2>&1
oc config set plugins.entries.lossless-claw.hooks.allowConversationAccess true > "$T/rehearsal-lcm-hook.log" 2>&1
oc config validate > "$T/rehearsal-validate-after.log" 2>&1
if oc doctor --lint --json > "$T/rehearsal-doctor.json" 2> "$T/rehearsal-doctor.err"; then
 D_RC=0
else
 D_RC=$?
fi
[ "$D_RC" = 0 ] || [ "$D_RC" = 1 ]
python3 - "$T/rehearsal-config" <<'PY'
import sys,pathlib,json,sqlite3
b=pathlib.Path(sys.argv[1]);c=json.loads((b/'openclaw.json').read_text());assert c['agents']['defaults']['model']=={'primary':'openrouter/meta/muse-spark-1.3-contributor','fallbacks':['openai/gpt-6.1-sol']}
assert c['plugins']['slots']['contextEngine']=='lossless-claw';assert c['plugins']['entries']['lossless-claw']['enabled'];assert c['plugins']['entries']['lossless-claw']['hooks']['allowConversationAccess']
db=sqlite3.connect((b/'state/openclaw.sqlite').as_uri()+'?mode=ro',uri=True);r=db.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone();idx=json.loads(r[0])['index']['installRecords'];assert idx['lossless-claw']['version']=='1.1.1';assert idx['codex']['version']=='2026.10.3';print('REHEARSAL_INSTALL_MODEL_SLOT_PLUGIN_VERSIONS_OK')
PY
