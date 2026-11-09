#!/usr/bin/env bash
# ROOM-CHANGE-PACKET-VPS-20261109-01 — đẩy packet review một chiều Mac → VPS cho Hermes đọc.
# Mặc định DRY-RUN (không SSH). --apply: Hưng GO chung 09/11 (chỉ lệnh này, chỉ vào inbox).
# --rollback và mọi thay đổi VPS khác vẫn cần GO riêng.
# Nằm trong repo (bot group bị denyWrite) để bot không sửa được script trước khi PC chạy.
#
#   push-packet.sh <TASK_ID>            # dry-run: liệt kê file, quét secret, in MANIFEST
#   push-packet.sh <TASK_ID> --apply    # đẩy vào /home/hung/work/collab-protocol/inbox/<TASK_ID>/<stamp>/
#                                       # và dọn các thư mục <stamp> trong inbox cũ hơn 30 ngày (Hưng GO 09/11)
#   push-packet.sh <TASK_ID> --rollback <stamp>   # xoá đúng 1 lần đẩy (cần GO riêng)
set -euo pipefail

SSH_HOST="hungreo-claude-vps"                      # ~/.ssh/config: User hung, IdentityFile ~/.ssh/hostinger_kvm2
REMOTE_BASE="/home/hung/work/collab-protocol/inbox"
WORK="$HOME/collab-bot/work"
ALLOW_EXT='md|txt|ts|json|out'
MAX_FILE=$((1024 * 1024))                           # 1 MB / file
MAX_TOTAL=$((10 * 1024 * 1024))                     # 10 MB / lần đẩy
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=yes)

RETENTION_DAYS=30
STAMP_GLOB='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]'

die() { echo "push-packet: $*" >&2; exit 1; }

# Lệnh dọn chạy trên VPS (GNU find); tách ra hàm để test được trên thư mục giả.
cleanup_cmd() {
  local base="$1"
  echo "test -d '$base' || exit 0; find '$base' -mindepth 2 -maxdepth 2 -type d -name '$STAMP_GLOB' -mtime +$RETENTION_DAYS -print -exec rm -rf -- {} + | sed 's/^/CLEANED /'; find '$base' -mindepth 1 -maxdepth 1 -type d -empty -print -delete | sed 's/^/CLEANED_EMPTY /'; true"
}
if [[ "${1:-}" == "--print-cleanup" ]]; then cleanup_cmd "${2:?base}"; exit 0; fi

TASK_ID="${1:-}"; MODE="${2:---dry-run}"; STAMP_ARG="${3:-}"
[[ "$TASK_ID" =~ ^[A-Z0-9][A-Z0-9-]{5,80}$ ]] || die "TASK_ID không hợp lệ (chỉ A-Z 0-9 -): '$TASK_ID'"
case "$MODE" in --dry-run|--apply|--rollback) ;; *) die "mode: --dry-run | --apply | --rollback <stamp>";; esac

if [[ "$MODE" == "--rollback" ]]; then
  [[ "$STAMP_ARG" =~ ^[0-9]{8}-[0-9]{6}$ ]] || die "stamp dạng YYYYmmdd-HHMMSS"
  DEST="$REMOTE_BASE/$TASK_ID/$STAMP_ARG"
  echo "Xoá trên VPS: $DEST"
  ssh "${SSH_OPTS[@]}" "$SSH_HOST" "test -d '$DEST' && rm -rf -- '$DEST' && rmdir --ignore-fail-on-non-empty '$REMOTE_BASE/$TASK_ID' && echo removed"
  exit 0
fi

WORK_REAL="$(cd "$WORK" && pwd -P)"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/push-packet.XXXXXX")"; chmod 700 "$STAGE"
trap 'rm -rf "$STAGE"' EXIT

