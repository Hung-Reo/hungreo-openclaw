#!/usr/bin/env bash
# Restore only this Nemo upgrade's backup, retaining failed candidate state.
set -Eeuo pipefail
S=/home/hung/sandbox-nemo; T=$S/ops-10.3-lcm-20261014
B=${1:-$(cat "$T/backup-path")}; TS=$(date +%Y%m%d-%H%M%S)
[ "$(hostname)" = srv1367812 ]
[ -f "$B/config.tar" ] && [ -f "$B/workspace.tar" ]
(cd "$B" && sha256sum -c SHA256SUMS)
if docker inspect nemo-rehearsal-103-lcm >/dev/null 2>&1; then docker stop -t 45 nemo-rehearsal-103-lcm >/dev/null; fi
if docker inspect nemo-sandbox >/dev/null 2>&1; then
 runtime=$(docker inspect nemo-sandbox --format '{{range .Mounts}}{{if eq .Destination "/sandbox/runtime"}}{{.Source}}{{end}}{{end}}')
 docker stop -t 60 nemo-sandbox >/dev/null
 if [ "$runtime" = "$S/runtime-10.3" ]; then
  docker rename nemo-sandbox "nemo-sandbox-failed-10.3-lcm-$TS"
  docker update --restart=no "nemo-sandbox-failed-10.3-lcm-$TS" >/dev/null
 elif [ "$runtime" != "$S/runtime-10.2" ]; then echo 'STOP: unexpected serving runtime'; exit 2; fi
fi
mv "$S/config" "$S/config.failed-10.3-lcm-$TS"
mv "$S/workspace" "$S/workspace.failed-10.3-lcm-$TS"
tar -C "$S" -xpf "$B/config.tar"
tar -C "$S" -xpf "$B/workspace.tar"
if ! docker inspect nemo-sandbox >/dev/null 2>&1; then docker rename nemo-sandbox-10.2 nemo-sandbox; fi
docker update --restart=unless-stopped nemo-sandbox >/dev/null
docker start nemo-sandbox >/dev/null
for i in $(seq 1 90); do
 if [ "$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:18796/readyz || true)" = 200 ]; then
  [ "$(docker exec nemo-sandbox node -e 'console.log(require("/sandbox/runtime/node_modules/openclaw/package.json").version)')" = 2026.10.2 ]
  echo ROLLBACK_10_2_READY_OK; exit 0
 fi
 sleep 2
done
echo ROLLBACK_NOT_READY; exit 1
