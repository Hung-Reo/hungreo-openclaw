#!/bin/bash
# 12 — trả thư mục extension edu-review về bản backup của 11_update_extension.sh rồi restart. Không đụng config.
#   ssh hungreo-claude-vps 'bash -s hungreo <BACKUP_DIR>' < 12_rollback_extension.sh
# Gỡ hẳn plugin (cả config) thì dùng 99_rollback.sh với backup của 10_apply.sh.
set -euo pipefail
export TZ=Asia/Ho_Chi_Minh
P=${1:-}; B=${2:-}
[ "$P" = hungreo ] || { echo "ABORT: chỉ dành cho hungreo"; exit 1; }
case "$B" in "$HOME"/backups/edu-review-ext-hungreo-*) ;; *) echo "ABORT: BACKUP_DIR phải là ~/backups/edu-review-ext-hungreo-*"; exit 1 ;; esac
[ -d "$B/extension-edu-review" ] && [ -f "$B/SHA256SUMS" ] || { echo "ABORT: BACKUP_DIR thiếu file"; exit 1; }
(cd "$B" && sha256sum -c --quiet SHA256SUMS) || { echo "ABORT: backup checksum sai"; exit 1; }
D=$HOME/.openclaw-$P; U=openclaw-gateway-$P.service; PORT=18789; EXT=$D/extensions/edu-review
F=$B/failed-$(date +%Y%m%d-%H%M%S); mkdir -p "$F"
HC_WAS=$(cat "$B/healthcheck_timer_state" 2>/dev/null || echo active)
STEP=stop
trap 'echo "ROLLBACK FAILED ở dòng $LINENO (step=$STEP). Gateway=$(systemctl --user is-active $U || true) timer=$(systemctl --user is-active openclaw-healthcheck.timer || true). Bản lỗi ở $F."' ERR
systemctl --user stop openclaw-healthcheck.timer openclaw-healthcheck.service || true
systemctl --user stop $U || true
sleep 5
[ "$(systemctl --user show $U -p MainPID --value)" = 0 ] || { echo "ABORT: $P chưa dừng"; false; }
STEP=restore
[ ! -d "$EXT" ] || mv "$EXT" "$F/extension-edu-review.failed"
cp -a "$B/extension-edu-review" "$EXT"
echo "  extension trả về $(jq -r .version $EXT/package.json)"
STEP=start
SINCE=$(date '+%F %T')
systemctl --user start $U
OK=""
for i in $(seq 1 48); do
  J=$(journalctl --user -u $U --since "$SINCE" --no-pager || true)
  if grep -q "\[gateway\] ready" <<<"$J"; then OK=1; echo "  ready sau ~$((i*5))s"; break; fi
  sleep 5
done
RZ=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/readyz); echo "  readyz: $RZ"
[ -n "$OK" ] && [ "$RZ" = 200 ] || { echo "ROLLBACK: gateway chưa ready (readyz=$RZ) — để timer TẮT, chạy 99_rollback.sh với backup của 10_apply"; exit 1; }
[ "$HC_WAS" = active ] && systemctl --user start openclaw-healthcheck.timer || true
echo "ROLLBACK DONE — $P $(systemctl --user is-active $U) timer=$(systemctl --user is-active openclaw-healthcheck.timer || true)"
