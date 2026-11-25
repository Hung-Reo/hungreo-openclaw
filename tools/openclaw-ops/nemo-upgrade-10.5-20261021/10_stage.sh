#!/usr/bin/env bash
# 10 — HƯNG CHẠY. Chỉ tạo runtime mới /home/hung/sandbox-nemo/runtime-10.5; KHÔNG đụng container/config/workspace live.
# ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash /home/hung/sandbox-nemo/ops-10.5-20261021/10_stage.sh'
set -Eeuo pipefail
S=/home/hung/sandbox-nemo
R=$S/runtime-10.5
T=$S/ops-10.5-20261021
IMG=node:24.21.0-bookworm-slim
CA=/etc/ssl/certs/ca-certificates.crt
INTEGRITY='sha512-9rCuXMweqVKZIK3KBtGcLzesz9G6+FmQ30lvwomRhmcNWDcOtlBoqdLbPditoJMuTP55jPqXpt1AA0L8tSzFHg=='
[ "$(hostname)" = srv1367812 ] || { echo "ABORT: sai host"; exit 1; }
[ "$(free -m | awk '/^Mem:/{print $7}')" -ge 1500 ] || { echo "ABORT: RAM available < 1500 MiB"; exit 1; }
[ "$(df --output=avail -BG / | tail -1 | tr -dc 0-9)" -ge 5 ] || { echo "ABORT: disk < 5G"; exit 1; }
if [ -f "$R/node_modules/openclaw/package.json" ] && [ "$(jq -r .version "$R/node_modules/openclaw/package.json")" = 2026.10.5 ] && [ ! -e "$R/node_modules/openclaw/.openclaw-lifecycle-pending" ]; then
  echo "SKIP: runtime-10.5 đã stage xong"; exit 0; fi
[ ! -e "$R" ] || { echo "STOP: $R tồn tại nhưng chưa hoàn chỉnh — báo Claude, không tự xoá"; exit 2; }
mkdir -m 700 "$R"; mkdir -p "$T/stage-home"; chmod 700 "$T" "$T/stage-home"
docker run --rm --name nemo-stage-105 --user 1001:1001 --cpus 1 --memory 1100m --memory-swap 1100m \
  -e HOME=/sandbox/stage-home -e NODE_OPTIONS=--max-old-space-size=640 -e SSL_CERT_FILE="$CA" \
  -v "$CA:$CA:ro" -v "$R:/sandbox/runtime" -v "$T/stage-home:/sandbox/stage-home" \
  "$IMG" sh -eu -c 'npm install --prefix /sandbox/runtime --no-audit --no-fund openclaw@2026.10.5; cd /sandbox/runtime/node_modules/openclaw; if [ -e .openclaw-lifecycle-pending ]; then node scripts/postinstall-bundled-plugins.mjs; fi' \
  > "$T/stage-core.log" 2>&1
python3 - "$R" "$INTEGRITY" <<'PY'
import pathlib,json,sys
r=pathlib.Path(sys.argv[1]); p=json.loads((r/'node_modules/openclaw/package.json').read_text()); lock=json.loads((r/'package-lock.json').read_text())
assert p['version']=='2026.10.5', p['version']
assert lock['packages']['node_modules/openclaw']['integrity']==sys.argv[2], 'integrity mismatch'
assert not (r/'node_modules/openclaw/.openclaw-lifecycle-pending').exists(), 'postinstall chưa chạy'
print('CORE_STAGE_VERSION_INTEGRITY_LIFECYCLE_OK')
PY
docker run --rm --user 1001:1001 --memory 700m --memory-swap 700m -e HOME=/tmp -v "$R:/sandbox/runtime:ro" \
  "$IMG" node /sandbox/runtime/node_modules/openclaw/openclaw.mjs --version > "$T/core-version.log" 2>&1
cat "$T/core-version.log"
for topic in 'plugins update' 'config validate'; do
  docker run --rm --user 1001:1001 --memory 700m --memory-swap 700m -e HOME=/tmp -v "$R:/sandbox/runtime:ro" \
    "$IMG" node /sandbox/runtime/node_modules/openclaw/openclaw.mjs $topic --help > "$T/help-${topic// /-}.txt" 2>&1 || true
done
grep -q -- '--dry-run' "$T/help-plugins-update.txt" || { echo "ABORT: 10.5 'plugins update' không còn --dry-run"; exit 1; }
du -sh "$R"
echo "OK 10 — CORE_STAGE_OK runtime-10.5"
