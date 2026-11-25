#!/bin/bash
# 99 — HƯNG CHẠY, CHỈ KHI CẦN. Trả Nemo về đúng trạng thái trước 07/10 (config + state + plugin dirs từ backup).
set -euo pipefail
S=/home/hung/sandbox-nemo
B=/home/hung/backups/nemo-sol-fallback-20261007
[ -f "$B/SHA256SUMS" ] || { echo "ABORT: không thấy backup"; exit 1; }
docker stop -t 60 nemo-sandbox >/dev/null
cp -p "$B/openclaw.json" "$S/config/openclaw.json"
rm -f "$S"/config/state/openclaw.sqlite-wal "$S"/config/state/openclaw.sqlite-shm
cp -p "$B"/openclaw.sqlite* "$S/config/state/"
tar xzf "$B/npm-projects.tgz" -C "$S/config"
docker start nemo-sandbox >/dev/null
sleep 60; docker logs --since 2m nemo-sandbox 2>&1 | grep -c "\[gateway\] ready"
echo "Rollback xong (thư mục plugin codex mới còn trên đĩa nhưng không được dùng)"
