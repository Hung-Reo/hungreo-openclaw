#!/bin/bash
# 10 — Dọn dung lượng VPS nhóm A + B (Hưng GO 11/10/2026). MẶC ĐỊNH DRY-RUN.
#   Dry-run: ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 10_cleanup.sh
#   Xoá thật: ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'APPLY=1 bash -s' < 10_cleanup.sh
# Danh sách cố định (không glob). Mỗi mục kiểm: tồn tại, không phải symlink, nằm trong /home/hung,
# không unit/drop-in systemd nào nhắc tới, không tiến trình nào mở file/cwd bên trong.
# Không có rollback (xoá là vĩnh viễn) — vì vậy chỉ gồm bản sao/cache/backup đã bị thay thế.
set -u
export XDG_RUNTIME_DIR=/run/user/$(id -u)
H=/home/hung; APPLY=${APPLY:-0}; TS=$(date +%Y%m%d-%H%M%S)
LOGDIR=$H/cleanup-logs; mkdir -p $LOGDIR; LOG=$LOGDIR/storage-cleanup-$TS-$([ "$APPLY" = 1 ] && echo apply || echo dry).log
log() { echo "$*" | tee -a "$LOG"; }

# Nhóm A — bản sao của thứ không đổi (upgrade Hermes 11/10 không áp gì) + cache tự tải lại
A=(
  "$H/backups/hermes-upgrade-v0216-20261011-134945"
  "$H/.hermes/backups/pre-update-2026-10-11-135048.zip"
  "$H/.hermes/state-snapshots/20261011-065046-pre-update"
  "$H/.hermes/cache/uv"
  "$H/.cache/uv"
  "$H/.npm/_cacache"
  "$H/.cache/pip"
  "$H/.cache/node-gyp"
)
# Nhóm B — backup rollback cũ đã bị thay thế bởi các lần upgrade sau (9.8, 9.9; Hermes 2026.9.24)
B=(
  "$H/backups/openclaw-upgrade-20260925"
  "$H/backups/lcm-0.15.6-upgrade-20260906-144807"
  "$H/backups/nemo-sandbox-pre-9.6-20260925-084622"
  "$H/backups/sandbox-nemo-pre-hardening-20260905.tar.gz"
  "$H/backups/sandbox-nemo-2026-09-05.tar.gz"
  "$H/backups/openclaw-upgrade-20260724-172856-pre-2026.7.1-2"
  "$H/.hermes/backups/pre-stable-v0.20.1-20260816-204854.zip"
  "$H/.hermes/backups/pre-update-2026-08-10-133846.zip"
  "$H/.hermes/backups/pre-update-2026-08-23-164647.zip"
  "$H/.hermes/backups/pre-update-2026-09-06-121011.zip"
  "$H/.hermes/backups/pre-update-2026-09-13-111201.zip"
  "$H/hermes-upgrade-20260913"
)

log "== storage cleanup $([ "$APPLY" = 1 ] && echo APPLY || echo DRY-RUN) $(date '+%F %T')  log=$LOG"
log "df trước: $(df -h / | tail -1 | awk '{print $3" dùng / "$4" trống ("$5")"}')"

# Điều kiện chung cho nhóm A1: Hermes phải đúng commit cũ (upgrade không áp gì)
hc=$(git -C $H/.hermes/hermes-agent rev-parse --short=10 HEAD 2>/dev/null)
[ "$hc" = 819cc3cbe0 ] || { log "STOP — Hermes không còn ở 819cc3cbe0 (đang $hc); backup upgrade có thể cần cho rollback."; exit 2; }
log "Hermes commit $hc (đúng bản chưa upgrade) ✔"

UNITS=$(cat $H/.config/systemd/user/*.service $H/.config/systemd/user/*.timer $H/.config/systemd/user/*.d/*.conf 2>/dev/null)
CRON=$(crontab -l 2>/dev/null)
OPEN=$(for p in /proc/[0-9]*; do readlink $p/cwd 2>/dev/null; ls -l $p/fd 2>/dev/null | awk '{print $NF}'; done | grep "^$H/" | sort -u)

total=0; ok=(); bad=0
check() { # path group
  local p=$1 g=$2 sz
  case "$p" in $H/*) ;; *) log "  ✗ [$g] ngoài $H: $p"; bad=$((bad+1)); return;; esac
  [ -e "$p" ] || { log "  – [$g] không còn: $p"; return; }
  [ -L "$p" ] && { log "  ✗ [$g] là symlink, bỏ qua: $p"; bad=$((bad+1)); return; }
  local name=${p#$H/}
  if echo "$UNITS" | grep -qF "$p"; then log "  ✗ [$g] systemd tham chiếu: $p"; bad=$((bad+1)); return; fi
  if echo "$CRON" | grep -qF "$p"; then log "  ✗ [$g] crontab tham chiếu: $p"; bad=$((bad+1)); return; fi
  if echo "$OPEN" | grep -q "^$p\(/\|$\)"; then log "  ✗ [$g] tiến trình đang mở: $p"; bad=$((bad+1)); return; fi
  sz=$(du -sk "$p" 2>/dev/null | cut -f1); total=$((total+sz))
  log "  ✔ [$g] $(numfmt --to=iec --from-unit=1024 $sz)  $name"
  ok+=("$p")
}
for p in "${A[@]}"; do check "$p" A; done
for p in "${B[@]}"; do check "$p" B; done
log "Tổng sẽ giải phóng: $(numfmt --to=iec --from-unit=1024 $total) — ${#ok[@]} mục đạt, $bad mục bị chặn"

if [ "$APPLY" != 1 ]; then log "DRY-RUN — không xoá gì. Chạy lại với APPLY=1 để xoá."; exit 0; fi
[ "$bad" -eq 0 ] || { log "STOP — có mục bị chặn; báo Claude Code trước khi xoá."; exit 2; }
for p in "${ok[@]}"; do rm -rf -- "$p" && log "  đã xoá: ${p#$H/}" || log "  ✗ lỗi xoá: $p"; done
log "df sau: $(df -h / | tail -1 | awk '{print $3" dùng / "$4" trống ("$5")"}')"
log "Hermes: $(systemctl --user is-active hermes-gateway.service); hungreo: $(systemctl --user is-active openclaw-gateway-hungreo.service); suckhoe: $(systemctl --user is-active openclaw-gateway-suckhoe.service)"
log "OK — báo Claude Code verify."
