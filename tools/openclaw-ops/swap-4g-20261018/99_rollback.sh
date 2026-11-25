#!/bin/bash
# 99 — Gỡ /swapfile2: swapoff (trang trong đó dồn về RAM / /swapfile) → trả fstab → xoá file.
# HƯNG CHẠY: ssh -t -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash /home/hung/ops-swap/99_rollback.sh <BACKUP_FSTAB>'
set -euo pipefail
SW=/swapfile2; FSTAB=/etc/fstab; LINE="$SW none swap sw,nofail 0 0"
FB=${1:?cần BACKUP_FSTAB do 10_swap.sh in ra}
case "$FB" in /etc/fstab.bak-*-pre-swapfile2) ;; *) echo "ABORT: $FB không phải backup của việc này"; exit 1;; esac
[ -f "$FB" ] || { echo "ABORT: không thấy $FB"; exit 1; }
# fstab hiện tại phải đúng bằng backup + đúng 1 dòng của mình (không ghi đè sửa đổi khác)
EXP=$(mktemp); trap 'rm -f "$EXP"' EXIT
cat "$FB" > "$EXP"; printf '%s\n' "$LINE" >> "$EXP"
FSTAB_OK=no; cmp -s "$EXP" $FSTAB && FSTAB_OK=yes
cmp -s "$FB" $FSTAB && FSTAB_OK=already
[ "$FSTAB_OK" != no ] || { echo "ABORT: /etc/fstab khác 'backup + dòng swapfile2' — báo Claude, không tự sửa"; exit 1; }

echo "-- sudo (Hưng tự gõ mật khẩu)"; sudo -v
if grep -q "^$SW " /proc/swaps; then
  USED_K=$(awk -v f=$SW '$1==f{print $4}' /proc/swaps)
  AVAIL_K=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
  echo "swapfile2 đang dùng $((USED_K/1024)) MiB, RAM available $((AVAIL_K/1024)) MiB"
  [ "$AVAIL_K" -gt $((USED_K + 1048576)) ] || { echo "ABORT: RAM không đủ để swapoff an toàn (cần used + 1 GiB) — chờ lúc nhàn hơn"; exit 1; }
  sudo swapoff $SW
fi
grep -q "^$SW " /proc/swaps && { echo "FAILED: $SW vẫn bật"; exit 1; }
[ "$FSTAB_OK" = yes ] && sudo cp -p "$FB" $FSTAB
cmp -s "$FB" $FSTAB || { echo "FAILED: fstab chưa về bản backup"; exit 1; }
findmnt --verify >/dev/null 2>&1 || { echo "FAILED: findmnt --verify lỗi sau rollback — báo Claude, đừng reboot"; exit 1; }
[ -f $SW ] && sudo rm -f -- $SW
cat /proc/swaps; free -m | sed -n 3p
echo "OK 99 — đã gỡ $SW, fstab về $FB"
