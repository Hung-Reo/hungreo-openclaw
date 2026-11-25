#!/bin/bash
# 10 — Thêm /swapfile2 2 GiB (giữ nguyên /swapfile 2 GiB đang dùng) → tổng swap 4 GiB.
# HƯNG CHẠY (cần sudo có mật khẩu → phải có TTY, nên chép script lên rồi chạy):
#   scp -i ~/.ssh/hostinger_kvm2 10_swap.sh 99_rollback.sh hung@72.61.123.33:/home/hung/ops-swap/
#   ssh -t -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash /home/hung/ops-swap/10_swap.sh check'   # không ghi gì
#   ssh -t -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash /home/hung/ops-swap/10_swap.sh apply'
# Không đụng service nào; không cần restart. Idempotent: đã có /swapfile2 đang bật + fstab đúng → SKIP.
set -euo pipefail
MODE=${1:?check|apply}
case "$MODE" in check|apply) ;; *) echo "ABORT: MODE phải là check|apply"; exit 1;; esac
SW=/swapfile2; FSTAB=/etc/fstab; LINE="$SW none swap sw,nofail 0 0"
TS=$(TZ=Asia/Ho_Chi_Minh date +%Y%m%d-%H%M%S)

echo "== $MODE $(TZ=Asia/Ho_Chi_Minh date '+%F %T')"
cat /proc/swaps; free -m | sed -n 1,3p
ACTIVE=no; grep -q "^$SW " /proc/swaps && ACTIVE=yes
INFSTAB=$(grep -cE "^[[:space:]]*$SW[[:space:]]" $FSTAB || true)
if [ "$ACTIVE" = yes ] && [ "$INFSTAB" = 1 ]; then echo "SKIP: $SW đã bật và có trong fstab"; exit 0; fi
[ "$ACTIVE" = no ] || { echo "ABORT: $SW đang bật nhưng fstab không khớp (INFSTAB=$INFSTAB) — báo Claude"; exit 1; }
[ "$INFSTAB" = 0 ] || { echo "ABORT: fstab đã có dòng $SW nhưng swap chưa bật — báo Claude"; exit 1; }
[ ! -e "$SW" ] || { echo "ABORT: $SW đã tồn tại (file cũ?) — báo Claude, không ghi đè"; exit 1; }
[ "$(findmnt -no FSTYPE /)" = ext4 ] || { echo "ABORT: / không phải ext4"; exit 1; }
AVAIL_G=$(df --output=avail -BG / | tail -1 | tr -dc 0-9)
[ "$AVAIL_G" -ge 8 ] || { echo "ABORT: disk trống ${AVAIL_G}G < 8G"; exit 1; }
[ -z "$(tail -c1 $FSTAB)" ] || { echo "ABORT: fstab thiếu newline cuối"; exit 1; }
echo "precheck OK: ext4, disk trống ${AVAIL_G}G, $SW chưa có"

# dry-run fstab bằng chính công cụ kiểm của util-linux (không ghi /etc/fstab)
T=$(mktemp); trap 'rm -f "$T"' EXIT
cp $FSTAB "$T"; printf '%s\n' "$LINE" >> "$T"
if findmnt --verify --tab-file "$T" >"$T.out" 2>&1; then rc=0; else rc=$?; fi
grep -iE "error|$SW" "$T.out" | head -5 || true; rm -f "$T.out"
[ $rc = 0 ] || { echo "ABORT: findmnt --verify fstab mới lỗi rc=$rc"; exit 1; }
echo "dry-run fstab OK (findmnt --verify)"
for c in dd mkswap swapon swapoff; do command -v $c >/dev/null || { echo "ABORT: thiếu $c"; exit 1; }; done
if [ "$MODE" = check ]; then echo "CHECK OK — chưa ghi gì"; exit 0; fi

echo "-- sudo (Hưng tự gõ mật khẩu)"; sudo -v
FB=$FSTAB.bak-$TS-pre-swapfile2
sudo cp -p $FSTAB "$FB"
[ "$(sha256sum $FSTAB | cut -c1-16)" = "$(sha256sum "$FB" | cut -c1-16)" ] || { echo "ABORT: backup fstab lệch"; exit 1; }
echo "BACKUP_FSTAB=$FB"

sudo install -m 600 -o root -g root /dev/null $SW
sudo dd if=/dev/zero of=$SW bs=1M count=2048 status=none conv=fsync   # dd thay fallocate theo khuyến nghị man mkswap
sudo mkswap $SW >/dev/null
sudo swapon $SW
grep -q "^$SW " /proc/swaps || { echo "FAILED: swapon không thấy $SW — chạy 99"; exit 1; }
echo "$LINE" | sudo tee -a $FSTAB >/dev/null
if findmnt --verify >/dev/null 2>&1; then :; else echo "FAILED: findmnt --verify sau khi sửa fstab — chạy 99 ngay (đừng reboot)"; exit 1; fi

echo "-- readback"
ls -l $SW; cat /proc/swaps; free -m | sed -n 3p
diff "$FB" $FSTAB || true
echo "OK 10 — swap tổng $(free -m | awk '/Swap/{print $2}') MiB"
echo "Rollback: ssh -t … 'bash /home/hung/ops-swap/99_rollback.sh $FB'"
