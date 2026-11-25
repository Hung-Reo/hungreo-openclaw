#!/usr/bin/env bash
# 99_rollback_node.sh — Khôi phục suckhoe hoặc hungreo từ Node v24.22.1 về Node v24.21.0 (/home/hung/openclaw-upgrade-20261003/node/bin/node).
set -Eeuo pipefail
umask 077
export TZ=Asia/Ho_Chi_Minh
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

P=${1:?Usage: 99_rollback_node.sh <suckhoe|hungreo> <backup_dir>}
B=${2:?Usage: 99_rollback_node.sh <suckhoe|hungreo> <backup_dir>}
case "$P" in
  suckhoe) PORT=18795 ;;
  hungreo) PORT=18789 ;;
  *) echo "ABORT: invalid profile $P"; exit 1 ;;
esac

D="/home/hung/.openclaw-$P"
U="openclaw-gateway-$P.service"
UNITS="/home/hung/.config/systemd/user"
OLD_NODE_REAL="$(readlink -f /home/hung/openclaw-upgrade-20261003/node/bin/node)"

[ -d "$B" ] || { echo "ABORT: missing backup dir $B"; exit 1; }
(cd "$B" && sha256sum -c --quiet SHA256SUMS)

echo "== [Rollback 1] Stop healthcheck & $U =="
systemctl --user stop openclaw-healthcheck.timer openclaw-healthcheck.service || true
systemctl --user stop "$U" || true
for _ in $(seq 1 15); do
  if [ "$(systemctl --user show "$U" -p MainPID --value)" = "0" ] && ! ss -ltn "sport = :$PORT" | grep -q LISTEN; then
    break
  fi
  sleep 1
done
[ "$(systemctl --user show "$U" -p MainPID --value)" = "0" ] || { echo "ABORT: $U still running"; exit 1; }
if ss -ltn "sport = :$PORT" | grep -q LISTEN; then
  echo "ABORT: port $PORT still listening"
  exit 1
fi

echo "== [Rollback 2] Khôi phục systemd drop-ins, CLI, healthcheck & openclaw.json =="
cp -p "$B/zzzzz-upgrade-99.conf" "$UNITS/$U.d/zzzzz-upgrade-99.conf.rb"
mv "$UNITS/$U.d/zzzzz-upgrade-99.conf.rb" "$UNITS/$U.d/zzzzz-upgrade-99.conf"
if [ "$P" = "hungreo" ] && [ -f "$B/zz-upgrade-99.conf" ]; then
  cp -p "$B/zz-upgrade-99.conf" "$UNITS/hungreo-finance-backup.service.d/zz-upgrade-99.conf.rb"
  mv "$UNITS/hungreo-finance-backup.service.d/zz-upgrade-99.conf.rb" "$UNITS/hungreo-finance-backup.service.d/zz-upgrade-99.conf"
fi
cp -p "$B/openclaw-cli" /home/hung/bin/openclaw.rb-tmp && mv /home/hung/bin/openclaw.rb-tmp /home/hung/bin/openclaw
cp -p "$B/openclaw-healthcheck.sh" /home/hung/bin/openclaw-healthcheck.sh.rb-tmp && mv /home/hung/bin/openclaw-healthcheck.sh.rb-tmp /home/hung/bin/openclaw-healthcheck.sh
cp -p "$B/openclaw.json" "$D/openclaw.json.rb-tmp" && mv "$D/openclaw.json.rb-tmp" "$D/openclaw.json"

systemctl --user daemon-reload
systemctl --user start "$U"

READY_OK=0
for _ in $(seq 1 60); do
  if [ "$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/readyz" || true)" = "200" ]; then
    READY_OK=1
    break
  fi
  sleep 2
done
[ "$READY_OK" = "1" ] || { echo "ABORT: $U did not reach readyz=200 after rollback"; exit 1; }

PID=$(systemctl --user show "$U" -p MainPID --value)
EXE=$(readlink -f "/proc/$PID/exe")
[ "$EXE" = "$OLD_NODE_REAL" ] || { echo "ABORT: rollback exe=$EXE != $OLD_NODE_REAL"; exit 1; }

HC_WAS="active"
[ -f "$B/healthcheck_timer_state" ] && HC_WAS=$(cat "$B/healthcheck_timer_state")
if [ "$HC_WAS" = "active" ]; then
  systemctl --user start openclaw-healthcheck.timer || true
fi
echo "ROLLBACK_NODE_24210_READY_OK profile=$P pid=$PID exe=$EXE"
