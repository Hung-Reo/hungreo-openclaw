#!/usr/bin/env bash
# 10 — Dọn bản thử 10.5 lỗi + đồ cũ của Nemo (GO Hưng 22/10). HƯNG CHẠY:
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s check' < 10_cleanup.sh    # chỉ kiểm + in dung lượng, KHÔNG xoá
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s apply' < 10_cleanup.sh    # xoá đúng danh sách dưới
# GIỮ (rollback tới hết soak): nemo-sandbox (live), nemo-sandbox-10.4, runtime-10.4, runtime-10.5, ops-10.5-20261021, ops-lcm120-20261022,
#   backups nemo-10.5-20261021-203858 + nemo-lcm120-20261022-062251, config/, workspace/, .npm, .cache, ~/.openclaw-nemotron.
set -euo pipefail
MODE=${1:?check|apply}
case "$MODE" in check|apply) ;; *) echo "ABORT: check|apply"; exit 1;; esac
S=/home/hung/sandbox-nemo; BK=/home/hung/backups
[ "$(hostname)" = srv1367812 ] || { echo "ABORT: sai host"; exit 1; }

CONTAINERS=(nemo-sandbox-failed-10.5-20261021-125948 nemo-sandbox-10.3 nemo-sandbox-10.2 nemo-rehearsal-103-lcm)
DIRS=(
  "$S/config.failed-10.5-20261021-125948" "$S/workspace.failed-10.5-20261021-125948"
  "$S/config.failed-10.3-lcm-20261014-211943" "$S/workspace.failed-10.3-lcm-20261014-211943"
  "$S/ops-10.3-lcm-20261014" "$S/ops-10.4-20261018"
  "$S/runtime-10.2" "$S/runtime-10.3"
  "$BK/nemo-10.5-20261021-125528" "$BK/nemo-10.4-20261018-154116" "$BK/nemo-10.3-lcm-20261014-212310"
)
KEEP=("$S/config" "$S/workspace" "$S/runtime-10.4" "$S/runtime-10.5" "$S/.npm" "$S/.cache" "$S/ops-10.5-20261021" "$S/ops-lcm120-20261022"
      "$BK/nemo-10.5-20261021-203858" "$BK/nemo-lcm120-20261022-062251")

echo "== $MODE $(TZ=Asia/Ho_Chi_Minh date '+%F %T')"; df -h / | tail -1
# 0) live phải đúng trạng thái hiện tại (10.5 + LCM 1.2.0), bộ rollback phải còn
[ "$(docker inspect nemo-sandbox --format '{{.State.Running}}')" = true ] || { echo "ABORT: nemo-sandbox không chạy"; exit 1; }
[ "$(docker inspect nemo-sandbox --format '{{range .Mounts}}{{if eq .Destination "/sandbox/runtime"}}{{.Source}}{{end}}{{end}}')" = "$S/runtime-10.5" ] || { echo "ABORT: live không ở runtime-10.5"; exit 1; }
for k in "${KEEP[@]}"; do [ -e "$k" ] || { echo "ABORT: thứ cần GIỮ không còn: $k"; exit 1; }; done
docker inspect nemo-sandbox-10.4 >/dev/null 2>&1 || { echo "ABORT: container rollback nemo-sandbox-10.4 không còn"; exit 1; }

# 1) container: phải tồn tại-hoặc-đã-xoá, Exited, không phải live/rollback
fail=0; CT_DEL=()
for c in "${CONTAINERS[@]}"; do
  case "$c" in nemo-sandbox|nemo-sandbox-10.4) echo "  ABORT: $c nằm trong danh sách giữ"; exit 1;; esac
  if ! docker inspect "$c" >/dev/null 2>&1; then echo "  (đã không còn) container $c"; continue; fi
  st=$(docker inspect "$c" --format '{{.State.Status}}')
  if [ "$st" != exited ] && [ "$st" != created ]; then echo "  CHẶN container $c đang $st"; fail=1; continue; fi
  echo "  xoá container $c ($st, $(docker ps -a --size --filter name="^${c}\$" --format '{{.Size}}'))"; CT_DEL+=("$c")
