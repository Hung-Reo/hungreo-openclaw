#!/usr/bin/env bash
# C1 — git sync cho ~claudebot/collab-bot qua repo private Hung-Reo/collab-bot. Hưng chạy:
#   sudo bash ~/claude-bot-vps-20261125/30_c1_root.sh
# Thiết kế (PLAN.md C1, góp ý của Rùa): user riêng `collabsync` giữ deploy key; bot (claudebot) KHÔNG có key.
# Git dir nằm ngoài thư mục của bot (/home/collabsync/collab-bot.git), nên bot không cài được hook, không đổi được config.
# Timer hệ thống (root quản), mỗi 2 phút: commit handoff/ memory/ .claude/ → pull --rebase → push.
# Rollback: 99_c1_rollback_root.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Cần chạy bằng sudo"; exit 1; }
REPO_SSH="git@github.com:Hung-Reo/collab-bot.git"
WT=/home/claudebot/collab-bot
GD=/home/collabsync/collab-bot.git

echo "== 1. Gói acl"
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq acl >/dev/null
command -v setfacl

echo "== 2. User collabsync (không login, không sudo/docker)"
id collabsync >/dev/null 2>&1 || useradd -m -s /usr/sbin/nologin collabsync
chmod 700 /home/collabsync
for g in sudo docker hung claudebot adm; do
  if id -nG collabsync | tr ' ' '\n' | grep -qx "$g"; then echo "collabsync ở group $g, dừng"; exit 1; fi
done

echo "== 3. Deploy key"
K=/home/collabsync/.ssh/id_ed25519
if [[ ! -f $K ]]; then
  install -d -o collabsync -g collabsync -m 700 /home/collabsync/.ssh
  runuser -u collabsync -- ssh-keygen -q -t ed25519 -N "" -C "collabsync@vps collab-bot deploy" -f $K
fi
runuser -u collabsync -- bash -c 'ssh-keyscan -t ed25519 github.com 2>/dev/null > ~/.ssh/known_hosts; chmod 600 ~/.ssh/known_hosts'

echo "== 4. ACL: collabsync đi qua /home/claudebot (chỉ x), đọc/ghi cây collab-bot"
setfacl -m u:collabsync:x /home/claudebot
setfacl -R -m u:collabsync:rwX,u:claudebot:rwX "$WT"
find "$WT" -type d -exec setfacl -m d:u:collabsync:rwX,d:u:claudebot:rwX {} +

echo "== 5. Script sync (root sở hữu, bot không sửa được)"
install -d -m 755 /usr/local/lib/collab-sync
cat > /usr/local/lib/collab-sync/sync.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
export GIT_DIR=/home/collabsync/collab-bot.git GIT_WORK_TREE=/home/claudebot/collab-bot
G=(git -c core.hooksPath=/dev/null -c user.name=collabsync-vps -c user.email=collabsync@localhost)
if [[ ! -d $GIT_DIR ]]; then
  git -c core.hooksPath=/dev/null clone -q --bare git@github.com:Hung-Reo/collab-bot.git "$GIT_DIR"
  git config core.bare false
  git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  "${G[@]}" fetch -q origin
  "${G[@]}" reset -q origin/main      # chỉ đổi index, không đụng file của bot
  git branch -q --set-upstream-to=origin/main main
fi
cd "$GIT_WORK_TREE"
"${G[@]}" add -A -- handoff memory .claude .gitignore 2>/dev/null || true
if ! "${G[@]}" diff --cached --quiet; then
  "${G[@]}" commit -q -m "sync(vps): $(date -u +%FT%TZ)"
fi
if ! "${G[@]}" pull -q --rebase origin main; then
  "${G[@]}" rebase --abort 2>/dev/null || true
  echo "collab-sync: pull --rebase lỗi (xung đột?), đã abort; cần người xem" >&2
  exit 1
fi
"${G[@]}" push -q origin HEAD:main
EOS
chmod 755 /usr/local/lib/collab-sync/sync.sh

cat > /etc/systemd/system/collab-sync.service <<'EOF'
[Unit]
Description=Sync ~claudebot/collab-bot với GitHub Hung-Reo/collab-bot (user collabsync)
After=network-online.target
[Service]
Type=oneshot
User=collabsync
UMask=0007
ExecStart=/usr/local/lib/collab-sync/sync.sh
TimeoutStartSec=90
EOF
cat > /etc/systemd/system/collab-sync.timer <<'EOF'
[Unit]
Description=collab-sync mỗi 2 phút
[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now collab-sync.timer >/dev/null

echo "== 6. Public key — đưa cho Claude PC để gắn làm deploy key (ghi được) của Hung-Reo/collab-bot:"
cat $K.pub
echo "C1 root xong. Timer đã bật; trước khi gắn deploy key các lượt sync sẽ báo lỗi, vô hại."
