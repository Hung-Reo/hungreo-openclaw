#!/bin/bash
# 99 — Quay Nemo về 2026.10.1. Đối số: thư mục backup do 20_cutover.sh in ra.
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s -- /home/hung/backups/nemo-upgrade-10.2-<TS>' < 99_rollback.sh
# Không xoá gì: config 10.2 đổi tên config.failed-10.2-<giờ>, container mới đổi tên nemo-sandbox-10.2-failed-<giờ>.
set -u
B=${1:?thiếu thư mục backup}; S=/home/hung/sandbox-nemo; OLD=nemo-sandbox-10.1; TS=$(date +%Y%m%d-%H%M%S)
[ -f "$B/sandbox-nemo-config.tar" ] && ( cd "$B" && sha256sum -c --quiet SHA256SUMS ) || { echo "STOP — backup thiếu hoặc sai checksum"; exit 2; }
docker ps -a --format '{{.Names}}' | grep -qx $OLD || { echo "STOP — không thấy container $OLD"; exit 2; }
docker stop -t 60 nemo-sandbox >/dev/null 2>&1; docker rename nemo-sandbox nemo-sandbox-10.2-failed-$TS 2>/dev/null
docker update --restart=no nemo-sandbox-10.2-failed-$TS >/dev/null 2>&1
cd $S && mv config config.failed-10.2-$TS && tar -xpf "$B/sandbox-nemo-config.tar" || { echo "STOP — khôi phục config lỗi"; exit 1; }
docker rename $OLD nemo-sandbox && docker update --restart=unless-stopped nemo-sandbox >/dev/null && docker start nemo-sandbox >/dev/null
for i in $(seq 1 60); do [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1:18796/readyz)" = 200 ] && { echo "READY ~$((i*5))s"; break; }; sleep 5; done
echo "version: $(docker exec nemo-sandbox node -e 'console.log(require("/sandbox/runtime/node_modules/openclaw/package.json").version)')"
docker ps -a --format '{{.Names}} {{.Status}}' | grep nemo
echo "ROLLBACK_DONE"
