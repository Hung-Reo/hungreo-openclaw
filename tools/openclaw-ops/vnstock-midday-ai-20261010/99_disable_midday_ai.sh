#!/bin/bash
# 99 — Tắt AI trưa: bỏ drop-in, daemon-reload. Trưa sau chạy lại code-only. Không xoá artifact/ví 2.
set -u
export XDG_RUNTIME_DIR=/run/user/$(id -u)
U=vnstock-daily-midday.service; F=~/.config/systemd/user/$U.d/zz-midday-ai.conf
[ -e "$F" ] || { echo "Không có $F — AI trưa đang tắt."; exit 0; }
mv "$F" "$F.disabled-$(date +%Y%m%d-%H%M%S)"
systemctl --user daemon-reload
echo "env hiệu lực: '$(systemctl --user show $U -p Environment --value)' (không còn MIDDAY_AI_ENABLE=1)"
