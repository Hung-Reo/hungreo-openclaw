#!/usr/bin/env bash
# 99 — Rollback về lossless-claw 1.1.1 trên core 2026.9.33.
#   soft: ssh … 'bash -s <bot> soft' < 99_rollback.sh
#   hard: ssh … 'bash -s <bot> hard <BACKUP_DIR> [force]' < 99_rollback.sh
set -euo pipefail
export TZ=Asia/Ho_Chi_Minh

P=${1:-}; MODE=${2:-}; B=${3:-}; FORCE=${4:-}
case "$P" in suckhoe) PORT=18795 ;; hungreo) PORT=18789 ;; *) echo "ABORT: bot = suckhoe|hungreo"; exit 1 ;; esac
case "$MODE" in soft|hard) ;; *) echo "ABORT: mode = soft|hard"; exit 1 ;; esac

F=""
trap 'echo "FAILED ở dòng $LINENO — gateway $P có thể đang DỪNG, timer TẮT. ${F:+File gốc trước khi khôi phục nằm ở $F. }"' ERR

OC=/home/hung/bin/openclaw
RUNTIME_933="/home/hung/openclaw-upgrade-20261018-933/runtime/node_modules/openclaw"
D="$HOME/.openclaw-$P"
U="openclaw-gateway-$P.service"
SPEC="@martian-engineering/lossless-claw@1.1.1"

redact_stream() {
  sed -E 's/sessionKey=[^ ]+/sessionKey=<R>/g; s/chatId=[0-9-]+/chatId=<R>/g; s/telegram:(direct:|group:)?[0-9-]+/telegram:<R>/g; s/bot[0-9]+:[A-Za-z0-9_-]+/bot<R>/g; s/sk-[^ "]+/<R>/g; s/eyJ[^ "]+/<R>/g'
}

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

