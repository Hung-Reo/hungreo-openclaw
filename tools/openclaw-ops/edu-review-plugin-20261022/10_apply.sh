#!/bin/bash
# 10 — cài plugin local `edu-review` vào profile hungreo (Rùa). Stop-first, một lần restart.
#   ssh hungreo-claude-vps 'bash -s hungreo <BUNDLE_DIR>'    < 10_apply.sh   # thật
#   ssh hungreo-claude-vps 'bash -s hungreo <BUNDLE_DIR> dry' < 10_apply.sh  # chỉ precheck + dry-run, không dừng gì
# BUNDLE_DIR = thư mục đã scp lên, chứa edu-review/ + MANIFEST.txt (từ hungreo-super-app/tools/edu-review-plugin/pack.sh).
# Cách cài giống plugin local hungreo-finance: copy vào extensions/ + plugins.allow + plugins.entries. KHÔNG dùng
# `plugins install --force` (từng reset bản ghi cài đặt plugin khác). Không đụng model/auth/fallback/slots, Suckhoe, Nemo.
# Không in secret, không in chat/user ID.
set -euo pipefail
export TZ=Asia/Ho_Chi_Minh
P=${1:-}; BUNDLE=${2:-}; MODE=${3:-apply}
[ "$P" = hungreo ] || { echo "ABORT: chỉ dành cho hungreo"; exit 1; }
[ -n "$BUNDLE" ] && [ -d "$BUNDLE/edu-review" ] && [ -f "$BUNDLE/MANIFEST.txt" ] || { echo "ABORT: BUNDLE_DIR thiếu edu-review/ hoặc MANIFEST.txt"; exit 1; }
PORT=18789
OC=/home/hung/bin/openclaw
D=$HOME/.openclaw-$P
U=openclaw-gateway-$P.service
EXT=$D/extensions/edu-review
KB=/home/hung/openclaw-shared/kb/education
B=$HOME/backups/edu-review-$P-$(date +%Y%m%d-%H%M%S)
TMPD=$(mktemp -d); chmod 700 "$TMPD"; trap 'rm -rf "$TMPD"' EXIT
PHASE=precheck
on_err() {
  echo "FAILED ở dòng $1 (phase=$PHASE)"
  case "$PHASE" in
    precheck) [ "${EXT_CREATED:-}" = 1 ] && rm -rf "$EXT" && echo "  đã gỡ $EXT vừa copy (plugin chưa được allow nên chưa nạp)"
              echo "Config chưa đổi, gateway vẫn chạy." ;;
    done) echo "Gateway đã chạy lại OK; chỉ bước bật lại healthcheck timer lỗi → systemctl --user start openclaw-healthcheck.timer" ;;
    stop|backup)
      echo "Config/extension CHƯA đổi → bật lại $P + healthcheck timer."
      systemctl --user start $U || true
      [ "${HC_WAS:-active}" = active ] && systemctl --user start openclaw-healthcheck.timer || true
      echo "  $P=$(systemctl --user is-active $U || true) timer=$(systemctl --user is-active openclaw-healthcheck.timer || true)" ;;
    *) echo "Gateway $P có thể đang DỪNG, timer TẮT. Chạy ngay:"
       echo "  ssh hungreo-claude-vps 'bash -s hungreo $B' < 99_rollback.sh" ;;
  esac
}
trap 'on_err $LINENO' ERR

mask() { sed -E -e '/sk-|eyJ/d' -e 's/[0-9]{6,}/<N>/g'; }   # không in token, chat/user ID
oc() { ( for v in $(compgen -v OPENCLAW_ 2>/dev/null || true); do unset "$v"; done; unset TELEGRAM_BOT_TOKEN
         set -a; . "$D/gateway.systemd.env"; set +a; cd /tmp
         OPENCLAW_PROFILE=$P OPENCLAW_STATE_DIR=$D OPENCLAW_CONFIG_PATH=$D/openclaw.json OPENCLAW_GATEWAY_PORT=$PORT \
         OPENCLAW_SYSTEMD_UNIT=$U timeout 180 $OC --profile $P "$@" < /dev/null ) 2>&1 | mask; return "${PIPESTATUS[0]}"; }

