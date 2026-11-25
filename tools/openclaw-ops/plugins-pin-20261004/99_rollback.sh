#!/bin/bash
# 99 — HƯNG CHẠY, CHỈ KHI CẦN. Hai mức:
#   bash -s soft  : cài lại plugin 2026.9.6 bằng CLI (không đụng sqlite/config) + trả google-sheets về
#   bash -s hard  : khôi phục nguyên trạng openclaw.json + state sqlite + thư mục plugin từ backup 01
#                   (mất dữ liệu state ghi sau lúc backup, vd tin nhắn/cron state trong cửa sổ bảo trì)
# Chạy: ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s soft' < 99_rollback.sh
set -euo pipefail
export TZ=Asia/Ho_Chi_Minh
MODE=${1:-}
OC=/home/hung/bin/openclaw
B=/home/hung/backups/maint-20261004-plugins
[ "$MODE" = soft ] || [ "$MODE" = hard ] || { echo "Usage: bash -s soft|hard"; exit 1; }
[ -f "$B/SHA256SUMS" ] || { echo "ABORT: không thấy backup $B"; exit 1; }

systemctl --user stop openclaw-healthcheck.timer openclaw-healthcheck.service
systemctl --user stop openclaw-gateway-hungreo.service openclaw-gateway-suckhoe.service
sleep 6

if [ "$MODE" = soft ]; then
  for p in hungreo suckhoe; do
    specs="@openclaw/brave-plugin@2026.9.6 @openclaw/deepseek-provider@2026.9.6"
    [ $p = hungreo ] && specs="$specs @openclaw/parallel-plugin@2026.9.6 @openclaw/typesafe@2026.9.6"
    OPENCLAW_STATE_DIR=$HOME/.openclaw-$p OPENCLAW_CONFIG_PATH=$HOME/.openclaw-$p/openclaw.json \
      timeout 300 $OC --profile $p plugins update $specs < /dev/null
  done
else
  for p in hungreo suckhoe; do
    d=$HOME/.openclaw-$p
    cp -p "$B/$p/openclaw.json" "$d/openclaw.json"
    rm -f "$d"/state/openclaw.sqlite-wal "$d"/state/openclaw.sqlite-shm
    cp -p "$B/$p"/state/openclaw.sqlite* "$d/state/"
    tar xzf "$B/$p/npm-projects-plugins.tgz" -C "$d/npm/projects"
  done
fi

if [ -d "$B/skills/google-sheets" ] && [ ! -e /home/hung/.openclaw-hungreo/workspace/skills/google-sheets ]; then
  mv "$B/skills/google-sheets" /home/hung/.openclaw-hungreo/workspace/skills/google-sheets
fi

for s in suckhoe hungreo; do systemctl --user restart openclaw-gateway-$s.service; sleep 90; echo "$s $(systemctl --user is-active openclaw-gateway-$s.service)"; done
systemctl --user start openclaw-healthcheck.timer
echo "Rollback $MODE xong — báo Claude Code kiểm lại (04_verify.sh)"
