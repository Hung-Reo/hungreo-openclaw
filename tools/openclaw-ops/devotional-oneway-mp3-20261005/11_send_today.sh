#!/bin/bash
# 11 — HƯNG CHẠY sau khi Claude Code xác nhận bước 10. GỬI THẬT tĩnh nguyện 05/10 (gửi bù) cho Minh Trân + Hưng (GO Q3).
# Có send guard: chạy lại sẽ in DEVOTIONAL_ALREADY_SENT, không gửi trùng.
set -uo pipefail
export TZ=Asia/Ho_Chi_Minh
cd /home/hung/.openclaw-suckhoe/workspace
DEVOTIONAL_LATE=1 DEVOTIONAL_ALERT_AFTER_HHMM=2400 timeout 400 bash scripts/devotional-morning-send.sh 2>/tmp/devotional-send-today.err
echo "exit=$?"
grep -E "DEVOTIONAL_" /tmp/devotional-send-today.err
python3 scripts/bsy_send_guard.py status --job-id devotional-morning --date-key 2026-10-05 | sed -E 's/[0-9]{10}/<id>/g'