echo "== [0] điều kiện ($(date '+%F %T'))"
[ "$(systemctl --user is-active $U)" = active ] || { echo "ABORT: $U không active"; exit 1; }
PID0=$(systemctl --user show $U -p MainPID --value)
echo "  core=$(strings /proc/$PID0/environ | grep ^OPENCLAW_SERVICE_VERSION= | cut -d= -f2) pid=$PID0"
(cd "$BUNDLE" && grep -E '^[0-9a-f]{64}  ' MANIFEST.txt | sed 's#  \./#  edu-review/#' | sha256sum -c --quiet) || { echo "ABORT: sha256 bundle khác MANIFEST"; exit 1; }
diff <(cd "$BUNDLE/edu-review" && find . -type f | sort) <(grep -oE '  \./.*$' "$BUNDLE/MANIFEST.txt" | sed 's/^  //' | sort) >/dev/null || { echo "ABORT: danh sách file bundle khác MANIFEST"; exit 1; }
echo "  bundle sha256 khớp MANIFEST"
[ ! -e "$EXT" ] || { echo "ABORT: $EXT đã tồn tại"; exit 1; }
EXT_CREATED=
jq -e '(.plugins.allow|index("edu-review"))==null and (.plugins.entries["edu-review"]==null)' $D/openclaw.json >/dev/null || { echo "ABORT: edu-review đã có trong config"; exit 1; }
# Reviewer = người duy nhất trong allowFrom của Rùa, và phải trùng reviewer của Suckhoe KB (không in giá trị).
RID=$(jq -r '.channels.telegram.allowFrom | if length==1 then (.[0]|tostring|gsub("[^0-9]";"")) else "" end' $D/openclaw.json)
SID=$(jq -r '.plugins.entries["suckhoe-kb-weekly"].config.allowedTelegramUserIds[0] // ""' $HOME/.openclaw-suckhoe/openclaw.json)
[ -n "$RID" ] && [ "$RID" = "$SID" ] || { echo "ABORT: không xác định chắc reviewer (allowFrom Rùa ≠ reviewer Suckhoe hoặc >1 người)"; exit 1; }
echo "  reviewer: 1 người, khớp reviewer Suckhoe"
FREE=$(df -BG --output=avail / | tail -1 | tr -dc 0-9); [ "$FREE" -ge 3 ] || { echo "ABORT: disk trống ${FREE}G"; exit 1; }
[ ! -e "$B" ] || { echo "ABORT: $B đã tồn tại"; exit 1; }

ALLOW_OLD=$(jq -c '.plugins.allow' $D/openclaw.json)
ALLOW_NEW=$(jq -c '.plugins.allow + ["edu-review"]' $D/openclaw.json)
ENTRY=$(jq -nc --arg kb "$KB" --arg rid "$RID" --arg sd "$D" --arg cp "$D/openclaw.json" --arg bin "$OC" \
  '{enabled:true, config:{kbRoot:$kb, openclawBin:$bin, openclawStateDir:$sd, openclawConfigPath:$cp, reviewChatId:$rid, allowedTelegramUserIds:[$rid], pollIntervalSeconds:300, approvalTtlDays:7}}')
printf '%s' "$ENTRY" > "$TMPD/entry.json"
jq -n --argjson allow "$ALLOW_NEW" --slurpfile e "$TMPD/entry.json" '{plugins:{allow:$allow, entries:{"edu-review":$e[0]}}}' > "$TMPD/patch.json"
# Lần 1 (22/10 18:48) set allow riêng → validator đòi entry của plugin đã có trong extensions/ → FAILED sau khi stop.
# Vì vậy: copy extension TRƯỚC (chưa allow = chưa nạp) rồi dry-run đúng một patch gộp allow + entry như lượt thật.
cp -a "$BUNDLE/edu-review" "$EXT"; chmod -R go-rwx "$EXT"; EXT_CREATED=1
echo "  dry-run (extension đã có mặt): patch gộp allow + entry"
oc config patch --file "$TMPD/patch.json" --dry-run | tail -2
CFG_HASH0=$(sha256sum $D/openclaw.json | cut -c1-8)
echo "  config=$CFG_HASH0 disk_free=${FREE}G"
if [ "$MODE" = dry ]; then rm -rf "$EXT"; EXT_CREATED=; echo "OK dry — config chưa đổi, đã gỡ extension thử"; exit 0; fi

PHASE=stop
echo "== [1] tắt healthcheck timer + stop $P"
HC_WAS=$(systemctl --user is-active openclaw-healthcheck.timer || true)
systemctl --user stop openclaw-healthcheck.timer openclaw-healthcheck.service
systemctl --user stop $U
sleep 5
[ "$(systemctl --user show $U -p MainPID --value)" = 0 ] || { echo "ABORT: $P chưa dừng"; false; }
if ss -ltn "sport = :$PORT" | grep -q LISTEN; then echo "ABORT: cổng $PORT vẫn mở"; false; fi
echo "  stopped (timer trước đó: $HC_WAS)"

PHASE=backup
echo "== [2] backup -> $B"
mkdir -p "$B/state"; chmod 700 "$B"
QC=$(python3 -c "import sqlite3,sys;print(sqlite3.connect('file:'+sys.argv[1]+'?mode=ro',uri=True).execute('pragma quick_check').fetchone()[0])" $D/state/openclaw.sqlite)
echo "  state quick_check: $QC"; [ "$QC" = ok ] || { echo "ABORT: openclaw.sqlite quick_check=$QC"; false; }
cp -p $D/openclaw.json "$B/"
for f in $D/state/openclaw.sqlite $D/state/openclaw.sqlite-wal; do [ ! -e "$f" ] || cp -p "$f" "$B/state/"; done
ls -1 $D/extensions > "$B/extensions.before.txt"
echo "$HC_WAS" > "$B/healthcheck_timer_state"
(cd "$B" && find . -type f ! -name SHA256SUMS -exec sha256sum {} \; | sort -k2 > SHA256SUMS)
(cd "$B" && sha256sum -c --quiet SHA256SUMS) || { echo "ABORT: checksum backup sai"; false; }
du -sh "$B"

