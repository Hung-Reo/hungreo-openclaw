#!/bin/bash
# 99 — HƯNG CHẠY nếu cần: ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s <BACKUP>' < 99_rollback.sh
# Trả AGENTS.md của Rùa về bản backup do 10_apply.sh in ra (BACKUP=...). Sau đó gửi /new.
set -euo pipefail
F=$HOME/.openclaw-hungreo/workspace/AGENTS.md
B=${1:?cần đường dẫn BACKUP do 10_apply.sh in ra}
case "$B" in "$F".bak-*-pre-plugin-version-note) ;; *) echo "ABORT: $B không phải backup của việc này"; exit 1 ;; esac
[ -f "$B" ] || { echo "ABORT: không thấy $B"; exit 1; }
[ "$(sha256sum "$B" | cut -c1-8)" = 05de36e7 ] || { echo "ABORT: backup không đúng bản gốc 05de36e7"; exit 1; }
grep -qF '<!-- plugin-version-check 2026-10-18 -->' "$F" || { echo "ABORT: AGENTS.md hiện không có ghi chú này — không ghi đè"; exit 1; }
cp -p "$F" "$F.bak-$(date +%Y%m%d-%H%M%S)-pre-rollback-plugin-version-note"
cp -p "$B" "$F.tmp.rb" && mv "$F.tmp.rb" "$F"
if [ "$(sha256sum "$F" | cut -c1-8)" = "$(sha256sum "$B" | cut -c1-8)" ]; then echo "OK 99 — sha $(sha256sum "$F" | cut -c1-8); gửi /new cho Rùa"; else echo "FAILED: hash lệch"; exit 1; fi
