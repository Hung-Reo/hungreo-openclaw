#!/bin/bash
# 11 — thay CODE plugin edu-review (đã cài bằng 10_apply.sh) bằng bundle mới. KHÔNG đổi openclaw.json.
#   ssh hungreo-claude-vps 'bash -s hungreo <BUNDLE_DIR> [dry]' < 11_update_extension.sh
# Lý do bản 0.1.2: nút kiểu "command" bị gửi vào Rùa như text thường → rơi xuống AI (22/10 19:04).
# 0.1.2 dùng nút callback + registerInteractiveHandler(namespace "edu").
# Phiếu đang pending được đặt lại notifiedAt=null để poller gửi lại tin với nút mới.
# Rollback: 12_rollback_extension.sh hungreo <BACKUP_DIR> (trả thư mục extension cũ, restart).
set -euo pipefail
export TZ=Asia/Ho_Chi_Minh
P=${1:-}; BUNDLE=${2:-}; MODE=${3:-apply}
[ "$P" = hungreo ] || { echo "ABORT: chỉ dành cho hungreo"; exit 1; }
[ -n "$BUNDLE" ] && [ -d "$BUNDLE/edu-review" ] && [ -f "$BUNDLE/MANIFEST.txt" ] || { echo "ABORT: BUNDLE_DIR thiếu edu-review/ hoặc MANIFEST.txt"; exit 1; }
PORT=18789
D=$HOME/.openclaw-$P
U=openclaw-gateway-$P.service
EXT=$D/extensions/edu-review
KB=${EDU_KB_ROOT:-/home/hung/openclaw-shared/kb/education}   # override chỉ để test local
B=$HOME/backups/edu-review-ext-$P-$(date +%Y%m%d-%H%M%S)
mask() { sed -E -e '/sk-|eyJ/d' -e 's/[0-9]{6,}/<N>/g'; }
PHASE=precheck
on_err() {
  echo "FAILED ở dòng $1 (phase=$PHASE)"
  case "$PHASE" in
    precheck) echo "Chưa đổi gì, gateway vẫn chạy." ;;
    stop|backup)
      echo "Extension CHƯA đổi → bật lại $P + timer."
      systemctl --user start $U || true
      [ "${HC_WAS:-active}" = active ] && systemctl --user start openclaw-healthcheck.timer || true
      echo "  $P=$(systemctl --user is-active $U || true) timer=$(systemctl --user is-active openclaw-healthcheck.timer || true)" ;;
    done) echo "Gateway đã chạy lại OK; chỉ bật timer lỗi → systemctl --user start openclaw-healthcheck.timer" ;;
    *) echo "Gateway $P có thể đang DỪNG, timer TẮT. Chạy ngay:"
       echo "  ssh hungreo-claude-vps 'bash -s hungreo $B' < 12_rollback_extension.sh" ;;
  esac
}
trap 'on_err $LINENO' ERR

echo "== [0] điều kiện ($(date '+%F %T'))"
[ "$(systemctl --user is-active $U)" = active ] || { echo "ABORT: $U không active"; exit 1; }
[ -d "$EXT" ] || { echo "ABORT: chưa có $EXT (chạy 10_apply.sh trước)"; exit 1; }
jq -e '(.plugins.allow|index("edu-review"))!=null and .plugins.entries["edu-review"].enabled==true' $D/openclaw.json >/dev/null || { echo "ABORT: config chưa có edu-review"; exit 1; }
(cd "$BUNDLE" && grep -E '^[0-9a-f]{64}  ' MANIFEST.txt | sed 's#  \./#  edu-review/#' | sha256sum -c --quiet) || { echo "ABORT: sha256 bundle khác MANIFEST"; exit 1; }
diff <(cd "$BUNDLE/edu-review" && find . -type f | sort) <(grep -oE '  \./.*$' "$BUNDLE/MANIFEST.txt" | sed 's/^  //' | sort) >/dev/null || { echo "ABORT: danh sách file bundle khác MANIFEST"; exit 1; }
grep -q registerInteractiveHandler "$BUNDLE/edu-review/index.js" || { echo "ABORT: bundle không có interactive handler"; exit 1; }
echo "  bundle: $(jq -r .version "$BUNDLE/edu-review/package.json") (đang chạy: $(jq -r .version "$EXT/package.json"))"
[ ! -e "$B" ] || { echo "ABORT: $B đã tồn tại"; exit 1; }
CFG0=$(sha256sum $D/openclaw.json | cut -c1-16)
# Glob rỗng là hợp lệ (KB chưa có phiếu); file state hỏng thì dừng trước khi stop gateway.
shopt -s nullglob
PENDING=""
for f in "$KB"/state/EDU-*.json; do
  st=$(jq -r '.status' "$f") || { echo "ABORT: state hỏng: $(basename "$f")"; exit 1; }
  [ "$st" = pending ] && PENDING="$PENDING $(jq -r .key "$f")"
