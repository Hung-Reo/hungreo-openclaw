#!/bin/bash
# 01 — HƯNG CHẠY. Tắt healthcheck → dừng 2 gateway → backup (config, state sqlite, plugin dirs).
# Không đụng Nemo (Docker nemo-sandbox).
set -euo pipefail
trap 'echo "FAILED ở dòng $LINENO — dừng lại, gửi output cho Claude Code (gateway có thể đang dừng, healthcheck timer đang tắt)"' ERR
export TZ=Asia/Ho_Chi_Minh
B=/home/hung/backups/maint-20261004-plugins
if [ -e "$B" ]; then echo "ABORT: $B đã tồn tại (đã chạy rồi?)"; exit 1; fi

echo "[1/4] stop healthcheck timer"
systemctl --user stop openclaw-healthcheck.timer openclaw-healthcheck.service
systemctl --user is-active openclaw-healthcheck.timer || true

echo "[2/4] stop gateways"
systemctl --user stop openclaw-gateway-hungreo.service openclaw-gateway-suckhoe.service
sleep 6
for s in hungreo suckhoe; do
  st=$(systemctl --user is-active openclaw-gateway-$s.service || true)
  pid=$(systemctl --user show openclaw-gateway-$s.service -p MainPID --value)
  echo "  $s state=$st pid=$pid"
  if [ "$st" = "active" ] || [ "$pid" != "0" ]; then echo "ABORT: $s chưa dừng"; exit 1; fi
done
if pgrep -af "dist/index.js gateway --port (18789|18795)" ; then echo "ABORT: còn process gateway"; exit 1; fi

echo "[3/4] backup -> $B"
mkdir -p "$B"
for p in hungreo suckhoe; do
  d=$HOME/.openclaw-$p
  mkdir -p "$B/$p/state"
  cp -p "$d/openclaw.json" "$B/$p/openclaw.json"
  cp -p "$d"/state/openclaw.sqlite* "$B/$p/state/"
  (cd "$d/npm/projects" && tar czf "$B/$p/npm-projects-plugins.tgz" openclaw-brave-plugin-* openclaw-deepseek-provider-* $( [ $p = hungreo ] && echo "openclaw-parallel-plugin-* openclaw-typesafe-*" ))
done

echo "[4/4] checksums"
(cd "$B" && find . -type f -exec sha256sum {} \; | sort -k2 > SHA256SUMS && cat SHA256SUMS | cut -c1-16,65-)
du -sh "$B"
echo "OK 01 — gateways đang DỪNG. Chạy tiếp 02_update.sh"