if [ "$MODE" = hard ]; then
  case "$B" in "$HOME"/backups/lcm-120-$P-*) ;; *) echo "ABORT: '$B' không phải backup lcm-120 của $P"; exit 1 ;; esac
  [ -f "$B/SHA256SUMS" ] || { echo "ABORT: $B thiếu SHA256SUMS"; exit 1; }
  (cd "$B" && sha256sum -c --quiet SHA256SUMS) || { echo "ABORT: checksum backup sai — KHÔNG khôi phục"; exit 1; }
  echo "backup SHA256 OK"
  AGE_MIN=$(( ( $(date +%s) - $(stat -c %Y "$B/SHA256SUMS") ) / 60 ))
  if [ "$AGE_MIN" -gt 180 ] && [ "$FORCE" != force ]; then
    echo "ABORT: backup đã $AGE_MIN phút — hard sẽ mất dữ liệu ghi sau đó. Dùng 'soft', hoặc thêm 'force' nếu chấp nhận."; exit 1
  fi
  DB=$(cat "$B/db_path")
  case "$DB" in "$D"/*) ;; *) echo "ABORT: db_path '$DB' không thuộc $D"; exit 1 ;; esac
  HC_WAS=$(cat "$B/healthcheck_timer_state")
  [ -f "$B/openclaw.json" ] && [ -f "$B/state/openclaw.sqlite" ] && [ -f "$B/lcm/$(basename "$DB")" ] && [ -f "$B/npm-lossless-1.1.1.tgz" ] \
    || { echo "ABORT: thiếu file trong bộ backup $B để khôi phục"; exit 1; }
else
  DRY=$(oc_profile plugins update "$SPEC" --dry-run 2>&1 | redact_stream || true)
  echo "dry-run: $(grep -i would <<<"$DRY" | head -2 || true)"
  grep -q -- "-> 1.1.1" <<<"$DRY" || { echo "ABORT: dry-run không ra '-> 1.1.1'"; tail -15 <<<"$DRY"; exit 1; }
  HC_WAS=active
fi

echo "== stop healthcheck + $P"
systemctl --user stop openclaw-healthcheck.timer openclaw-healthcheck.service || true
systemctl --user stop "$U" || true
sleep 5
[ "$(systemctl --user show "$U" -p MainPID --value)" = 0 ] || { echo "ABORT: $P chưa dừng"; exit 1; }

if [ "$MODE" = hard ]; then
  F="$B/failed-$(date +%Y%m%d-%H%M%S)"
  echo "== cất trạng thái hiện tại -> $F"
  mkdir -p -m 700 "$F/state" "$F/lcm" "$F/npm"
  [ ! -e "$D/openclaw.json" ] || cp -p "$D/openclaw.json" "$F/"
  for f in "$D/state/openclaw.sqlite"*; do [ ! -e "$f" ] || mv "$f" "$F/state/"; done
  for f in "$DB"*; do [ ! -e "$f" ] || mv "$f" "$F/lcm/"; done
  for d in "$D"/npm/projects/martian-engineering-lossless-claw-*; do [ ! -e "$d" ] || mv "$d" "$F/npm/"; done
  echo "== khôi phục từ $B"
  cp -p "$B/openclaw.json" "$D/openclaw.json"
  cp -p "$B"/state/* "$D/state/"
  cp -p "$B"/lcm/* "$(dirname "$DB")/"
  rm -f "$D/state/openclaw.sqlite-shm" "$DB-shm"
  tar xzf "$B/npm-lossless-1.1.1.tgz" -C "$D/npm/projects"
else
  S="$HOME/backups/lcm-120-$P-soft-$(date +%Y%m%d-%H%M%S)"
  mkdir -p -m 700 "$S/state"; cp -p "$D/openclaw.json" "$S/"
  for f in "$D/state/openclaw.sqlite" "$D/state/openclaw.sqlite-wal"; do [ ! -e "$f" ] || cp -p "$f" "$S/state/"; done
  echo "backup nhỏ trước soft: $S"
  echo "== plugins update $SPEC"
  oc_profile plugins update "$SPEC" 2>&1 | redact_stream | tail -10 || true
fi

read -r S_SPEC PTH < <(index_spec)
echo "index: $S_SPEC  package: $(jq -r .version "$PTH/package.json")"
[ "$(jq -r .version "$PTH/package.json")" = 1.1.1 ] || { echo "ABORT: package tại installPath không phải 1.1.1"; exit 1; }
[ "$S_SPEC" = "$SPEC" ] || { echo "ABORT: index không phải $SPEC"; exit 1; }

PROJ_NM=$(dirname "$(dirname "$PTH")")
if [ ! -e "$PROJ_NM/openclaw/package.json" ] || [ "$(jq -r .version "$PROJ_NM/openclaw/package.json" 2>/dev/null || echo none)" != "2026.9.33" ]; then
  ln -sfn "$RUNTIME_933" "$PROJ_NM/openclaw"
fi

echo "== start $P"
SINCE=$(date '+%F %T'); systemctl --user start "$U"; OK=""; J=""
for i in $(seq 1 48); do
  J=$(journalctl --user -u "$U" --since "$SINCE" --no-pager || true)
  if grep -q "\[gateway\] ready" <<<"$J"; then OK=1; echo "ready sau ~$((i*5))s"; break; fi
  [ "$(systemctl --user is-active "$U")" != failed ] || break
  sleep 5
done
[ -n "$OK" ] || { echo "STOP: $P không ready — healthcheck timer vẫn TẮT"; grep -iE 'error|fail' <<<"$J" | redact_stream | tail -10 || true; exit 1; }
READYZ=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/readyz")
echo "readyz: $READYZ"
[ "$READYZ" = "200" ] || { echo "STOP: readyz=$READYZ != 200 — healthcheck timer vẫn TẮT"; exit 1; }
[ "$HC_WAS" = active ] && systemctl --user start openclaw-healthcheck.timer || true
echo "healthcheck.timer: $(systemctl --user is-active openclaw-healthcheck.timer || true)"
echo "OK 99 $MODE $P"
