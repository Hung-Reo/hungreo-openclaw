#!/usr/bin/env bash
# Run only after the isolated compaction/restart/recall checks pass.
set -Eeuo pipefail
S=/home/hung/sandbox-nemo; T=$S/ops-10.3-lcm-20261014; R=$S/runtime-10.3
B=$(cat "$T/backup-path"); IMG=node:24.21.0-bookworm-slim; CA=/etc/ssl/certs/ca-certificates.crt
[ "$(hostname)" = srv1367812 ]
[ "$(docker inspect nemo-sandbox --format '{{.State.Running}}')" = false ]
[ -f "$T/rehearsal-recall.json" ]
python3 - "$T" <<'PY'
import pathlib,json,sqlite3,sys
p=pathlib.Path(sys.argv[1]);s=(p/'rehearsal-recall.json').read_text();d=None
for i,c in enumerate(s):
 if c!='{':continue
 try:d,end=json.JSONDecoder().raw_decode(s[i:]);break
 except Exception:continue
assert d and d.get('status')=='ok';assert any('SEN-731' in x.get('text','') for x in d['result']['payloads'])
db=sqlite3.connect((p/'rehearsal-config/lcm.db').as_uri()+'?mode=ro',uri=True);assert db.execute('select count(*) from summaries').fetchone()[0]>0;assert db.execute('pragma quick_check').fetchone()[0]=='ok';db.close()
print('REHEARSAL_GATE_PASSED')
PY
(cd "$B" && sha256sum -c SHA256SUMS)
on_error(){ trap - ERR; echo 'CUTOVER_ERROR_RESTORING_NEMO_10_2'; bash "$T/99_rollback.sh" "$B"; exit 1; }
trap on_error ERR
docker stop -t 45 nemo-rehearsal-103-lcm >/dev/null
oc(){ docker run --rm --user 1001:1001 --cpus 1 --memory 1300m --memory-swap 1300m \
 --env-file "$S/nemo.env" -e HOME=/sandbox/config -e OPENCLAW_STATE_DIR=/sandbox/config \
 -e OPENCLAW_CONFIG_PATH=/sandbox/config/openclaw.json -e SSL_CERT_FILE="$CA" \
 -v "$CA:$CA:ro" -v "$R:/sandbox/runtime:ro" -v "$S/config:/sandbox/config" \
 -v "$S/workspace:/sandbox/workspace" -v "$S/.npm:/sandbox/.npm" -v "$S/.cache:/sandbox/.cache" \
 "$IMG" node /sandbox/runtime/node_modules/openclaw/openclaw.mjs "$@" < /dev/null; }
oc plugins update codex --dry-run > "$B/codex-dryrun.log" 2>&1
oc plugins update codex > "$B/codex-update.log" 2>&1
oc plugins install @martian-engineering/lossless-claw@1.1.1 --pin --force --accept-capabilities > "$B/lcm-install.log" 2>&1
oc config set plugins.entries.lossless-claw.hooks.allowConversationAccess true --dry-run > "$B/lcm-hook-dryrun.log" 2>&1
oc config set plugins.entries.lossless-claw.hooks.allowConversationAccess true > "$B/lcm-hook.log" 2>&1
oc config validate > "$B/config-validate.log" 2>&1
# An if condition suppresses ERR for the expected warning-only exit status.
# set +e alone does not suppress an ERR trap inside oc().
if oc doctor --lint --json > "$B/doctor-lint.json" 2> "$B/doctor-lint.err"; then
 D_RC=0
else
 D_RC=$?
fi
python3 - "$S" "$B" "$D_RC" <<'PY'
import pathlib,json,sqlite3,sys,hashlib
s,b=map(pathlib.Path,sys.argv[1:3]);before=json.loads((b/'openclaw.json.before').read_text());after=json.loads((s/'config/openclaw.json').read_text())
for k in ['agents','channels','models','gateway','tools','skills','memory']:
 assert before.get(k)==after.get(k), 'unapproved config drift: '+k
assert (s/'nemo.env').read_bytes()==(b/'nemo.env.before').read_bytes(), 'env drift'
e=after['plugins']['entries']['lossless-claw'];assert e['enabled'] and e['hooks']['allowConversationAccess'];assert not e.get('config'), 'rehearsal tuning must not leak into serving config';assert after['plugins']['slots']['contextEngine']=='lossless-claw'
txt=(b/'doctor-lint.json').read_text();d,end=json.JSONDecoder().raw_decode(txt[txt.index('{'):]);assert not any(x.get('severity')=='error' for x in d['findings']), 'doctor errors'
assert int(sys.argv[3]) in [0,1]
db=sqlite3.connect((s/'config/state/openclaw.sqlite').as_uri()+'?mode=ro',uri=True);idx=json.loads(db.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()[0])['index']['installRecords'];assert idx['lossless-claw']['version']=='1.1.1';assert idx['codex']['version']=='2026.10.3';assert db.execute('pragma quick_check').fetchone()[0]=='ok';db.close();print('LIVE_INSTALL_CONFIG_MODEL_ENV_PLUGIN_GATES_OK')
PY
docker rename nemo-sandbox nemo-sandbox-10.2
docker update --restart=no nemo-sandbox-10.2 >/dev/null
docker run -d --name nemo-sandbox --restart=unless-stopped --user 1001:1001 --cpus 1 \
 --memory 2560m --memory-swap 4608m --log-opt max-size=10m --log-opt max-file=3 \
 -p 127.0.0.1:18796:18796 -p 127.0.0.1:8789:8789 --env-file "$S/nemo.env" -e SSL_CERT_FILE="$CA" \
 -v "$CA:$CA:ro" -v "$S/.npm:/sandbox/.npm" -v "$R:/sandbox/runtime:ro" -v "$S/config:/sandbox/config" \
 -v "$S/config/openclaw.json:/sandbox/config/openclaw.json:ro" -v "$S/workspace:/sandbox/workspace" -v "$S/.cache:/sandbox/.cache" \
 "$IMG" node /sandbox/runtime/node_modules/openclaw/openclaw.mjs gateway run --bind lan --port 18796 > "$B/candidate-container-id"
ready=0
for i in $(seq 1 90); do
 if [ "$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:18796/readyz || true)" = 200 ]; then ready=1; break; fi
 [ "$(docker inspect nemo-sandbox --format '{{.State.Running}}')" = true ]
 sleep 2
done
[ "$ready" = 1 ]
chmod 600 "$B"/*
trap - ERR
echo "CUTOVER_10_3_LCM_READY_OK backup=$B"
