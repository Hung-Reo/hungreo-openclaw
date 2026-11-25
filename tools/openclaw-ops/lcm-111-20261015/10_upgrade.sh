#!/bin/bash
# 10 — HƯNG CHẠY, MỘT bot mỗi lần:  ssh … 'bash -s suckhoe' < 10_upgrade.sh   (sau đó mới tới hungreo)
# Nâng lossless-claw 1.1.0 → 1.1.1 (chỉ plugin, core giữ 2026.9.9). Stop-first.
# Thứ tự: kiểm điều kiện + dry-run (chưa đổi gì) → tắt healthcheck → stop gateway → backup (khi đã dừng)
#         → plugins update đúng spec 1.1.1 (= ghim) → readback → start → chờ ready → kiểm LCM/DB → bật lại healthcheck.
# Lỗi SAU khi đã stop: script dừng, gateway để DỪNG → chạy ngay 99_rollback.sh <bot> hard (in sẵn lệnh).
# Không đụng: model/auth/fallback, core, plugin khác, Nemo. Không in secret.
set -euo pipefail
export TZ=Asia/Ho_Chi_Minh
P=${1:-}
case "$P" in suckhoe) PORT=18795 ;; hungreo) PORT=18789 ;; *) echo "ABORT: dùng 'bash -s suckhoe' hoặc 'bash -s hungreo'"; exit 1 ;; esac
OC=/home/hung/bin/openclaw
FROM=1.1.0; TO=1.1.1
SPEC=@martian-engineering/lossless-claw@$TO
D=$HOME/.openclaw-$P
U=openclaw-gateway-$P.service
B=$HOME/backups/lcm-111-$P-$(date +%Y%m%d-%H%M%S)
PHASE=precheck
on_err() {
  echo "FAILED ở dòng $1 (phase=$PHASE)"
  if [ "$PHASE" = precheck ]; then
    echo "Chưa đổi gì, gateway vẫn chạy. Gửi output cho Claude Code."
  elif [ "$PHASE" = stop ] || [ "$PHASE" = backup ]; then
    echo "Plugin CHƯA đổi → bật lại $P + healthcheck timer như cũ."
    systemctl --user start $U || true
    [ "${HC_WAS:-active}" = active ] && systemctl --user start openclaw-healthcheck.timer || true
    echo "  $P=$(systemctl --user is-active $U || true) timer=$(systemctl --user is-active openclaw-healthcheck.timer || true). Gửi output cho Claude Code."
  else
    echo "Gateway $P có thể đang DỪNG, healthcheck timer đang TẮT."
    echo "Chạy ngay:  ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s $P hard $B' < 99_rollback.sh"
  fi
}
trap 'on_err $LINENO' ERR

oc() { ( set -a; . "$D/gateway.systemd.env"; set +a
         OPENCLAW_STATE_DIR=$D OPENCLAW_CONFIG_PATH=$D/openclaw.json timeout 300 $OC --profile $P "$@" < /dev/null ); }
index_spec() { python3 - "$D/state/openclaw.sqlite" <<'PY'
import sqlite3,sys,json,re
c=sqlite3.connect("file:"+sys.argv[1]+"?mode=ro",uri=True)
def walk(o):
    if isinstance(o,dict):
        r=o.get("lossless-claw")
        if isinstance(r,dict) and "spec" in r and "installPath" in r: return r
        for v in o.values():
            x=walk(v)
            if x: return x
    elif isinstance(o,list):
        for v in o:
            x=walk(v)
            if x: return x
for (v,) in c.execute("select value_json from config_machine_state"):
    try: r=walk(json.loads(v))
    except Exception: r=None
    if r: print(r["spec"], r["installPath"]); break
PY
}

