#!/bin/bash
# 10 — HƯNG CHẠY. Restart riêng Hungreo để thu hồi RAM/swap (phương án B, 10/10).
# Không đổi file nào: không config, không unit, không npm. Chỉ restart + đo trước/sau.
# DRY_RUN=1 → chỉ chạy phần đo + kiểm điều kiện, không dừng timer, không restart.
# FORCE=1   → bỏ qua chặn "có lượt đang chạy trong 5 phút gần nhất".
# Chạy: ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 10_restart.sh
#       (dry-run: ... 'DRY_RUN=1 bash -s' < 10_restart.sh)
set -u
export TZ=Asia/Ho_Chi_Minh XDG_RUNTIME_DIR=/run/user/$(id -u)
P=hungreo; U=openclaw-gateway-$P.service; CFG=~/.openclaw-$P/openclaw.json; ENVF=~/.openclaw-$P/gateway.systemd.env
DRY=${DRY_RUN:-0}; TS=$(date +%Y%m%d-%H%M%S)
EV=~/backups/hungreo-restart-ram-$TS; [ "$DRY" = 1 ] && EV=/tmp/hungreo-restart-ram-dry-$TS
mkdir -p "$EV"

snap() { # label
  local pid; pid=$(systemctl --user show $U -p MainPID --value)
  {
    echo "== $1 $(date '+%F %T')"
    echo "active=$(systemctl --user is-active $U) pid=$pid NRestarts=$(systemctl --user show $U -p NRestarts --value)"
    grep -E 'VmRSS|VmSwap|VmHWM' /proc/$pid/status 2>/dev/null | tr -s ' \t' ' ' | tr '\n' ' '; echo
    echo "cgroup MemoryCurrent=$(systemctl --user show $U -p MemoryCurrent --value) SwapCurrent=$(systemctl --user show $U -p MemorySwapCurrent --value)"
    free -m | awk 'NR>1{print $1,"total="$2,"used="$3,"avail="$NF}'
    echo "config_sha=$(sha256sum $CFG | cut -c1-8) primary=$(jq -r .agents.defaults.model.primary $CFG) fb=$(jq -c .agents.defaults.model.fallbacks $CFG)"
    echo "dropins_sha=$(cat ~/.config/systemd/user/$U.d/*.conf | sha256sum | cut -c1-8)"
  } | tee -a "$EV/state.txt"
}

echo "evidence: $EV"
snap BEFORE
BEFORE_CFG=$(sha256sum $CFG | cut -c1-8)

# Chặn nếu có lượt agent trong 5 phút gần nhất (đang có người dùng / cron đang chạy)
recent=$(journalctl --user -u $U --since '-5min' --no-pager | grep -c 'agent turn milestone')
echo "agent turn milestones 5 phút gần nhất: $recent"
if [ "$recent" -gt 0 ] && [ "${FORCE:-0}" != 1 ]; then
  echo "STOP — đang có lượt chạy. Chờ vài phút rồi chạy lại (hoặc FORCE=1)."; exit 2
fi
[ "$(systemctl --user is-active $U)" = active ] || { echo "STOP — $U không active trước restart. Báo Claude Code."; exit 2; }

if [ "$DRY" = 1 ]; then echo "DRY_RUN — dừng ở đây, không restart."; exit 0; fi

# Dừng healthcheck để nó không restart chồng khi gateway đang 'deactivating' (TimeoutStopSec=340)
systemctl --user stop openclaw-healthcheck.timer
echo "healthcheck.timer: $(systemctl --user is-active openclaw-healthcheck.timer)"

since=$(date '+%F %T')
echo "== restart $U ($since)"
systemctl --user restart $U
ok=0
for i in $(seq 1 96); do   # tối đa 480s: gồm cả thời gian drain khi stop
  if journalctl --user -u $U --since "$since" --no-pager | grep -q "\[gateway\] ready"; then echo "  ready sau ~$((i*5))s"; ok=1; break; fi
  [ "$(systemctl --user is-active $U)" = failed ] && { echo "  FAILED"; break; }
  sleep 5
done
if [ $ok != 1 ]; then
  journalctl --user -u $U --since "$since" --no-pager | grep -iE 'error|cannot find|invalid|fail' | tail -20
  echo "STOP — Hungreo chưa ready; healthcheck.timer vẫn TẮT. Báo Claude Code (config không đổi, nên không có gì để rollback file)."; exit 1
fi

sleep 20
systemctl --user start openclaw-healthcheck.timer
echo "healthcheck.timer: $(systemctl --user is-active openclaw-healthcheck.timer)"

snap AFTER
pid=$(systemctl --user show $U -p MainPID --value)
miss=$(for v in $(grep -v '^#' $ENVF | grep = | cut -d= -f1); do strings /proc/$pid/environ | grep -q "^$v=" || echo -n "$v "; done)
echo "env_missing=[${miss}] degraded=$(journalctl --user -u $U --since "$since" --no-pager | grep -cE 'SECRETS_(DEGRADED|OWNER_UNAVAILABLE)')" | tee -a "$EV/state.txt"
[ "$(sha256sum $CFG | cut -c1-8)" = "$BEFORE_CFG" ] && echo "config unchanged ($BEFORE_CFG)" || echo "⚠️ CONFIG CHANGED khi start — báo Claude Code (có thể auto-migrate)"
echo "errors since restart: $(journalctl --user -u $U --since "$since" --no-pager | grep -ciE 'error|fail')"
echo "OK 10 — báo Claude Code verify; Hưng gửi /status cho Rùa trên Telegram."
