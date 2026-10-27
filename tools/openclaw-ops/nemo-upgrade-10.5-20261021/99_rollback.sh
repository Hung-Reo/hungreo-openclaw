#!/usr/bin/env bash
# 99 — Nemo 10.5 → 10.4: khôi phục config/workspace từ backup của 20_cutover, chạy lại container nemo-sandbox-10.4.
# ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash /home/hung/sandbox-nemo/ops-10.5-20261021/99_rollback.sh <BACKUP_DIR>'
# Lưu ý: tin nhắn/trạng thái phát sinh SAU lúc backup sẽ nằm ở config.failed-10.5-*, không mất nhưng không còn trong bot.
set -Eeuo pipefail
S=/home/hung/sandbox-nemo
T=$S/ops-10.5-20261021
B=${1:-$(cat "$T/backup-path")}
TS=$(TZ=Asia/Ho_Chi_Minh date +%Y%m%d-%H%M%S)
[ "$(hostname)" = srv1367812 ] || { echo "ABORT: sai host"; exit 1; }
case "$B" in /home/hung/backups/nemo-10.5-[0-9]*) ;; *) echo "ABORT: $B không phải backup của việc này"; exit 1;; esac
[ -f "$B/config.tar" ] && [ -f "$B/workspace.tar" ] || { echo "ABORT: backup thiếu tar"; exit 1; }
(cd "$B" && sha256sum -c --quiet SHA256SUMS) || { echo "ABORT: SHA256 backup lệch"; exit 1; }

if docker inspect nemo-sandbox >/dev/null 2>&1; then
  rt=$(docker inspect nemo-sandbox --format '{{range .Mounts}}{{if eq .Destination "/sandbox/runtime"}}{{.Source}}{{end}}{{end}}')
  if [ "$rt" = "$S/runtime-10.5" ]; then          # đã đổi container → cất container 10.5 lỗi
    docker stop -t 60 nemo-sandbox >/dev/null || true
    docker rename nemo-sandbox "nemo-sandbox-failed-10.5-$TS"
    docker update --restart=no "nemo-sandbox-failed-10.5-$TS" >/dev/null
  elif [ "$rt" = "$S/runtime-10.4" ]; then        # fail trước khi rename → giữ container 10.4, chỉ trả config
    docker stop -t 60 nemo-sandbox >/dev/null || true
  else
    echo "ABORT: nemo-sandbox mount runtime lạ ($rt) — báo Claude"; exit 1
  fi
fi
mv "$S/config" "$S/config.failed-10.5-$TS"
mv "$S/workspace" "$S/workspace.failed-10.5-$TS"
tar -C "$S" -xpf "$B/config.tar"
tar -C "$S" -xpf "$B/workspace.tar"
docker inspect nemo-sandbox >/dev/null 2>&1 || docker rename nemo-sandbox-10.4 nemo-sandbox
docker update --restart=unless-stopped nemo-sandbox >/dev/null
docker start nemo-sandbox >/dev/null
for i in $(seq 1 90); do
  if [ "$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:18796/readyz || true)" = 200 ]; then
    v=$(docker exec nemo-sandbox node -e 'console.log(require("/sandbox/runtime/node_modules/openclaw/package.json").version)')
    [ "$v" = 2026.10.4 ] && { echo "OK 99 — ROLLBACK_10_4_READY (state hỏng cất ở *.failed-10.5-$TS)"; exit 0; }
    echo "FAILED: lên nhưng version=$v"; exit 1
  fi
  sleep 2
done
echo "ROLLBACK_NOT_READY — báo Claude"; exit 1