echo "== [0] điều kiện ($(date '+%F %T'))"
[ "$(systemctl --user is-active $U)" = active ] || { echo "ABORT: $U không active"; exit 1; }
read -r CUR_SPEC CUR_PATH < <(index_spec)
echo "  index: $CUR_SPEC"
[ "$CUR_SPEC" = "@martian-engineering/lossless-claw@$FROM" ] || { echo "ABORT: spec hiện tại không phải $FROM"; exit 1; }
[ "$(jq -r .version "$CUR_PATH/package.json")" = "$FROM" ] || { echo "ABORT: package tại installPath không phải $FROM"; exit 1; }
DB=$(jq -r '.plugins.entries["lossless-claw"].config.dbPath // empty' $D/openclaw.json); DB=${DB:-$D/lcm.db}
[ -f "$DB" ] || { echo "ABORT: không thấy $DB"; exit 1; }
FREE=$(df -BG --output=avail / | tail -1 | tr -dc 0-9)
[ "$FREE" -ge 3 ] || { echo "ABORT: disk trống ${FREE}G < 3G"; exit 1; }
[ ! -e "$B" ] || { echo "ABORT: $B đã tồn tại"; exit 1; }
DRY=$(oc plugins update "$SPEC" --dry-run 2>&1 | grep -vE 'sk-|eyJ' || true)
echo "  dry-run: $(grep -i 'would' <<<"$DRY" | head -2 || true)"
grep -q "$FROM -> $TO" <<<"$DRY" || { echo "ABORT: dry-run không ra '$FROM -> $TO':"; echo "$DRY" | tail -15; exit 1; }
CFG_HASH0=$(sha256sum $D/openclaw.json | cut -c1-8)
echo "  config=$CFG_HASH0 db=$(du -h "$DB" | cut -f1) disk_free=${FREE}G"

PHASE=stop
echo "== [1] tắt healthcheck timer + stop $P"
HC_WAS=$(systemctl --user is-active openclaw-healthcheck.timer || true)
systemctl --user stop openclaw-healthcheck.timer openclaw-healthcheck.service
systemctl --user stop $U
sleep 5
[ "$(systemctl --user show $U -p MainPID --value)" = 0 ] || { echo "ABORT: $P chưa dừng"; false; }
if ss -ltn "sport = :$PORT" | grep -q LISTEN; then echo "ABORT: cổng $PORT vẫn mở"; false; fi
echo "  $P stopped (healthcheck timer trước đó: $HC_WAS)"

PHASE=backup
echo "== [2] backup -> $B"
QC=$(python3 - "$DB" <<'PY'
import sqlite3,sys
print(sqlite3.connect("file:"+sys.argv[1]+"?mode=ro",uri=True).execute("pragma quick_check").fetchone()[0])
PY
)
echo "  lcm quick_check (trước backup): $QC"
[ "$QC" = ok ] || { echo "ABORT: lcm.db quick_check=$QC"; false; }
mkdir -p "$B/state" "$B/lcm"
cp -p $D/openclaw.json "$B/"
for f in $D/state/openclaw.sqlite $D/state/openclaw.sqlite-wal; do [ ! -e "$f" ] || cp -p "$f" "$B/state/"; done
for f in "$DB" "$DB-wal"; do [ ! -e "$f" ] || cp -p "$f" "$B/lcm/"; done   # không chép -shm: SQLite tự dựng lại
tar czf "$B/npm-lossless-$FROM.tgz" -C $D/npm/projects $(cd $D/npm/projects && ls -d martian-engineering-lossless-claw-*)
echo "$HC_WAS" > "$B/healthcheck_timer_state"
echo "$DB" > "$B/db_path"
(cd "$B" && find . -type f ! -name SHA256SUMS -exec sha256sum {} \; | sort -k2 > SHA256SUMS)
(cd "$B" && sha256sum -c --quiet SHA256SUMS) || { echo "ABORT: checksum backup sai"; false; }
du -sh "$B"

