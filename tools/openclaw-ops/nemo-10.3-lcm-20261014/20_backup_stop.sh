#!/usr/bin/env bash
# Stop only Nemo and preserve its exact state before any live installation.
set -Eeuo pipefail
S=/home/hung/sandbox-nemo; T=$S/ops-10.3-lcm-20261014
[ "$(hostname)" = srv1367812 ]
[ ! -e "$T/backup-path" ] || [ "${RETRY:-0}" = 1 ] || { echo 'STOP: backup marker exists; explicit retry needed'; exit 2; }
[ "$(docker exec nemo-sandbox node -e 'console.log(require("/sandbox/runtime/node_modules/openclaw/package.json").version)')" = 2026.10.2 ]
[ -f "$T/rehearsal-doctor.json" ]
python3 - "$T" <<'PY'
import pathlib,json,sqlite3,sys
p=pathlib.Path(sys.argv[1]);s=(p/'rehearsal-doctor.json').read_text();d,end=json.JSONDecoder().raw_decode(s[s.index('{'):]);assert not any(x.get('severity')=='error' for x in d['findings']), 'doctor has errors'
b=p/'rehearsal-config';c=json.loads((b/'openclaw.json').read_text());assert c['plugins']['slots']['contextEngine']=='lossless-claw';assert c['plugins']['entries']['lossless-claw']['hooks']['allowConversationAccess']
db=sqlite3.connect((b/'state/openclaw.sqlite').as_uri()+'?mode=ro',uri=True);idx=json.loads(db.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()[0])['index']['installRecords'];assert idx['lossless-claw']['version']=='1.1.1';assert idx['codex']['version']=='2026.10.3';print('REHEARSAL_SCHEMA_PLUGIN_GATES_OK')
PY
B=/home/hung/backups/nemo-10.3-lcm-$(date +%Y%m%d-%H%M%S)
mkdir -m 700 "$B"
printf '%s\n' "$B" > "$T/backup-path"
docker inspect nemo-sandbox > "$B/container-inspect.json"
cp -p "$S/config/openclaw.json" "$B/openclaw.json.before"
cp -p "$S/nemo.env" "$B/nemo.env.before"
chmod 600 "$B"/*
python3 - "$B" <<'PY'
import subprocess,pathlib,json,sys
b=pathlib.Path(sys.argv[1]);out={}
for p in ['hungreo','suckhoe']:
 out[p]={k:subprocess.check_output(['systemctl','--user','show',f'openclaw-gateway-{p}.service','-p',k,'--value'],text=True).strip() for k in ['MainPID','NRestarts','ActiveState']}
(b/'unaffected-services.json').write_text(json.dumps(out))
PY
docker stop -t 60 nemo-sandbox >/dev/null
trap 'echo BACKUP_FAILED_RESTARTING_ORIGINAL; docker start nemo-sandbox >/dev/null' ERR
tar -C "$S" -cpf "$B/config.tar" config
tar -C "$S" -cpf "$B/workspace.tar" workspace
(cd "$B" && sha256sum config.tar workspace.tar > SHA256SUMS && sha256sum -c SHA256SUMS)
chmod 600 "$B"/*
trap - ERR
echo "NEMO_STOPPED_BACKUP_VERIFIED=$B"