PHASE=apply
echo "== [3] KB dir + config patch (extension đã copy ở precheck)"
mkdir -p "$KB"; chmod 700 "$KB"
[ "$(jq -c .plugins.allow $D/openclaw.json)" = "$ALLOW_OLD" ] || { echo "ABORT: plugins.allow đổi từ lúc precheck"; false; }
oc config patch --file "$TMPD/patch.json" | tail -2
python3 - $D/openclaw.json "$B/openclaw.json" <<'PY'
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
print("  config changed keys:",len(ks))
for k in ks: print("   ",k)
ok=lambda k: k==".plugins.allow" or k.startswith(".plugins.entries.edu-review.") or k.startswith(".meta.")
forbidden=[k for k in ks if any(x in k for x in (".model",".auth","fallback",".slots"))]
bad=[k for k in ks if not ok(k)]
if forbidden or bad: print("ABORT: đổi khoá cấm/ngoài phạm vi:",forbidden or bad); sys.exit(1)
PY
[ "$(jq -c .plugins.allow $D/openclaw.json)" = "$ALLOW_NEW" ] || { echo "ABORT: readback plugins.allow khác dự kiến"; false; }
jq -e --slurpfile want "$TMPD/entry.json" '.plugins.entries["edu-review"] as $g | $g.enabled == true and ($want[0].config | to_entries | all(.value == $g.config[.key]))' $D/openclaw.json >/dev/null || { echo "ABORT: readback entry edu-review khác dự kiến"; false; }
echo "  readback allow + entry: khớp"
echo "  plugins list (gateway đang dừng):"
PL=$(oc plugins list --json || true)
EDU=$(jq -c '[.. | objects | select(.id?=="edu-review")] | first // empty | {id, enabled, status, origin, error}' <<<"$PL" 2>/dev/null || true)
echo "  $EDU"
[ -n "$EDU" ] || { echo "ABORT: plugins list --json không thấy edu-review"; false; }
jq -e '(.enabled != false) and ((.error // null) == null)' <<<"$EDU" >/dev/null || { echo "ABORT: edu-review disabled hoặc có lỗi"; false; }
[ "$(systemctl --user show $U -p MainPID --value)" = 0 ] || { echo "ABORT: gateway tự chạy lại khi config đổi"; false; }

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
[ -n "$OK" ] || { echo "ABORT: $P không ready sau 240s"; grep -iE 'error|edu-review|fail' <<<"$J" | mask | tail -15 || true; false; }
RZ=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/readyz); echo "  readyz: $RZ"
[ "$RZ" = 200 ] || { echo "ABORT: readyz=$RZ"; false; }
PID1=$(systemctl --user show $U -p MainPID --value); NR1=$(systemctl --user show $U -p NRestarts --value)
sleep 30   # poll đầu của plugin chạy ở giây 15
[ "$(systemctl --user show $U -p MainPID --value)" = "$PID1" ] && [ "$(systemctl --user show $U -p NRestarts --value)" = "$NR1" ] || { echo "ABORT: gateway restart/crash sau khi ready"; false; }
LOG=$(journalctl --user -u $U --since "$SINCE" --no-pager | mask)
grep -oE 'http server listening \([0-9]+ plugins: [^)]*' <<<"$LOG" | head -1 | cut -c1-240 || true
grep -q 'edu-review poller started' <<<"$LOG" || echo "  WARN: journal chưa có 'edu-review poller started' (plugin logger có thể ghi chỗ khác) — 20_verify + /edu_review status sẽ xác nhận"
echo "  log edu-review:"; grep -iE 'edu-review|edu_review' <<<"$LOG" | cut -c1-220 | tail -6 || true
echo "  model sau start: $(jq -c '{p:.agents.defaults.model.primary,fb:.agents.defaults.model.fallbacks,slot:.plugins.slots.contextEngine}' $D/openclaw.json)"

PHASE=done
[ "$HC_WAS" = active ] && systemctl --user start openclaw-healthcheck.timer
echo "  healthcheck.timer: $(systemctl --user is-active openclaw-healthcheck.timer || true)"
echo "  $P $(systemctl --user is-active $U) pid=$(systemctl --user show $U -p MainPID --value)"
echo "BACKUP=$B"
echo "OK 10 — chạy 20_verify.sh, rồi Hưng gõ /edu_review status trên Telegram"
