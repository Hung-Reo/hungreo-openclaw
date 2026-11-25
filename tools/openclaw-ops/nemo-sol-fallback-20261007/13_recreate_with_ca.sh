#!/bin/bash
# 13 — HƯNG CHẠY. Tạo lại container Nemo Y HỆT (lệnh từ cutover-9.8.sh) + mount file CA của host (read-only)
# + SSL_CERT_FILE, để binary Codex (Rust) mở được TLS tới chatgpt.com. Container cũ giữ lại tên nemo-sandbox-pre-ca để rollback.
set -uo pipefail
S=/home/hung/sandbox-nemo
CA=/etc/ssl/certs/ca-certificates.crt
[ -f "$CA" ] || { echo "ABORT: host thiếu $CA"; exit 1; }
docker ps -a --format '{{.Names}}' | grep -qx nemo-sandbox-pre-ca && { echo "ABORT: nemo-sandbox-pre-ca đã tồn tại"; exit 1; }

echo "[1/4] dừng + đổi tên container cũ"
docker stop -t 60 nemo-sandbox >/dev/null && docker rename nemo-sandbox nemo-sandbox-pre-ca && docker update --restart=no nemo-sandbox-pre-ca >/dev/null || { echo "ABORT ở bước 1"; docker start nemo-sandbox; exit 1; }

echo "[2/4] tạo container mới (giống hệt + CA)"
if ! docker run -d --name nemo-sandbox --restart unless-stopped --user 1001:1001 \
  --cpus 1 --memory 2560m --memory-swap 4608m --log-opt max-size=10m --log-opt max-file=3 \
  -p 127.0.0.1:18796:18796 -p 127.0.0.1:8789:8789 --env-file $S/nemo.env \
  -e SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt -v $CA:/etc/ssl/certs/ca-certificates.crt:ro \
  -v $S/.npm:/sandbox/.npm -v $S/runtime-9.8:/sandbox/runtime:ro -v $S/config:/sandbox/config \
  -v $S/config/openclaw.json:/sandbox/config/openclaw.json:ro -v $S/workspace:/sandbox/workspace -v $S/.cache:/sandbox/.cache \
  node:24.21.0-bookworm-slim node /sandbox/runtime/node_modules/openclaw/dist/entry.js gateway run --bind lan --port 18796 >/dev/null; then
  echo "RUN FAILED → khôi phục container cũ"; docker rm nemo-sandbox 2>/dev/null; docker rename nemo-sandbox-pre-ca nemo-sandbox
  docker update --restart=unless-stopped nemo-sandbox >/dev/null; docker start nemo-sandbox; exit 2
fi

echo "[3/4] chờ readyz"
for i in $(seq 1 60); do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1:18796/readyz)
  [ "$c" = "200" ] && { echo "  READY sau ~$((i*5))s"; break; }; sleep 5
done
docker exec nemo-sandbox sh -lc 'test -s /etc/ssl/certs/ca-certificates.crt && echo "  CA trong container: OK"'

echo "[4/4] trạng thái"
docker ps -a --format '{{.Names}} {{.Status}}' | grep nemo-sandbox
echo "OK 13 — báo Claude Code chạy UAT Sol"
