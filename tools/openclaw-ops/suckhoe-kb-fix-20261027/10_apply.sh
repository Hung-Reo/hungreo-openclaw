#!/usr/bin/env bash
# 10 — ÁP bản vá nhắc duyệt + Rotation V2 + whitelist merge cho plugin suckhoe-kb-weekly, 1 lần restart Suckhoe.
# HƯNG CHẠY 1 LẦN (sau khi 00 PASS), chạy NỀN để SSH rớt không làm script chết giữa chừng:
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'setsid nohup bash /home/hung/ops/suckhoe-kb-fix-20261027/10_apply.sh > /home/hung/ops/suckhoe-kb-fix-20261027/apply.log 2>&1 < /dev/null &'
#   rồi xem:  ssh … 'tail -n 40 /home/hung/ops/suckhoe-kb-fix-20261027/apply.log'   (chờ dòng OK 10 hoặc OK 99)
# Không đổi openclaw.json / model / auth. Lỗi sau khi đã ghi file → tự gọi 99_rollback.sh.
set -euo pipefail
export TZ=Asia/Ho_Chi_Minh XDG_RUNTIME_DIR="/run/user/$(id -u)"
PKG=$(cd "$(dirname "$0")" && pwd)
P=/home/hung/.openclaw-suckhoe/extensions/suckhoe-kb-weekly
CFG=/home/hung/.openclaw-suckhoe/openclaw.json
U=openclaw-gateway-suckhoe.service
T=openclaw-healthcheck.timer
PORT=18795
[ "$(hostname)" = srv1367812 ] || { echo "ABORT: sai host"; exit 1; }
exec 9>/home/hung/ops/.suckhoe-kb-fix.lock; flock -n 9 || { echo "ABORT: đang có 10_apply khác chạy — CHỈ BẤM 1 LẦN"; exit 1; }
W=$(jq -r '.plugins.entries["suckhoe-kb-weekly"].config.whitelistPath' "$CFG")
[ ! -L "$W" ] || { echo "ABORT: whitelist là symlink"; exit 1; }
TIMER0=$(systemctl --user is-active "$T" || true)

# Khung giờ cấm: job sáng Suckhoe 04:10–07:15, nhắc thuốc 19:15–19:45, sáng CN 00:30–09:00 (candidate tuần mới tới)
hm=$((10#$(date +%H%M))); dow=$(date +%u)
if { [ $hm -ge 410 ] && [ $hm -lt 715 ]; } || { [ $hm -ge 1915 ] && [ $hm -lt 1945 ]; } || { [ "$dow" = 7 ] && [ $hm -ge 30 ] && [ $hm -lt 900 ]; }; then
  echo "ABORT: đang trong khung giờ cấm ($(date '+%a %H:%M')) — chạy lại sau"; exit 1
fi
[ "$(systemctl --user is-active $U)" = active ] || { echo "ABORT: $U không active"; exit 1; }

echo "== 10 $(date '+%F %T') — chạy lại 00 trước"
bash "$PKG/00_check.sh"
CFG_SHA0=$(sha256sum "$CFG" | cut -c1-64)

TS=$(date +%Y%m%d-%H%M%S); B=/home/hung/backups/suckhoe-kb-fix-$TS
mkdir -p -m 700 "$B"
tar -C "$P" -czf "$B/plugin-dist.tgz" dist
cp -a "$W" "$B/whitelist.txt"; echo "$W" > "$B/whitelist.path"
(cd "$B" && sha256sum plugin-dist.tgz whitelist.txt > SHA256SUMS && sha256sum -c --quiet SHA256SUMS)
echo "  BACKUP_OK $B"

PHASE=install
on_err() {
  echo "!! LỖI ở PHASE=$PHASE (dòng $1) → rollback tự động"
  trap - ERR INT TERM HUP
  bash "$PKG/99_rollback.sh" "$B" || echo "!! ROLLBACK LỖI — báo Claude ngay; backup: $B"
  # 99 thấy timer đã bị 10 dừng nên không tự bật lại → bật theo trạng thái lúc đầu
  if [ "$TIMER0" = active ]; then systemctl --user start "$T" || echo "!! không bật lại được $T"; fi
  exit 1
}
trap 'on_err $LINENO' ERR
trap 'on_err signal' INT TERM HUP

systemctl --user stop "$T"
install -m 644 "$PKG/files/dist/index.js" "$P/dist/index.js"
for f in commands.js poller.js candidate.js; do install -m 644 "$PKG/files/dist/src/$f" "$P/dist/src/$f"; done
tmpw=$(mktemp "$(dirname "$W")/.whitelist.XXXXXX")
cp "$W" "$tmpw"; grep -qxF 'dalieu.vn' "$tmpw" || printf '%s\n' 'dalieu.vn' >> "$tmpw"
chmod --reference="$W" "$tmpw"; mv -f "$tmpw" "$W"
for pair in "dist/index.js" "dist/src/commands.js" "dist/src/poller.js" "dist/src/candidate.js"; do
  [ "$(sha256sum "$P/$pair" | cut -c1-64)" = "$(sha256sum "$PKG/files/$pair" | cut -c1-64)" ] || { echo "readback lệch: $pair"; false; }
done
grep -qxF 'dalieu.vn' "$W"
echo "  INSTALL_READBACK_OK"

PHASE=restart
START=$(date '+%F %T')
systemctl --user restart "$U"
ok=0
for i in $(seq 1 60); do
  sleep 3
  [ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/readyz)" = 200 ] && { ok=1; break; }
done
[ $ok = 1 ] || { echo "readyz không lên sau 180s"; false; }
sleep 5
J=$(journalctl --user -u "$U" --since "$START" --no-pager)
grep -q 'http server listening.*suckhoe-kb-' <<<"$J" || { echo "plugin suckhoe-kb-weekly không có trong danh sách plugin"; false; }
! grep -qiE 'suckhoe-kb-weekly.*(error|fail)|Drive polling disabled' <<<"$J" || { echo "log plugin có lỗi"; false; }
[ "$(sha256sum "$CFG" | cut -c1-64)" = "$CFG_SHA0" ] || { echo "openclaw.json bị đổi ngoài dự kiến"; false; }
echo "  RESTART_OK readyz=200 plugin=loaded pid=$(systemctl --user show $U -p MainPID --value)"

PHASE=done
trap - ERR INT TERM HUP
[ "$TIMER0" = active ] && systemctl --user start "$T"
echo "  timer $T: $(systemctl --user is-active $T)"
echo "OK 10 — đã áp. Backup: $B · Rollback: bash $PKG/99_rollback.sh $B"