done
shopt -u nullglob
PENDING=${PENDING# }
echo "  config=${CFG0:0:8} pending=[${PENDING}]"
if [ "$MODE" = dry ]; then echo "OK dry — chưa đổi gì"; exit 0; fi

PHASE=stop
echo "== [1] tắt healthcheck timer + stop $P"
HC_WAS=$(systemctl --user is-active openclaw-healthcheck.timer || true)
systemctl --user stop openclaw-healthcheck.timer openclaw-healthcheck.service
systemctl --user stop $U
sleep 5
[ "$(systemctl --user show $U -p MainPID --value)" = 0 ] || { echo "ABORT: $P chưa dừng"; false; }
if ss -ltn "sport = :$PORT" | grep -q LISTEN; then echo "ABORT: cổng $PORT vẫn mở"; false; fi

PHASE=backup
echo "== [2] backup extension + state phiếu -> $B"
mkdir -p "$B"; chmod 700 "$B"
cp -a "$EXT" "$B/extension-edu-review"
cp -a "$KB/state" "$B/kb-state"
echo "$HC_WAS" > "$B/healthcheck_timer_state"
echo "$CFG0" > "$B/config_sha"
(cd "$B" && find . -type f ! -name SHA256SUMS -exec sha256sum {} \; | sort -k2 > SHA256SUMS)
(cd "$B" && sha256sum -c --quiet SHA256SUMS) || { echo "ABORT: checksum backup sai"; false; }

PHASE=apply
echo "== [3] thay extension + đặt lại notifiedAt cho phiếu pending"
rm -rf "$EXT"
cp -a "$BUNDLE/edu-review" "$EXT"; chmod -R go-rwx "$EXT"
for k in $PENDING; do
  f=$KB/state/$k.json
  if jq --arg v "$(jq -r .version "$BUNDLE/edu-review/package.json")" '.notifiedAt=null | .messageId=null | .history += [{"at":(now|todate),"status":("resend_after_plugin_"+$v)}]' "$f" > "$f.tmp" \
     && chmod 600 "$f.tmp" && mv "$f.tmp" "$f" && [ "$(jq -r .notifiedAt "$f")" = null ]; then
    echo "  $k → sẽ gửi lại"
  else
    rm -f "$f.tmp"; echo "ABORT: không đặt lại được notifiedAt cho $k"; false
  fi
done
[ "$(sha256sum $D/openclaw.json | cut -c1-16)" = "$CFG0" ] || { echo "ABORT: openclaw.json bị đổi"; false; }

PHASE=start
echo "== [4] start $P"
SINCE=$(date '+%F %T')
systemctl --user start $U
OK=""
for i in $(seq 1 48); do
  J=$(journalctl --user -u $U --since "$SINCE" --no-pager || true)
  if grep -q "\[gateway\] ready" <<<"$J"; then OK=1; echo "  ready sau ~$((i*5))s"; break; fi
  [ "$(systemctl --user is-active $U)" != failed ] || break
  sleep 5
done
[ -n "$OK" ] || { echo "ABORT: không ready sau 240s"; grep -iE 'error|edu|fail' <<<"$J" | mask | tail -12 || true; false; }
RZ=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/readyz); echo "  readyz: $RZ"
[ "$RZ" = 200 ] || { echo "ABORT: readyz=$RZ"; false; }
PID1=$(systemctl --user show $U -p MainPID --value); NR1=$(systemctl --user show $U -p NRestarts --value)
sleep 30
[ "$(systemctl --user show $U -p MainPID --value)" = "$PID1" ] && [ "$(systemctl --user show $U -p NRestarts --value)" = "$NR1" ] || { echo "ABORT: gateway restart/crash sau khi ready"; false; }
LOG=$(journalctl --user -u $U --since "$SINCE" --no-pager | mask)
grep -oE 'http server listening \([0-9]+ plugins: [^)]*' <<<"$LOG" | head -1 | cut -c1-240 || true
echo "  log edu:"; grep -iE 'edu-review|edu_review|interactive' <<<"$LOG" | cut -c1-220 | tail -6 || true
if grep -qiE 'registerInteractiveHandler unavailable|namespace "edu" already' <<<"$LOG"; then echo "ABORT: interactive handler không đăng ký được"; false; fi
[ "$(sha256sum $D/openclaw.json | cut -c1-16)" = "$CFG0" ] || echo "  WARN: openclaw.json đổi sau start (gateway tự ghi?) — kiểm 20_verify"

PHASE=done
[ "$HC_WAS" = active ] && systemctl --user start openclaw-healthcheck.timer
echo "  healthcheck.timer: $(systemctl --user is-active openclaw-healthcheck.timer || true)"
echo "  $P $(systemctl --user is-active $U) plugin=$(jq -r .version $EXT/package.json)"
echo "BACKUP=$B"
echo "OK 11 — poller gửi lại phiếu pending trong ~15s–5 phút (trong giờ 07:30–21:30)"
