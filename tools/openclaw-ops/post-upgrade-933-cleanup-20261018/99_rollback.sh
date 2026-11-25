#!/bin/bash
# 99_rollback.sh — Khôi phục toàn vẹn plugin + state + systemd từ BACKUP_DIR:
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s <suckhoe|hungreo> <BACKUP_DIR>' < 99_rollback.sh
set -euo pipefail
umask 077
export TZ=Asia/Ho_Chi_Minh

P=${1:?bot (suckhoe|hungreo)}
B=${2:?BACKUP_DIR}
case "$P" in
  suckhoe) PORT=18795 ;;
  hungreo) PORT=18789 ;;
  *) echo "ABORT: dùng suckhoe hoặc hungreo"; exit 1 ;;
esac

D=$HOME/.openclaw-$P
U=openclaw-gateway-$P.service
UNIT_FILE=$HOME/.config/systemd/user/$U
UNIT_DIR=$HOME/.config/systemd/user/$U.d

[ -d "$B" ] || { echo "ABORT: không thấy $B"; exit 1; }
(cd "$B" && sha256sum -c --quiet SHA256SUMS) || { echo "ABORT: checksum backup $B sai"; exit 1; }

echo "== [1] stop healthcheck timer + $U"
systemctl --user stop openclaw-healthcheck.timer openclaw-healthcheck.service || true
systemctl --user stop "$U" || true
sleep 5
[ "$(systemctl --user show "$U" -p MainPID --value)" = 0 ] || { echo "ABORT: $U chưa dừng"; exit 1; }

echo "== [2] cất trạng thái lỗi vào $B/failed-$(date +%H%M%S)"
F="$B/failed-$(date +%H%M%S)"
mkdir -p "$F/state" "$F/systemd"
cp -p "$D/openclaw.json" "$F/" 2>/dev/null || true
for s in "$D/state/openclaw.sqlite"*; do [ ! -e "$s" ] || mv "$s" "$F/state/"; done
mv "$D/npm/projects" "$F/npm-projects" 2>/dev/null || true
cp -a "$UNIT_DIR" "$F/systemd/service.d" 2>/dev/null || true

echo "== [3] khôi phục từ $B"
cp -p "$B/openclaw.json" "$D/openclaw.json"
cp -p "$B/state/openclaw.sqlite"* "$D/state/"
rm -f "$D/state/openclaw.sqlite-shm"
tar xzf "$B/npm-projects-pre.tgz" -C "$D/npm"
cp -p "$B/systemd/$U" "$UNIT_FILE"
if [ -e "$B/systemd/${U}.bak" ]; then
  cp -p "$B/systemd/${U}.bak" "${UNIT_FILE}.bak"
fi
rm -rf "$UNIT_DIR"
mkdir -p "$UNIT_DIR"
cp -a "$B/systemd/service.d/." "$UNIT_DIR/"
systemctl --user daemon-reload

echo "== [4] start $U"
SINCE=$(date '+%F %T')
systemctl --user start "$U"
OK=""
for i in $(seq 1 48); do
  J=$(journalctl --user -u "$U" --since "$SINCE" --no-pager || true)
  if grep -q "\[gateway\] ready" <<<"$J"; then
    OK=1
    echo "  ready sau ~$((i*5))s"
    break
  fi
  [ "$(systemctl --user is-active "$U")" != failed ] || break
  sleep 5
done
[ -n "$OK" ] || { echo "ABORT: $U không ready sau rollback"; exit 1; }
echo "  readyz: $(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/readyz")"

HC_WAS=$(cat "$B/healthcheck_timer_state" 2>/dev/null || echo active)
[ "$HC_WAS" = active ] && systemctl --user start openclaw-healthcheck.timer
echo "ROLLBACK_OK $P"
