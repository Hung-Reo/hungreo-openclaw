#!/bin/bash
# 98 — HƯNG CHẠY, CHỈ KHI CẦN. Bỏ container mới (có CA), trả lại container cũ nemo-sandbox-pre-ca. Config/state dùng chung, không đổi.
set -euo pipefail
docker ps -a --format '{{.Names}}' | grep -qx nemo-sandbox-pre-ca || { echo "ABORT: không có nemo-sandbox-pre-ca"; exit 1; }
docker stop -t 60 nemo-sandbox >/dev/null || true
docker rm nemo-sandbox
docker rename nemo-sandbox-pre-ca nemo-sandbox
docker update --restart=unless-stopped nemo-sandbox >/dev/null
docker start nemo-sandbox >/dev/null
docker ps --format '{{.Names}} {{.Status}}' | grep nemo-sandbox