# 1. Chọn file: chỉ trong ~/collab-bot/work/<TASK_ID>* (file hoặc thư mục), đúng đuôi, không symlink.
total=0; n=0; rejected=0
while IFS= read -r -d '' f; do
  rel="${f#"$WORK"/}"
  name="$(basename "$f")"
  if [[ -L "$f" ]]; then echo "BỎ (symlink): $rel"; rejected=$((rejected+1)); continue; fi
  real="$(cd "$(dirname "$f")" && pwd -P)/$name"
  [[ "$real" == "$WORK_REAL/"* ]] || { echo "BỎ (ngoài work): $rel"; rejected=$((rejected+1)); continue; }
  [[ "$name" =~ \.($ALLOW_EXT)$ ]] || { echo "BỎ (đuôi): $rel"; continue; }
  [[ "$name" =~ (^\.env|secret|token|credential|\.key$|\.pem$) ]] && { echo "BỎ (tên nhạy cảm): $rel"; rejected=$((rejected+1)); continue; }
  size=$(stat -f %z "$f")
  (( size <= MAX_FILE )) || { echo "BỎ (>1 MB): $rel"; rejected=$((rejected+1)); continue; }
  # 2. Quét nội dung: khoá riêng, token Telegram/GitHub/OpenAI, JWT, URL tải file có token.
  if grep -qE -- '-----BEGIN [A-Z ]*PRIVATE KEY-----|[0-9]{8,12}:[A-Za-z0-9_-]{30,}|(sk-|ghp_|github_pat_)[A-Za-z0-9_-]{16,}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.|api\.telegram\.org/file/bot[0-9]' "$f"; then
    die "DỪNG: nghi có secret trong $rel — không đẩy gì cả"
  fi
  total=$((total + size)); n=$((n + 1))
  mkdir -p "$STAGE/$(dirname "$rel")"; cp -p "$f" "$STAGE/$rel"
done < <(find "$WORK" -maxdepth 1 -name "$TASK_ID*" -print0 | xargs -0 -I{} find {} -name node_modules -prune -o \( -type f -o -type l \) -print0)

(( n > 0 )) || die "không có file nào cho $TASK_ID"
(( total <= MAX_TOTAL )) || die "tổng $total byte > 10 MB"
(cd "$STAGE" && find . -type f ! -name MANIFEST.sha256 | sed 's#^\./##' | LC_ALL=C sort | while IFS= read -r p; do shasum -a 256 "$p"; done > MANIFEST.sha256)
MANIFEST_SHA="$(shasum -a 256 "$STAGE/MANIFEST.sha256" | cut -d' ' -f1)"

echo "--- $n file, $total byte, bỏ có lý do nhạy cảm/symlink: $rejected"
cat "$STAGE/MANIFEST.sha256"
echo "MANIFEST.sha256 sha256=$MANIFEST_SHA"

if [[ "$MODE" == "--dry-run" ]]; then echo "DRY-RUN: không SSH, không đẩy."; exit 0; fi

# 3. Apply: thư mục mới mỗi lần đẩy (không ghi đè), 1 chiều, rồi kiểm sha ngay trên VPS.
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$REMOTE_BASE/$TASK_ID/$STAMP"
ssh "${SSH_OPTS[@]}" "$SSH_HOST" "umask 077; test ! -e '$DEST' && mkdir -p '$DEST'" || die "không tạo được $DEST (đã tồn tại?)"
COPYFILE_DISABLE=1 tar --no-xattrs --no-mac-metadata -C "$STAGE" -cf - . | ssh "${SSH_OPTS[@]}" "$SSH_HOST" "umask 077; tar -C '$DEST' -xf - --no-same-owner"
ssh "${SSH_OPTS[@]}" "$SSH_HOST" "cd '$DEST' && sha256sum -c --quiet MANIFEST.sha256 && echo VERIFY_OK"
echo "PUSHED $DEST  MANIFEST sha256=$MANIFEST_SHA"
# 4. Dọn packet cũ hơn RETENTION_DAYS: chỉ thư mục tên <YYYYmmdd-HHMMSS> ở đúng độ sâu inbox/<TASK_ID>/<stamp>,
#    rồi thư mục <TASK_ID> rỗng. Lỗi dọn không làm hỏng lần đẩy vừa xong.
ssh "${SSH_OPTS[@]}" "$SSH_HOST" "$(cleanup_cmd "$REMOTE_BASE")" || echo "push-packet: cảnh báo — bước dọn >${RETENTION_DAYS} ngày lỗi" >&2
echo "Tin group (1 dòng): @hungreo_bds_bot $TASK_ID packet: $DEST · MANIFEST $MANIFEST_SHA"
echo "Rollback: $0 $TASK_ID --rollback $STAMP"
