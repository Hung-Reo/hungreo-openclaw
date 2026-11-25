#!/usr/bin/env bash
# 99 — Trả plugin suckhoe-kb-weekly + whitelist về bản backup của 10_apply, restart Suckhoe.
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash /home/hung/ops/suckhoe-kb-fix-20261027/99_rollback.sh /home/hung/backups/suckhoe-kb-fix-<TS>'
# Không khôi phục drive-files.json (sổ cái): cờ nhắc thêm vào là vô hại; trả sổ cũ có thể làm poller nhập lại file.
# Chỉ an toàn trước 2026-11-08 (sau đó code cũ V1 sẽ từ chối candidate tuần ≥16 — xem ROTATION-V2-SPEC.md §6).
set -euo pipefail
export TZ=Asia/Ho_Chi_Minh XDG_RUNTIME_DIR="/run/user/$(id -u)"
B=${1:?BACKUP_DIR}
P=/home/hung/.openclaw-suckhoe/extensions/suckhoe-kb-weekly
U=openclaw-gateway-suckhoe.service
T=openclaw-healthcheck.timer
[ "$(hostname)" = srv1367812 ] || { echo "ABORT: sai host"; exit 1; }
(cd "$B" && sha256sum -c --quiet SHA256SUMS) || { echo "ABORT: backup hỏng"; exit 1; }
W=$(cat "$B/whitelist.path")
[ "$(date +%s)" -lt "$(date -d '2026-11-08 00:30' +%s)" ] || echo "!! CẢNH BÁO: đã qua 08/11 — code V1 sẽ reject candidate tuần ≥16"
TIMER0=$(systemctl --user is-active "$T" || true)
trap '[ "$TIMER0" = active ] && systemctl --user start "$T"' EXIT
systemctl --user stop "$T" || true
F=$P.failed-kbfix-$(date +%Y%m%d-%H%M%S); mkdir -p "$F"; cp -a "$P/dist" "$F/dist"; cp -a "$W" "$F/whitelist.txt"
rm -rf "$P/dist.rollback-tmp"; mkdir "$P/dist.rollback-tmp"
tar -C "$P/dist.rollback-tmp" -xzf "$B/plugin-dist.tgz"
OLD="$P/dist.before-rollback-$(date +%H%M%S)"; mv "$P/dist" "$OLD"
mv "$P/dist.rollback-tmp/dist" "$P/dist" || { mv "$OLD" "$P/dist"; echo "ABORT: không đặt được dist backup — đã trả dist cũ"; exit 1; }
rmdir "$P/dist.rollback-tmp"; rm -rf "$OLD"
cp -a "$B/whitelist.txt" "$W"
START=$(date '+%F %T')
systemctl --user restart "$U"
ok=0; for i in $(seq 1 60); do sleep 3; [ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:18795/readyz)" = 200 ] && { ok=1; break; }; done
[ $ok = 1 ] || { echo "!! readyz chưa lên sau rollback — báo Claude"; exit 1; }
J=$(journalctl --user -u "$U" --since "$START" --no-pager)
grep -q 'http server listening.*suckhoe-kb-' <<<"$J" && echo "  plugin loaded" || echo "!! chưa thấy plugin trong log"
echo "OK 99 — ROLLBACK_DONE (bản lỗi cất ở $F)"
