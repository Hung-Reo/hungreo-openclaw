#!/usr/bin/env bash
# Rollback B1. Hưng chạy: sudo bash ~/claude-bot-vps-20261125/99_b1_rollback_root.sh
# Gỡ user claudebot (kèm home), linger, AppArmor profile bwrap. Giữ gói apt (vô hại) và token gốc ở /home/hung/.secrets.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Cần chạy bằng sudo"; exit 1; }
runuser -u claudebot -- env XDG_RUNTIME_DIR=/run/user/$(id -u claudebot) systemctl --user stop claude-collab.service 2>/dev/null || true
loginctl disable-linger claudebot 2>/dev/null || true
pkill -u claudebot 2>/dev/null || true
id claudebot >/dev/null 2>&1 && deluser --remove-home claudebot
if [[ -e /etc/apparmor.d/bwrap ]]; then
  apparmor_parser -R /etc/apparmor.d/bwrap || true
  mv /etc/apparmor.d/bwrap "/root/bwrap.apparmor.removed-$(date +%Y%m%d-%H%M%S)"
fi
echo "Rollback B1 xong."
