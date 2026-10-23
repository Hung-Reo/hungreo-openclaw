#!/bin/bash
# 99 — gỡ plugin edu-review khỏi hungreo.
#   ssh hungreo-claude-vps 'bash -s hungreo <BACKUP_DIR> [delta|full] [force]' < 99_rollback.sh
# delta (mặc định): chỉ gỡ "edu-review" khỏi plugins.allow + plugins.entries bằng MỘT config patch; mọi thay đổi
#   config khác (model/auth/plugin khác) sau mốc backup được giữ nguyên.
# full: chép lại cả openclaw.json của backup — CHỈ khi config hiện tại không lệch backup ngoài phạm vi
#   edu-review/meta (kiểm trước khi stop), hoặc khi thêm 'force'.
# Giữ nguyên dữ liệu /home/hung/openclaw-shared/kb/education (không ảnh hưởng Rùa).
set -euo pipefail
export TZ=Asia/Ho_Chi_Minh
P=${1:-}; B=${2:-}; MODE=${3:-delta}; FORCE=${4:-}
[ "$P" = hungreo ] || { echo "ABORT: chỉ dành cho hungreo"; exit 1; }
case "$MODE" in delta|full) ;; *) echo "ABORT: mode phải là delta hoặc full"; exit 1 ;; esac
case "$B" in "$HOME"/backups/edu-review-hungreo-*) ;; *) echo "ABORT: BACKUP_DIR phải là ~/backups/edu-review-hungreo-*"; exit 1 ;; esac
[ -f "$B/openclaw.json" ] && [ -f "$B/SHA256SUMS" ] || { echo "ABORT: BACKUP_DIR thiếu file"; exit 1; }
(cd "$B" && sha256sum -c --quiet SHA256SUMS) || { echo "ABORT: backup checksum sai"; exit 1; }
D=$HOME/.openclaw-$P; U=openclaw-gateway-$P.service; PORT=18789; OC=/home/hung/bin/openclaw
TMPD=$(mktemp -d); chmod 700 "$TMPD"
mask() { sed -E -e '/sk-|eyJ/d' -e 's/[0-9]{6,}/<N>/g'; }
oc() { ( for v in $(compgen -v OPENCLAW_ 2>/dev/null || true); do unset "$v"; done; unset TELEGRAM_BOT_TOKEN
         set -a; . "$D/gateway.systemd.env"; set +a; cd /tmp
         OPENCLAW_PROFILE=$P OPENCLAW_STATE_DIR=$D OPENCLAW_CONFIG_PATH=$D/openclaw.json OPENCLAW_GATEWAY_PORT=$PORT \
         OPENCLAW_SYSTEMD_UNIT=$U timeout 180 $OC --profile $P "$@" < /dev/null ) 2>&1 | mask; return "${PIPESTATUS[0]}"; }

echo "== [0] precheck (mode=$MODE, chưa dừng gì)"
DRIFT=$(python3 - $D/openclaw.json "$B/openclaw.json" <<'PY'
import json,sys
def flat(d,p=""):
    o={}
    if isinstance(d,dict):
        for k,v in d.items(): o.update(flat(v,p+"."+k))
    elif isinstance(d,list): o[p]=json.dumps(d)
    else: o[p]=d
    return o
a=flat(json.load(open(sys.argv[1]))); b=flat(json.load(open(sys.argv[2])))
ks=[k for k in sorted(set(a)|set(b)) if a.get(k)!=b.get(k)]
print(" ".join(k for k in ks if not (k==".plugins.allow" or k.startswith(".plugins.entries.edu-review.") or k.startswith(".meta."))))
PY
)
# plugins.allow: ngoài edu-review, danh sách phải như backup — nếu không, đó cũng là drift.
ALLOW_NOW=$(jq -c '.plugins.allow - ["edu-review"]' $D/openclaw.json); ALLOW_BAK=$(jq -c '.plugins.allow - ["edu-review"]' "$B/openclaw.json")
[ "$ALLOW_NOW" = "$ALLOW_BAK" ] || DRIFT="$DRIFT .plugins.allow(ngoài edu-review)"
echo "  config lệch backup ngoài phạm vi edu-review: [${DRIFT:-không}]"
if [ "$MODE" = full ] && [ -n "$DRIFT" ] && [ "$FORCE" != force ]; then
  echo "ABORT: full sẽ đè các khoá trên. Dùng mode delta, hoặc thêm 'force' nếu chắc chắn."; exit 1
fi
if [ "$MODE" = delta ]; then
  jq -n --argjson allow "$ALLOW_NOW" '{plugins:{allow:$allow, entries:{"edu-review":null}}}' > "$TMPD/patch.json"
  echo "  patch: bỏ edu-review khỏi allow + entries"
fi

F=$B/failed-$(date +%Y%m%d-%H%M%S); mkdir -p "$F"
HC_WAS=$(cat "$B/healthcheck_timer_state" 2>/dev/null || echo active)
STEP=stop
trap 'echo "ROLLBACK FAILED ở dòng $LINENO (step=$STEP). Gateway=$(systemctl --user is-active $U || true) timer=$(systemctl --user is-active openclaw-healthcheck.timer || true). Bản lỗi ở $F. Gửi output cho Claude Code."' ERR

echo "== stop timer + $P"
systemctl --user stop openclaw-healthcheck.timer openclaw-healthcheck.service || true
systemctl --user stop $U || true
sleep 5
[ "$(systemctl --user show $U -p MainPID --value)" = 0 ] || { echo "ABORT: $P chưa dừng, không đổi config"; false; }
STEP=restore
echo "== cất bản lỗi -> $F"
cp -p $D/openclaw.json "$F/openclaw.json.failed"
[ ! -d $D/extensions/edu-review ] || mv $D/extensions/edu-review "$F/extension-edu-review"
if [ "$MODE" = delta ]; then
  oc config patch --file "$TMPD/patch.json" | tail -2
else
  cp -p "$B/openclaw.json" $D/openclaw.json
fi
jq -e '(.plugins.allow|index("edu-review"))==null and (.plugins.entries["edu-review"]==null)' $D/openclaw.json >/dev/null || { echo "ABORT: config vẫn còn edu-review"; false; }
if diff <(ls -1 $D/extensions) "$B/extensions.before.txt" >/dev/null; then echo "  extensions khớp trước khi cài"; else echo "  WARN: extensions khác danh sách trước khi cài"; fi

STEP=start
echo "== start $P"
SINCE=$(date '+%F %T')
systemctl --user start $U
OK=""
for i in $(seq 1 48); do
  J=$(journalctl --user -u $U --since "$SINCE" --no-pager || true)
  if grep -q "\[gateway\] ready" <<<"$J"; then OK=1; echo "  ready sau ~$((i*5))s"; break; fi
  sleep 5
done
RZ=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/readyz)
echo "  readyz: $RZ"
[ -n "$OK" ] && [ "$RZ" = 200 ] || { echo "ROLLBACK: gateway chưa ready (readyz=$RZ) — để healthcheck timer TẮT, gửi output cho Claude Code"; exit 1; }
[ "$HC_WAS" = active ] && systemctl --user start openclaw-healthcheck.timer || true
rm -rf "$TMPD"
echo "  $P $(systemctl --user is-active $U) timer=$(systemctl --user is-active openclaw-healthcheck.timer || true)"
echo "ROLLBACK DONE ($MODE) — Hưng hỏi Rùa 1 câu + /status để xác nhận"
