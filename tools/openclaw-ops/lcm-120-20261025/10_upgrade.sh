#!/usr/bin/env bash
# 10 — Nâng lossless-claw 1.1.1 → 1.2.0 trên core 2026.9.33 (MỘT bot mỗi lần: suckhoe trước, hungreo sau).
# Stop-first + backup SQLite không chép -shm + relink peerDependency openclaw + diff config + verify readyz.
# Không đụng: model/auth/fallback/slots, core, plugin khác, Nemo, Hermes. Không in secret/chatId.
set -euo pipefail
export TZ=Asia/Ho_Chi_Minh

P=${1:-}
case "$P" in
  suckhoe) PORT=18795 ;;
  hungreo) PORT=18789 ;;
  *) echo "ABORT: dùng 'bash -s suckhoe' hoặc 'bash -s hungreo'"; exit 1 ;;
esac

OC=/home/hung/bin/openclaw
RUNTIME_933="/home/hung/openclaw-upgrade-20261018-933/runtime/node_modules/openclaw"
FROM="1.1.1"
TO="1.2.0"
SPEC="@martian-engineering/lossless-claw@$TO"
D="$HOME/.openclaw-$P"
U="openclaw-gateway-$P.service"
B="$HOME/backups/lcm-120-$P-$(date +%Y%m%d-%H%M%S)"
PHASE=precheck

redact_stream() {
  sed -E 's/sessionKey=[^ ]+/sessionKey=<R>/g; s/chatId=[0-9-]+/chatId=<R>/g; s/telegram:(direct:|group:)?[0-9-]+/telegram:<R>/g; s/bot[0-9]+:[A-Za-z0-9_-]+/bot<R>/g; s/sk-[^ "]+/<R>/g; s/eyJ[^ "]+/<R>/g'
}

on_err() {
  echo "FAILED ở dòng $1 (phase=$PHASE)"
  if [ "$PHASE" = precheck ]; then
    echo "Chưa đổi gì, gateway $P vẫn đang chạy."
  elif [ "$PHASE" = stop ] || [ "$PHASE" = backup ]; then
    echo "Plugin CHƯA đổi → bật lại $P + healthcheck timer như cũ."
    systemctl --user start "$U" || true
    [ "${HC_WAS:-active}" = active ] && systemctl --user start openclaw-healthcheck.timer || true
    echo "  $P=$(systemctl --user is-active "$U" || true) timer=$(systemctl --user is-active openclaw-healthcheck.timer || true)."
  else
    echo "Gateway $P đang DỪNG, healthcheck timer đang TẮT."
    echo "Chạy ngay rollback hard: ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s $P hard $B' < tools/openclaw-ops/lcm-120-20261025/99_rollback.sh"
  fi
}
trap 'on_err $LINENO' ERR

oc_profile() {
  (
    for v in $(compgen -v OPENCLAW_ 2>/dev/null || true); do unset "$v"; done
    unset TELEGRAM_BOT_TOKEN
    set -a
    [ -f "$D/gateway.systemd.env" ] && . "$D/gateway.systemd.env"
    set +a
    OPENCLAW_PROFILE="$P" \
    OPENCLAW_STATE_DIR="$D" \
    OPENCLAW_CONFIG_PATH="$D/openclaw.json" \
    OPENCLAW_GATEWAY_PORT="$PORT" \
    OPENCLAW_SYSTEMD_UNIT="$U" \
      timeout 300 "$OC" --profile "$P" "$@" < /dev/null
  )
}

index_spec() {
  python3 - "$D/state/openclaw.sqlite" <<'PY'
import sqlite3,sys,json
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
c.close()
PY
}

