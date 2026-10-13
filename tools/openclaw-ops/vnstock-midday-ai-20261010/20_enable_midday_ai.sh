#!/bin/bash
# 20 — HƯNG CHẠY. Bật AI trưa vn-stock (Hưng GO 11/10: chạy từ thứ Hai 12/10, review cuối ngày).
# Chỉ thêm 1 drop-in Environment=MIDDAY_AI_ENABLE=1 cho vnstock-daily-midday.service + daemon-reload.
# Không đổi timer (vẫn 12:45), không restart gì, không chạy midday ngay.
# DRY_RUN=1 → chỉ kiểm điều kiện.
# Chạy: ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 20_enable_midday_ai.sh
# Rollback: ssh ... 'bash -s' < 99_disable_midday_ai.sh
set -u
export TZ=Asia/Ho_Chi_Minh XDG_RUNTIME_DIR=/run/user/$(id -u)
P=~/projects/vn-stock-agent; U=vnstock-daily-midday.service; D=~/.config/systemd/user/$U.d; F=$D/zz-midday-ai.conf
EXPECT=${EXPECT_HEAD:-3aeaeeb}
head=$(git -C $P rev-parse --short HEAD); dirty=$(git -C $P status --porcelain | wc -l)
echo "production HEAD=$head dirty=$dirty (cần $EXPECT, sạch)"
[ "$head" = "$EXPECT" ] && [ "$dirty" = 0 ] || { echo "STOP — production chưa ff đúng $EXPECT hoặc không sạch."; exit 2; }
grep -q 'MIDDAY_AI_ENABLE:-0}" = "1"' $P/scripts/daily_midday.sh || { echo "STOP — script chưa có nhánh MIDDAY_AI_ENABLE."; exit 2; }
grep -q '"spending_mode": "unbounded_owner_go"' $P/config/research-first.json || { echo "STOP — config Jev chưa là unbounded_owner_go."; exit 2; }
[ -e "$F" ] && { echo "Đã bật từ trước: $F"; cat "$F"; exit 0; }
echo "timer: $(systemctl --user show vnstock-daily-midday.timer -p NextElapseUSecRealtime --value 2>/dev/null) ($(systemctl --user is-enabled vnstock-daily-midday.timer))"
if [ "${DRY_RUN:-0}" = 1 ]; then echo "DRY_RUN — sẽ tạo $F với Environment=MIDDAY_AI_ENABLE=1"; exit 0; fi
mkdir -p "$D"
printf '[Service]\n# Hưng GO 2026-10-11: AI trưa midday/v1 + ví AI_FOLLOW_MIDDAY, bắt đầu 12/10\nEnvironment=MIDDAY_AI_ENABLE=1\n' > "$F"
systemctl --user daemon-reload
echo "drop-in: $F"; cat "$F"
echo "env hiệu lực: $(systemctl --user show $U -p Environment --value)"
echo "OK 20 — lượt đầu: thứ Hai 12/10 12:45. Claude Code review cuối ngày (receipt Sol included, không OpenRouter, giờ gửi, Jev)."
