#!/usr/bin/env bash
# Rollback Nemo (nemo-sandbox) from 2026.10.4 back to 2026.10.3.
set -Eeuo pipefail
S=/home/hung/sandbox-nemo
T=$S/ops-10.4-20261018
B=${1:-$(cat "$T/backup-path")}
TS=$(TZ=Asia/Ho_Chi_Minh date +%Y%m%d-%H%M%S)

[ "$(hostname)" = srv1367812 ]
[ -f "$B/config.tar" ] && [ -f "$B/workspace.tar" ]
(cd "$B" && sha256sum -c --quiet SHA256SUMS)

if docker inspect nemo-sandbox >/dev/null 2>&1; then
  runtime=$(docker inspect nemo-sandbox --format '{{range .Mounts}}{{if eq .Destination "/sandbox/runtime"}}{{.Source}}{{end}}{{end}}')
  docker stop -t 60 nemo-sandbox >/dev/null || true
  if [ "$runtime" = "$S/runtime-10.4" ]; then
    docker rename nemo-sandbox "nemo-sandbox-failed-10.4-$TS"
    docker update --restart=no "nemo-sandbox-failed-10.4-$TS" >/dev/null
  fi
fi

mv "$S/config" "$S/config.failed-10.4-$TS"
mv "$S/workspace" "$S/workspace.failed-10.4-$TS"
tar -C "$S" -xpf "$B/config.tar"
tar -C "$S" -xpf "$B/workspace.tar"

if ! docker inspect nemo-sandbox >/dev/null 2>&1; then
  docker rename nemo-sandbox-10.3 nemo-sandbox
fi
docker update --restart=unless-stopped nemo-sandbox >/dev/null
docker start nemo-sandbox >/dev/null

for i in $(seq 1 90); do
  if [ "$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:18796/readyz || true)" = 200 ]; then
    [ "$(docker exec nemo-sandbox node -e 'console.log(require("/sandbox/runtime/node_modules/openclaw/package.json").version)')" = "2026.10.3" ]
    echo "ROLLBACK_10_3_READY_OK"
    exit 0
  fi
  sleep 2
done
echo "ROLLBACK_NOT_READY"
exit 1