echo "== [0] Kiểm điều kiện tiên quyết ($P, $(date '+%F %T')) =="
[ "$(systemctl --user is-active "$U")" = active ] || { echo "ABORT: $U không active"; exit 1; }
[ -d "$RUNTIME_933" ] || { echo "ABORT: thiếu $RUNTIME_933"; exit 1; }
read -r CUR_SPEC CUR_PATH < <(index_spec)
echo "  index hiện tại: $CUR_SPEC"
[ "$CUR_SPEC" = "@martian-engineering/lossless-claw@$FROM" ] || { echo "ABORT: spec hiện tại ($CUR_SPEC) không phải @$FROM"; exit 1; }
[ "$(jq -r .version "$CUR_PATH/package.json")" = "$FROM" ] || { echo "ABORT: package tại installPath không phải $FROM"; exit 1; }
DB=$(jq -r '.plugins.entries["lossless-claw"].config.dbPath // empty' "$D/openclaw.json"); DB=${DB/#\~/$HOME}; DB=${DB:-$D/lcm.db}
[ -f "$DB" ] || { echo "ABORT: không thấy $DB"; exit 1; }
FREE=$(df -BG --output=avail / | tail -1 | tr -dc 0-9)
[ "$FREE" -ge 3 ] || { echo "ABORT: disk trống ${FREE}G < 3G"; exit 1; }
[ ! -e "$B" ] || { echo "ABORT: $B đã tồn tại"; exit 1; }

DRY=$(oc_profile plugins update "$SPEC" --dry-run 2>&1 | redact_stream || true)
echo "  dry-run: $(grep -i 'would' <<<"$DRY" | head -2 || true)"
grep -q "$FROM -> $TO" <<<"$DRY" || { echo "ABORT: dry-run không ra '$FROM -> $TO':"; echo "$DRY" | tail -15; exit 1; }
CFG_HASH0=$(sha256sum "$D/openclaw.json" | cut -c1-8)
echo "  config=$CFG_HASH0 db=$(du -h "$DB" | cut -f1) disk_free=${FREE}G"

PHASE=stop
echo "== [1] Tắt healthcheck timer + stop $P =="
HC_WAS=$(systemctl --user is-active openclaw-healthcheck.timer || true)
systemctl --user stop openclaw-healthcheck.timer openclaw-healthcheck.service || true
systemctl --user stop "$U"
sleep 5
[ "$(systemctl --user show "$U" -p MainPID --value)" = 0 ] || { echo "ABORT: $P chưa dừng"; false; }
if ss -ltn "sport = :$PORT" | grep -q LISTEN; then echo "ABORT: cổng $PORT vẫn mở"; false; fi
echo "  $P stopped (healthcheck timer trước đó: $HC_WAS)"

PHASE=backup
echo "== [2] Backup -> $B (không chép -shm) =="
QC=$(python3 - "$DB" "$D/state/openclaw.sqlite" <<'PY'
import sqlite3,sys
for p in sys.argv[1:3]:
    c=sqlite3.connect("file:"+p+"?mode=ro",uri=True)
    r=c.execute("pragma quick_check").fetchone()[0]
    c.close()
    if r != "ok":
        print(f"FAIL:{p}:{r}")
        sys.exit(0)
print("ok")
PY
)
echo "  lcm + state quick_check (trước backup): $QC"
[ "$QC" = ok ] || { echo "ABORT: quick_check=$QC"; false; }
mkdir -p -m 700 "$B/state" "$B/lcm"
cp -p "$D/openclaw.json" "$B/"
for f in "$D/state/openclaw.sqlite" "$D/state/openclaw.sqlite-wal"; do [ ! -e "$f" ] || cp -p "$f" "$B/state/"; done
for f in "$DB" "$DB-wal"; do [ ! -e "$f" ] || cp -p "$f" "$B/lcm/"; done
tar czf "$B/npm-lossless-$FROM.tgz" -C "$D/npm/projects" $(cd "$D/npm/projects" && ls -d martian-engineering-lossless-claw-*)
echo "$HC_WAS" > "$B/healthcheck_timer_state"
echo "$DB" > "$B/db_path"
(cd "$B" && find . -type f ! -name SHA256SUMS -exec sha256sum {} \; | sort -k2 > SHA256SUMS)
(cd "$B" && sha256sum -c --quiet SHA256SUMS) || { echo "ABORT: checksum backup sai"; false; }
du -sh "$B"

PHASE=update
echo "== [3] plugins update $SPEC + kiểm peerDependency openclaw =="
UPD=$(oc_profile plugins update "$SPEC" 2>&1) || { echo "$UPD" | redact_stream | tail -15 || true; echo "ABORT: plugins update lỗi"; false; }
redact_stream <<<"$UPD" | tail -15 || true
read -r NEW_SPEC NEW_PATH < <(index_spec)
echo "  index mới: $NEW_SPEC"
[ "$NEW_SPEC" = "$SPEC" ] || { echo "ABORT: index không phải $SPEC ($NEW_SPEC)"; false; }
[ "$(jq -r .version "$NEW_PATH/package.json")" = "$TO" ] || { echo "ABORT: package mới không phải $TO"; false; }

# Đảm bảo peerDependency openclaw trong project lossless-claw trỏ đúng runtime 9.33 (lesson 2026-10-08)
PROJ_NM=$(dirname "$(dirname "$NEW_PATH")")
if [ ! -e "$PROJ_NM/openclaw/package.json" ] || [ "$(jq -r .version "$PROJ_NM/openclaw/package.json" 2>/dev/null || echo none)" != "2026.9.33" ]; then
  ln -sfn "$RUNTIME_933" "$PROJ_NM/openclaw"
  echo "  đã relink peer openclaw -> $RUNTIME_933"
else
  echo "  peer openclaw OK ($(readlink -f "$PROJ_NM/openclaw"))"
fi

[ "$(systemctl --user show "$U" -p MainPID --value)" = 0 ] || { echo "ABORT: gateway tự chạy lại sau plugins update"; false; }
echo "  config hash: $CFG_HASH0 -> $(sha256sum "$D/openclaw.json" | cut -c1-8)"
python3 - "$D/openclaw.json" "$B/openclaw.json" <<'PY'
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
echo "== [4] Start $P + kiểm readyz & LCM 1.2.0 =="
SINCE=$(date '+%F %T')
systemctl --user start "$U"
OK=""
for i in $(seq 1 48); do
  J=$(journalctl --user -u "$U" --since "$SINCE" --no-pager || true)
  if grep -q "\[gateway\] ready" <<<"$J"; then OK=1; echo "  ready sau ~$((i*5))s"; break; fi
  [ "$(systemctl --user is-active "$U")" != failed ] || break
  sleep 5
done
[ -n "$OK" ] || { echo "ABORT: $P không ready sau 240s"; grep -iE 'error|lossless|lcm|fail' <<<"$J" | redact_stream | tail -15 || true; false; }
READYZ=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/readyz")
echo "  readyz: $READYZ"
[ "$READYZ" = "200" ] || { echo "ABORT: readyz=$READYZ != 200"; false; }

LOG=$(journalctl --user -u "$U" --since "$SINCE" --no-pager)
grep -oE 'http server listening \([0-9]+ plugins: [^)]*' <<<"$LOG" | head -1 | cut -c1-200 || true
grep -q 'lossless-claw' <<<"$LOG" || { echo "ABORT: không thấy lossless-claw trong log khởi động"; false; }
if grep -q 'readSessionTranscriptVisibleMessageDelta is required' <<<"$LOG"; then
  echo "ABORT: LCM 1.2.0 báo thiếu readSessionTranscriptVisibleMessageDelta!"
  false
fi
echo "  log lossless/lcm (lỗi/cảnh báo):"; grep -iE 'lossless|lcm|migration' <<<"$LOG" | grep -iE 'error|fail|warn' | redact_stream | cut -c1-220 | tail -8 || true

python3 - "$DB" <<'PY'
import sqlite3,sys
c=sqlite3.connect("file:"+sys.argv[1]+"?mode=ro",uri=True)
qc=c.execute("pragma quick_check").fetchone()[0]
tabs={r[0] for r in c.execute("select name from sqlite_master where type='table'")}
c.close()
print("  lcm quick_check:",qc,"has_120_tables:", "conversation_transcript_cursors" in tabs)
if qc!="ok": sys.exit("ABORT: lcm quick_check sau start != ok")
PY

PHASE=done
[ "$HC_WAS" = active ] && systemctl --user start openclaw-healthcheck.timer
echo "  healthcheck.timer: $(systemctl --user is-active openclaw-healthcheck.timer || true)"
echo "  $P $(systemctl --user is-active "$U") pid=$(systemctl --user show "$U" -p MainPID --value)"
echo "BACKUP=$B"
echo "OK 10 $P"
