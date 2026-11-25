#!/usr/bin/env bash
# Upgrade Nemo (nemo-sandbox) from OpenClaw 2026.10.3 -> 2026.10.4 (latest), keeping LCM 1.1.1.
set -Eeuo pipefail
umask 077

S=/home/hung/sandbox-nemo
R=$S/runtime-10.4
T=$S/ops-10.4-20261018
IMG=node:24.21.0-bookworm-slim
CA=/etc/ssl/certs/ca-certificates.crt
TS=$(TZ=Asia/Ho_Chi_Minh date +%Y%m%d-%H%M%S)
B=/home/hung/backups/nemo-10.4-$TS

[ "$(hostname)" = srv1367812 ]
[ -f "$R/node_modules/openclaw/package.json" ]
[ "$(node -e 'console.log(require("/home/hung/sandbox-nemo/runtime-10.4/node_modules/openclaw/package.json").version)')" = "2026.10.4" ]
[ "$(docker exec nemo-sandbox node -e 'console.log(require("/sandbox/runtime/node_modules/openclaw/package.json").version)')" = "2026.10.3" ]

mkdir -p -m 700 "$B" "$T"
printf '%s\n' "$B" > "$T/backup-path"

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
python3 - "$B" <<'PY'
import subprocess, pathlib, json, sys
b = pathlib.Path(sys.argv[1])
out = {}
for p in ['hungreo', 'suckhoe']:
    out[p] = {k: subprocess.check_output(['systemctl', '--user', 'show', f'openclaw-gateway-{p}.service', '-p', k, '--value'], text=True).strip() for k in ['MainPID', 'NRestarts', 'ActiveState']}
(b / 'unaffected-services.json').write_text(json.dumps(out))
PY

docker inspect nemo-sandbox > "$B/container-inspect.json"
cp -p "$S/config/openclaw.json" "$B/openclaw.json.before"
cp -p "$S/nemo.env" "$B/nemo.env.before"

echo "== [1] Stop nemo-sandbox & backup to $B =="
docker stop -t 60 nemo-sandbox >/dev/null
on_backup_err() {
  trap - ERR
  echo "BACKUP_FAILED_RESTARTING_10_3"
  docker start nemo-sandbox >/dev/null || true
  exit 1
}
trap on_backup_err ERR

