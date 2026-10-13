#!/bin/bash
# 99 — HƯNG CHẠY khi cần quay lại 819cc3cb. Đối số: thư mục backup do 10_upgrade.sh in ra.
# Chạy: ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s -- /home/hung/backups/hermes-upgrade-v0216-<TS>' < 99_rollback.sh
# Không xoá bản mới: chuyển sang <tên>.failed-<giờ> để còn điều tra.
set -u
export TZ=Asia/Ho_Chi_Minh XDG_RUNTIME_DIR=/run/user/$(id -u)
BK=${1:?thiếu thư mục backup}; H=~/.hermes; U=hermes-gateway.service; TS=$(date +%Y%m%d-%H%M%S)
[ -d "$BK/hermes-agent" ] && [ -d "$BK/tools" ] && [ -f "$BK/state/state.db" ] || { echo "STOP — backup thiếu phần"; exit 2; }
[ "$(git -C "$BK/hermes-agent" rev-parse --short HEAD)" = 819cc3c ] || { echo "STOP — backup không phải 819cc3c"; exit 2; }
systemctl --user stop $U; echo "gateway: $(systemctl --user is-active $U)"
mv $H/hermes-agent $H/hermes-agent.failed-$TS && mv $H/tools $H/tools.failed-$TS
cp -a "$BK/hermes-agent" $H/hermes-agent && cp -a "$BK/tools" $H/tools
for f in config.yaml .env auth.json SOUL.md AGENTS.md gateway_state.json channel_directory.json; do [ -e "$BK/state/$f" ] && cp -a "$BK/state/$f" $H/$f; done
cp -a "$BK/state/cron/." $H/cron/; cp -a "$BK/state/profiles/vnstock/." $H/profiles/vnstock/
for db in state.db kanban.db verification_evidence.db shared-state.db; do
  [ -f "$BK/state/$db" ] && { mv $H/$db $H/$db.failed-$TS 2>/dev/null; rm -f $H/$db-wal $H/$db-shm; cp -a "$BK/state/$db" $H/$db; }
done
systemctl --user start $U; sleep 20
echo "gateway: $(systemctl --user is-active $U)  version: $($HOME/.local/bin/hermes --version 2>&1 | head -1)"
echo "Bản lỗi giữ ở: $H/hermes-agent.failed-$TS, $H/tools.failed-$TS. Báo Claude Code verify."