PHASE=update
echo "== [3] plugins update $SPEC"
UPD=$(oc plugins update "$SPEC" 2>&1) || { echo "$UPD" | grep -vE 'sk-|eyJ' | tail -15; echo "ABORT: plugins update lỗi"; false; }
grep -vE 'sk-|eyJ' <<<"$UPD" | tail -15 || true
read -r NEW_SPEC NEW_PATH < <(index_spec)
echo "  index: $NEW_SPEC"
[ "$NEW_SPEC" = "$SPEC" ] || { echo "ABORT: index không phải $SPEC"; false; }
[ "$(jq -r .version "$NEW_PATH/package.json")" = "$TO" ] || { echo "ABORT: package mới không phải $TO"; false; }
[ "$(systemctl --user show $U -p MainPID --value)" = 0 ] || { echo "ABORT: gateway tự chạy lại sau plugins update"; false; }
echo "  file đổi sau backup (ngoài logs/tmp):"; find $D -newer "$B/SHA256SUMS" -type f 2>/dev/null | grep -vE '/(logs|tmp|cache)/' | sed "s|$D/||" | head -20 || true
echo "  config: $CFG_HASH0 -> $(sha256sum $D/openclaw.json | cut -c1-8)"
python3 - $D/openclaw.json "$B/openclaw.json" <<'PY'
import json,sys
def flat(d,p=""):
    o={}
    if isinstance(d,dict):
        for k,v in d.items(): o.update(flat(v,p+"."+k))
    else: o[p]=d
    return o
a=flat(json.load(open(sys.argv[1]))); b=flat(json.load(open(sys.argv[2])))
ks=[k for k in sorted(set(a)|set(b)) if a.get(k)!=b.get(k)]
sens=lambda k:any(x in k.lower() for x in("token","key","secret","password"))
print("  config changed keys:",len(ks))
for k in ks: print("   ",k,"| old=","<R>" if sens(k) else b.get(k),"| new=","<R>" if sens(k) else a.get(k))
bad=[k for k in ks if any(x in k for x in(".model",".auth","fallback",".slots"))]
if bad: print("ABORT: đổi khoá cấm:",bad); sys.exit(1)
PY

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
[ -n "$OK" ] || { echo "ABORT: $P không ready sau 240s"; grep -iE 'error|lossless|fail' <<<"$J" | tail -15 || true; false; }
echo "  readyz: $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/readyz)"
LOG=$(journalctl --user -u $U --since "$SINCE" --no-pager)
grep -oE 'http server listening \([0-9]+ plugins: [^)]*' <<<"$LOG" | head -1 | cut -c1-200 || true
grep -q 'lossless-claw' <<<"$LOG" || { echo "ABORT: không thấy lossless-claw trong log khởi động"; false; }
echo "  log lossless/lcm (lỗi/cảnh báo):"; grep -iE 'lossless|lcm|migration' <<<"$LOG" | grep -iE 'error|fail|warn' | cut -c1-220 | tail -8 || true
python3 - "$DB" <<'PY'
import sqlite3,sys
c=sqlite3.connect("file:"+sys.argv[1]+"?mode=ro",uri=True)
qc=c.execute("pragma quick_check").fetchone()[0]
print("  lcm quick_check:",qc)
if qc!="ok": sys.exit("ABORT: lcm quick_check sau start != ok")
cols=[r[1] for r in c.execute("pragma table_info(pending_summary_nodes)") if "ordinal" in r[1]]
print("  pending_summary_nodes cols:",cols, "(1.1.1 migrate:", "ĐÃ" if "active_ordinal_start" in cols else "CHƯA — sẽ chạy ở lượt đầu", ")")
PY

PHASE=done
[ "$HC_WAS" = active ] && systemctl --user start openclaw-healthcheck.timer
echo "  healthcheck.timer: $(systemctl --user is-active openclaw-healthcheck.timer || true)"
echo "  $P $(systemctl --user is-active $U) pid=$(systemctl --user show $U -p MainPID --value)"
echo "BACKUP=$B"
echo "OK 10 $P — báo Claude Code chạy 20_verify.sh, rồi Hưng hỏi bot 1 câu trên Telegram"
