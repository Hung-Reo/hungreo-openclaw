#!/usr/bin/env bash
# Rollback C1. Hưng chạy: sudo bash ~/claude-bot-vps-20261125/99_c1_rollback_root.sh
# Dừng + gỡ timer, gỡ ACL, xoá user collabsync (kèm key + git dir). File của bot trong ~/collab-bot giữ nguyên.
# Sau đó gỡ deploy key trên GitHub (Settings → Deploy keys của Hung-Reo/collab-bot).
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Cần chạy bằng sudo"; exit 1; }
systemctl disable --now collab-sync.timer 2>/dev/null || true
rm -f /etc/systemd/system/collab-sync.timer /etc/systemd/system/collab-sync.service
systemctl daemon-reload
rm -rf /usr/local/lib/collab-sync
setfacl -x u:collabsync /home/claudebot 2>/dev/null || true
setfacl -R -b /home/claudebot/collab-bot 2>/dev/null || true
id collabsync >/dev/null 2>&1 && deluser --remove-home collabsync
echo "Rollback C1 xong."
