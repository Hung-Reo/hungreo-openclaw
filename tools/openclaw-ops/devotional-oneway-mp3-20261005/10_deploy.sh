#!/bin/bash
# 10 — HƯNG CHẠY. Deploy nguồn MP3 Oneway + cảnh báo thiếu nguồn cho tĩnh nguyện Suckhoe (GO Q1–Q2 05/10).
# Không restart gateway, không gửi tin. Tạo cron chép lời 04:10/04:40. Tự rollback file nếu test fail.
set -euo pipefail
trap 'echo "FAILED ở dòng $LINENO — gửi output cho Claude Code"' ERR
export TZ=Asia/Ho_Chi_Minh
SRC=/tmp/devotional-deploy-20261005
DST=/home/hung/.openclaw-suckhoe/workspace/scripts
SUF=bak-20261005-pre-oneway-mp3
OC=/home/hung/bin/openclaw

echo "[1/5] kiểm sha file deploy"
(cd "$SRC" && sha256sum -c - <<'SUMS'
19922826234623d64044e3dec932ff2cbede5f6fc867208ee77cad11dc8a7d60  devotional_content.py
f1f7858ee4821903e1d6487be1f88b656066dd215c81bf957caaa61c14b92742  devotional-morning-send.sh
fa39e9578f985b5269f55037c5cb2c1a8e5b177148d947fb0613ef22b4601837  test_devotional_content.py
SUMS
)

echo "[2/5] backup + copy"
for f in devotional_content.py devotional-morning-send.sh test_devotional_content.py; do
  [ -e "$DST/$f.$SUF" ] || cp -p "$DST/$f" "$DST/$f.$SUF"
  cp "$SRC/$f" "$DST/$f"
done
ls -l "$DST"/*."$SUF"

echo "[3/5] test tại thư mục production"
TEST_OUT="$(cd "$DST" && python3 test_devotional_content.py 2>&1 || true)"
printf '%s\n' "$TEST_OUT" | tail -3
if ! printf '%s\n' "$TEST_OUT" | tail -1 | grep -qx "OK"; then
  for f in devotional_content.py devotional-morning-send.sh test_devotional_content.py; do cp -p "$DST/$f.$SUF" "$DST/$f"; done
  echo "ROLLED BACK — test fail"; exit 1
fi

echo "[4/5] cache bản chép lời 05/10 (từ staging, đã kiểm)"
mkdir -p /home/hung/.openclaw-suckhoe/workspace/data/devotional-audio
cp /tmp/devotional-stage-20261005/cache/2026-10-05.json /home/hung/.openclaw-suckhoe/workspace/data/devotional-audio/
ls -l /home/hung/.openclaw-suckhoe/workspace/data/devotional-audio/

echo "[5/5] cron chép lời MP3 04:10 + 04:40 (chạy lại là no-op nếu đã có cache)"
OPENCLAW_STATE_DIR=$HOME/.openclaw-suckhoe OPENCLAW_CONFIG_PATH=$HOME/.openclaw-suckhoe/openclaw.json \
  $OC --profile suckhoe cron add \
  --name "Tĩnh nguyện: chép lời MP3 Oneway 04:10/04:40" \
  --declaration-key devotional-oneway-audio-prefetch \
  --cron "10,40 4 * * *" --tz Asia/Ho_Chi_Minh --exact \
  --session isolated --no-deliver \
  --command-argv '["python3","/home/hung/.openclaw-suckhoe/workspace/scripts/devotional_content.py","--prefetch-audio"]' \
  --command-cwd /home/hung/.openclaw-suckhoe/workspace \
  --timeout-seconds 1600 --no-output-timeout-seconds 1600 --output-max-bytes 4000
echo "OK 10 — báo Claude Code kiểm, rồi mới chạy 11_send_today.sh"
