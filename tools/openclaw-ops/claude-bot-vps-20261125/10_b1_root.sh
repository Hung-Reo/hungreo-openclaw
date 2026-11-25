#!/usr/bin/env bash
# B1 — phần cần root cho bot Claude trên VPS (PLAN.md pha B1). Hưng chạy:
#   sudo bash ~/claude-bot-vps-20261125/10_b1_root.sh
# Làm: cài bubblewrap+socat+unzip, tạo user claudebot (không sudo/docker), AppArmor profile cho bwrap
# (theo code.claude.com/docs/en/sandboxing.md), enable-linger, chuyển token bot test sang claudebot.
# Không đụng service nào của hung (Rùa, Suckhoe, Hermes). Rollback: 99_b1_rollback_root.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Cần chạy bằng sudo"; exit 1; }
TS=$(date +%Y%m%d-%H%M%S)
SRC_ENV=/home/hung/.secrets/claude-collab-test/.env
[[ -f $SRC_ENV ]] || { echo "Thiếu $SRC_ENV"; exit 1; }

echo "== 1. Cài gói"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq bubblewrap socat unzip
command -v bwrap socat unzip

echo "== 2. User claudebot"
if id claudebot >/dev/null 2>&1; then
  echo "claudebot đã có, giữ nguyên"
else
  adduser --disabled-password --gecos "" claudebot
fi
chmod 750 /home/claudebot
for g in sudo docker hung adm; do
  if id -nG claudebot | tr ' ' '\n' | grep -qx "$g"; then echo "claudebot đang ở group $g, dừng"; exit 1; fi
done

echo "== 3. AppArmor profile cho bwrap"
P=/etc/apparmor.d/bwrap
if [[ -e $P ]]; then cp -a "$P" "/root/bwrap.apparmor.bak-$TS"; echo "Đã có $P, backup /root/bwrap.apparmor.bak-$TS"; fi
cat > "$P" <<'EOF'
abi <abi/4.0>,
include <tunables/global>

profile bwrap /usr/bin/bwrap flags=(unconfined) {
  userns,
  include if exists <local/bwrap>
}
EOF
apparmor_parser -r "$P"

echo "== 4. Linger (cho systemd --user của claudebot chạy khi không login)"
loginctl enable-linger claudebot

echo "== 5. Token bot test -> claudebot"
D=/home/claudebot/.claude/channels/telegram-collab
install -d -o claudebot -g claudebot -m 700 /home/claudebot/.claude /home/claudebot/.claude/channels "$D"
install -o claudebot -g claudebot -m 600 "$SRC_ENV" "$D/.env"

echo "== 6. Kiểm"
if runuser -u claudebot -- bwrap --ro-bind / / --unshare-user --unshare-net -- true; then echo "bwrap: OK"; else echo "bwrap: FAIL"; fi
if runuser -u claudebot -- test -r /home/hung/.openclaw-hungreo/.env; then echo "CÁCH LY: FAIL (claudebot đọc được .env của Rùa)"; else echo "cách ly /home/hung: OK"; fi
if runuser -u claudebot -- docker ps >/dev/null 2>&1; then echo "docker: FAIL"; else echo "docker bị chặn: OK"; fi
stat -c "%A %U %n" "$D/.env"
id claudebot
echo "B1 xong ($TS)."
