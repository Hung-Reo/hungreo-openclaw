#!/bin/bash
# 99 — HƯNG CHẠY, CHỈ KHI CẦN. Index mới đã dựng nên KHÔNG chỉ "config unset" (memory_search sẽ rỗng — lesson Suckhoe 04/10).
# Đường lui luôn dựng được, không cần mạng/khoá: provider "none" (tìm theo từ khoá) rồi dựng lại index.
set -euo pipefail
P=/home/hung/.openclaw-hungreo
run() { OPENCLAW_STATE_DIR=$P OPENCLAW_CONFIG_PATH=$P/openclaw.json /home/hung/bin/openclaw --profile hungreo "$@"; }
run config set agents.entries.main.memory.search.provider none
run memory index --force --agent main 2>&1 | tail -3
run memory status --agent main 2>&1 | grep -E "Provider|Indexed|Dirty"
echo "Rollback xong. Khôi phục hẳn bản cũ (config + DB) cần dừng gateway — hỏi Claude Code: /home/hung/backups/hungreo-embeddings-20261006/"