tar -C "$S" -cpf "$B/config.tar" config
tar -C "$S" -cpf "$B/workspace.tar" workspace
(cd "$B" && sha256sum config.tar workspace.tar > SHA256SUMS && sha256sum -c --quiet SHA256SUMS)
chmod 600 "$B"/*
echo "NEMO_BACKUP_OK=$B"

on_cutover_err() {
  trap - ERR
  echo "CUTOVER_FAILED_ROLLING_BACK_TO_10_3 backup=$B"
  bash "$T/99_rollback.sh" "$B"
  exit 1
}
trap on_cutover_err ERR

oc() {
  docker run --rm --user 1001:1001 --cpus 1 --memory 1300m --memory-swap 1300m \
    --env-file "$S/nemo.env" -e HOME=/sandbox/config -e OPENCLAW_STATE_DIR=/sandbox/config \
    -e OPENCLAW_CONFIG_PATH=/sandbox/config/openclaw.json -e SSL_CERT_FILE="$CA" \
    -e NODE_OPTIONS=--max-old-space-size=640 \
    -v "$CA:$CA:ro" -v "$R:/sandbox/runtime:ro" -v "$S/config:/sandbox/config" \
    -v "$S/workspace:/sandbox/workspace" -v "$S/.npm:/sandbox/.npm" -v "$S/.cache:/sandbox/.cache" \
    "$IMG" node /sandbox/runtime/node_modules/openclaw/openclaw.mjs "$@" < /dev/null
}

echo "== [2] Update @openclaw/codex@2026.10.4 & validate config =="
oc plugins update "@openclaw/codex@2026.10.4" --dry-run > "$B/codex-dryrun.log" 2>&1
oc plugins update "@openclaw/codex@2026.10.4" > "$B/codex-update.log" 2>&1
oc config validate > "$B/config-validate.log" 2>&1

python3 - "$S" "$B" <<'PY'
import pathlib, json, sqlite3, sys
s, b = map(pathlib.Path, sys.argv[1:3])
before = json.loads((b / 'openclaw.json.before').read_text())
after = json.loads((s / 'config/openclaw.json').read_text())
for k in ['agents', 'channels', 'models', 'gateway', 'tools', 'skills', 'memory']:
    assert before.get(k) == after.get(k), 'unapproved config drift: ' + k
assert (s / 'nemo.env').read_bytes() == (b / 'nemo.env.before').read_bytes(), 'env drift'
e = after['plugins']['entries']['lossless-claw']
assert e['enabled'] and e['hooks']['allowConversationAccess']
assert after['plugins']['slots']['contextEngine'] == 'lossless-claw'

db = sqlite3.connect((s / 'config/state/openclaw.sqlite').as_uri() + '?mode=ro', uri=True)
idx = json.loads(db.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()[0])['index']['installRecords']
assert idx['lossless-claw']['version'] == '1.1.1', idx['lossless-claw']
assert idx['codex']['version'] == '2026.10.4', idx['codex']
assert db.execute('pragma quick_check').fetchone()[0] == 'ok'
db.close()

lcmdb = sqlite3.connect((s / 'config/lcm.db').as_uri() + '?mode=ro', uri=True)
assert lcmdb.execute('pragma quick_check').fetchone()[0] == 'ok'
lcmdb.close()
print('NEMO_10_4_CONFIG_AND_SQLITE_GATES_OK')
PY

echo "== [3] Switch container to runtime-10.4 =="
if docker inspect nemo-sandbox-10.3 >/dev/null 2>&1; then
  docker rm -f nemo-sandbox-10.3 >/dev/null
fi
docker rename nemo-sandbox nemo-sandbox-10.3
docker update --restart=no nemo-sandbox-10.3 >/dev/null

docker run -d --name nemo-sandbox --restart=unless-stopped --user 1001:1001 --cpus 1 \
  --memory 2560m --memory-swap 4608m --log-opt max-size=10m --log-opt max-file=3 \
  -p 127.0.0.1:18796:18796 -p 127.0.0.1:8789:8789 --env-file "$S/nemo.env" -e SSL_CERT_FILE="$CA" \
  -v "$CA:$CA:ro" -v "$S/.npm:/sandbox/.npm" -v "$R:/sandbox/runtime:ro" -v "$S/config:/sandbox/config" \
  -v "$S/config/openclaw.json:/sandbox/config/openclaw.json:ro" -v "$S/workspace:/sandbox/workspace" -v "$S/.cache:/sandbox/.cache" \
  "$IMG" node /sandbox/runtime/node_modules/openclaw/openclaw.mjs gateway run --bind lan --port 18796 > "$B/candidate-container-id"

ready=0
for i in $(seq 1 90); do
  if [ "$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:18796/readyz || true)" = 200 ]; then
    ready=1
    break
  fi
  [ "$(docker inspect nemo-sandbox --format '{{.State.Running}}')" = true ]
  sleep 2
done
[ "$ready" = 1 ]

python3 - "$B" <<'PY'
import subprocess, pathlib, json, sys
b = pathlib.Path(sys.argv[1])
before = json.loads((b / 'unaffected-services.json').read_text())
after = {}
for p in ['hungreo', 'suckhoe']:
    after[p] = {k: subprocess.check_output(['systemctl', '--user', 'show', f'openclaw-gateway-{p}.service', '-p', k, '--value'], text=True).strip() for k in ['MainPID', 'NRestarts', 'ActiveState']}
assert before == after, f'unaffected service state changed: {before} vs {after}'
print('UNAFFECTED_SERVICES_UNCHANGED_OK')
PY

chmod 600 "$B"/*
trap - ERR
echo "CUTOVER_NEMO_10_4_READY_OK backup=$B"