done

# 2) thư mục: đường dẫn tuyệt đối cố định, không symlink, nằm dưới $S hoặc $BK, không bị container nào CÒN LẠI mount, không bị process nào mở
ALLC=$(docker ps -a --format '{{.Names}}') || { echo "ABORT: docker ps lỗi"; exit 1; }
mounted_by_remaining() {  # $1 dir → in tên container (ngoài danh sách xoá) có mount nằm trong dir
  local d=$1 c src
  for c in $ALLC; do
    local x skip=0; for x in "${CT_DEL[@]}"; do [ "$x" = "$c" ] && skip=1; done; [ $skip = 1 ] && continue
    for src in $(docker inspect "$c" --format '{{range .Mounts}}{{.Source}} {{end}}'); do
      case "$src/" in "$d"/*) echo "$c"; return 0;; esac
      case "$d/" in "$src"/*) echo "$c (mount thư mục cha $src)"; return 0;; esac
    done
  done
  return 1
}
open_by_process() {  # $1 dir → có fd/cwd của process (đọc được) trỏ vào dir không
  local d=$1 p t l
  for p in /proc/[0-9]*; do
    for l in "$p/cwd" "$p/exe" "$p"/fd/*; do
      t=$(readlink "$l" 2>/dev/null) || continue
      case "$t" in "$d"|"$d"/*) echo "${p#/proc/}"; return 0;; esac
    done
  done
  return 1
}
DIR_DEL=(); total=0
for d in "${DIRS[@]}"; do
  case "$d" in "$S"/*|"$BK"/*) ;; *) echo "  ABORT: $d ngoài vùng cho phép"; exit 1;; esac
  for k in "${KEEP[@]}"; do
    [ "$d" = "$k" ] && { echo "  ABORT: $d nằm trong danh sách giữ"; exit 1; }
    case "$k/" in "$d"/*) echo "  ABORT: $d chứa thứ cần giữ $k"; exit 1;; esac
  done
  if [ ! -e "$d" ]; then echo "  (đã không còn) $d"; continue; fi
  [ -L "$d" ] && { echo "  CHẶN $d là symlink"; fail=1; continue; }
  [ "$(realpath "$d")" = "$d" ] || { echo "  CHẶN realpath $d khác"; fail=1; continue; }
  if m=$(mounted_by_remaining "$d"); then echo "  CHẶN $d còn bị container $m mount"; fail=1; continue; fi
  if p=$(open_by_process "$d"); then echo "  CHẶN $d đang được process $p mở"; fail=1; continue; fi
  kb=$(du -sk "$d" | cut -f1); total=$((total+kb))
  echo "  xoá $d ($((kb/1024)) MiB)"; DIR_DEL+=("$d")
done
echo "== tổng thư mục sẽ xoá: $((total/1024)) MiB, container: ${#CT_DEL[@]}"
[ $fail = 0 ] || { echo "CÓ MỤC BỊ CHẶN — không xoá gì. Gửi output cho Claude."; exit 1; }
if [ "$MODE" = check ]; then echo "CHECK OK — chưa xoá gì"; exit 0; fi

echo "== apply"
for c in "${CT_DEL[@]}"; do docker rm "$c" >/dev/null && echo "  removed container $c"; done   # không -v: bind mount trên host không bị đụng
for d in "${DIR_DEL[@]}"; do rm -rf --one-file-system -- "$d" && echo "  removed $d"; done
echo "-- readback"
for c in "${CONTAINERS[@]}"; do docker inspect "$c" >/dev/null 2>&1 && echo "  CÒN container $c" || true; done
for d in "${DIRS[@]}"; do [ -e "$d" ] && echo "  CÒN $d" || true; done
for k in "${KEEP[@]}"; do [ -e "$k" ] || echo "  MẤT thứ cần giữ: $k"; done
echo "nemo-sandbox: $(docker inspect nemo-sandbox --format '{{.State.Status}}') readyz=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18796/readyz)"
df -h / | tail -1
echo "OK 10 — CLEANUP_DONE"
