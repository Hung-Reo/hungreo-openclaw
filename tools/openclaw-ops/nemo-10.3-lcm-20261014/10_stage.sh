#!/usr/bin/env bash
# Authorized target: Nemo only. Does not mount or mutate live config/workspace.
set -Eeuo pipefail
S=/home/hung/sandbox-nemo
R=$S/runtime-10.3
T=$S/ops-10.3-lcm-20261014
IMG=node:24.21.0-bookworm-slim
CA=/etc/ssl/certs/ca-certificates.crt
[ "$(hostname)" = srv1367812 ]
[ "$(free -m | awk '/^Mem:/{print $7}')" -ge 1500 ]
[ ! -e "$R" ] || { echo 'STOP: candidate path exists; inspect before resume'; exit 2; }
mkdir -m 700 "$R"
mkdir -p "$T/stage-home"
chmod 700 "$T" "$T/stage-home"
docker run --rm --name nemo-stage-103-lcm --user 1001:1001 --cpus 1 --memory 1100m --memory-swap 1100m \
 -e HOME=/sandbox/stage-home -e NODE_OPTIONS=--max-old-space-size=640 -e SSL_CERT_FILE="$CA" \
 -v "$CA:$CA:ro" -v "$R:/sandbox/runtime" -v "$T/stage-home:/sandbox/stage-home" \
 "$IMG" sh -eu -c 'npm install --prefix /sandbox/runtime --no-audit --no-fund openclaw@2026.10.3; cd /sandbox/runtime/node_modules/openclaw; if [ -e .openclaw-lifecycle-pending ]; then node scripts/postinstall-bundled-plugins.mjs; fi' \
 > "$T/stage-core.log" 2>&1
python3 - "$R" <<'PY'
import pathlib,json,sys
r=pathlib.Path(sys.argv[1]); p=json.loads((r/'node_modules/openclaw/package.json').read_text()); lock=json.loads((r/'package-lock.json').read_text())
assert p['version']=='2026.10.3'
assert lock['packages']['node_modules/openclaw']['integrity']=='sha512-ncl6LntMlf76K39LFhVrDXQTbaGNAG5j52f7PL5P8vIn0knWmCrvfAe9DHMslFq+47HeOWBH2CBYQH8zEb+UAA=='
assert not (r/'node_modules/openclaw/.openclaw-lifecycle-pending').exists()
print('CORE_STAGE_VERSION_INTEGRITY_LIFECYCLE_OK')
PY
docker run --rm --user 1001:1001 --memory 700m --memory-swap 700m -e HOME=/tmp -v "$R:/sandbox/runtime:ro" \
 "$IMG" node /sandbox/runtime/node_modules/openclaw/openclaw.mjs --version > "$T/core-version.log" 2>&1
for topic in 'plugins install' 'plugins update' 'config set' 'agent'; do
 name=${topic// /-}
 docker run --rm --user 1001:1001 --memory 700m --memory-swap 700m -e HOME=/tmp -v "$R:/sandbox/runtime:ro" \
 "$IMG" node /sandbox/runtime/node_modules/openclaw/openclaw.mjs $topic --help > "$T/help-$name.txt" 2>&1
done
echo CORE_STAGE_OK
