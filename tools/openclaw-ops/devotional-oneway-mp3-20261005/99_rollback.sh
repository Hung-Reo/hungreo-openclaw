#!/bin/bash
# 99 — HƯNG CHẠY, CHỈ KHI CẦN. Trả 3 file script về bản trước 05/10 và xoá cron chép lời MP3.
set -euo pipefail
DST=/home/hung/.openclaw-suckhoe/workspace/scripts
SUF=bak-20261005-pre-oneway-mp3
for f in devotional_content.py devotional-morning-send.sh test_devotional_content.py; do cp -p "$DST/$f.$SUF" "$DST/$f"; done
ID=$(OPENCLAW_STATE_DIR=$HOME/.openclaw-suckhoe /home/hung/bin/openclaw --profile suckhoe cron list --json | python3 -c '
import json,sys; d=json.load(sys.stdin); print(next((j["id"] for j in d.get("jobs",d) if "MP3 Oneway" in (j.get("name") or "")), ""))')
[ -n "$ID" ] && OPENCLAW_STATE_DIR=$HOME/.openclaw-suckhoe /home/hung/bin/openclaw --profile suckhoe cron rm "$ID"
echo "Rollback xong (cache data/devotional-audio giữ lại, vô hại)"
