#!/bin/bash
# 99 — HƯNG CHẠY khi cần quay về lossless-claw 1.1.0.
#   soft:  ssh … 'bash -s <bot> soft' < 99_rollback.sh
#          Cài lại đúng spec 1.1.0, GIỮ lcm.db hiện tại (1.1.1 chỉ thêm 2 cột NULL; 1.1.0 ghi bằng danh sách cột tường minh → đọc được).
#          Dùng khi bot đã chạy 1.1.1 một thời gian (vd sau soak) — không mất dữ liệu mới.
#   hard:  ssh … 'bash -s <bot> hard <BACKUP_DIR>' < 99_rollback.sh
#          Khôi phục openclaw.json + state/openclaw.sqlite + lcm.db + thư mục npm của plugin từ backup của 10_upgrade.sh.
#          Chỉ dùng NGAY sau sự cố của 10 (backup ≤ 3 giờ; cũ hơn phải thêm tham số thứ 4 `force`) — mất mọi thứ ghi vào
#          state/openclaw.sqlite và lcm.db sau lúc backup. Trạng thái hiện tại được CẤT (mv) vào <BACKUP_DIR>/failed-*, không xoá.
set -euo pipefail
export TZ=Asia/Ho_Chi_Minh
P=${1:-}; MODE=${2:-}; B=${3:-}; FORCE=${4:-}
case "$P" in suckhoe) PORT=18795 ;; hungreo) PORT=18789 ;; *) echo "ABORT: bot = suckhoe|hungreo"; exit 1 ;; esac
case "$MODE" in soft|hard) ;; *) echo "ABORT: mode = soft|hard"; exit 1 ;; esac
F=""
trap 'echo "FAILED ở dòng $LINENO — gateway $P có thể đang DỪNG, timer TẮT. ${F:+File gốc trước khi khôi phục nằm ở $F. }Gửi output cho Claude Code."' ERR
OC=/home/hung/bin/openclaw
D=$HOME/.openclaw-$P
U=openclaw-gateway-$P.service
SPEC=@martian-engineering/lossless-claw@1.1.0
oc() { ( set -a; . "$D/gateway.systemd.env"; set +a
         OPENCLAW_STATE_DIR=$D OPENCLAW_CONFIG_PATH=$D/openclaw.json timeout 300 $OC --profile $P "$@" < /dev/null ); }
index_spec() { python3 - "$D/state/openclaw.sqlite" <<'PY'
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
PY
}

if [ "$MODE" = hard ]; then
  case "$B" in "$HOME"/backups/lcm-111-$P-*) ;; *) echo "ABORT: '$B' không phải backup lcm-111 của $P"; exit 1 ;; esac
  [ -f "$B/SHA256SUMS" ] || { echo "ABORT: $B thiếu SHA256SUMS"; exit 1; }
  (cd "$B" && sha256sum -c --quiet SHA256SUMS) || { echo "ABORT: checksum backup sai — KHÔNG khôi phục"; exit 1; }
  echo "backup SHA256 OK"
  AGE_MIN=$(( ( $(date +%s) - $(stat -c %Y "$B/SHA256SUMS") ) / 60 ))
  if [ "$AGE_MIN" -gt 180 ] && [ "$FORCE" != force ]; then
    echo "ABORT: backup đã $AGE_MIN phút — hard sẽ mất dữ liệu ghi sau đó. Dùng 'soft', hoặc thêm 'force' nếu Hưng chấp nhận."; exit 1; fi
  DB=$(cat "$B/db_path")
  case "$DB" in "$D"/*) ;; *) echo "ABORT: db_path '$DB' không thuộc $D"; exit 1 ;; esac
  HC_WAS=$(cat "$B/healthcheck_timer_state")
  NPM_SRC=$(compgen -G "$D/npm/projects/martian-engineering-lossless-claw-*" || true)
  [ -n "$NPM_SRC" ] && [ -f "$D/state/openclaw.sqlite" ] && [ -f "$DB" ] && [ -f "$B/state/openclaw.sqlite" ] && [ -f "$B/lcm/$(basename "$DB")" ] \
    || { echo "ABORT: thiếu file nguồn/đích để khôi phục"; exit 1; }
else
  DRY=$(oc plugins update "$SPEC" --dry-run 2>&1 || true)
  echo "dry-run: $(grep -i would <<<"$DRY" | head -2 || true)"
  grep -q -- "-> 1.1.0" <<<"$DRY" || { echo "ABORT: dry-run không ra '-> 1.1.0'"; tail -15 <<<"$DRY"; exit 1; }
  HC_WAS=active   # trạng thái bình thường; 10 có thể đã tắt timer giữa sự cố
fi

echo "== stop healthcheck + $P"
systemctl --user stop openclaw-healthcheck.timer openclaw-healthcheck.service
systemctl --user stop $U || true
sleep 5
[ "$(systemctl --user show $U -p MainPID --value)" = 0 ] || { echo "ABORT: $P chưa dừng"; exit 1; }

if [ "$MODE" = hard ]; then
  F=$B/failed-$(date +%Y%m%d-%H%M%S)
  echo "== cất trạng thái hiện tại -> $F"
  mkdir -p "$F/state" "$F/lcm" "$F/npm"
  cp -p $D/openclaw.json "$F/"
  mv $D/state/openclaw.sqlite* "$F/state/"
  mv "$DB"* "$F/lcm/"
  mv $NPM_SRC "$F/npm/"
  echo "== khôi phục từ $B"
  cp -p "$B/openclaw.json" $D/openclaw.json
  cp -p "$B"/state/* $D/state/
  cp -p "$B"/lcm/* "$(dirname "$DB")/"
  tar xzf "$B"/npm-lossless-1.1.0.tgz -C $D/npm/projects
else
  S=$HOME/backups/lcm-111-$P-soft-$(date +%Y%m%d-%H%M%S)
  mkdir -p "$S/state"; cp -p $D/openclaw.json "$S/"
  for f in $D/state/openclaw.sqlite $D/state/openclaw.sqlite-wal; do [ ! -e "$f" ] || cp -p "$f" "$S/state/"; done
  echo "backup nhỏ trước soft: $S"
  echo "== plugins update $SPEC"
  oc plugins update "$SPEC" 2>&1 | grep -vE 'sk-|eyJ' | tail -10 || true
fi

read -r S_SPEC PTH < <(index_spec)
echo "index: $S_SPEC  package: $(jq -r .version "$PTH/package.json")"
[ "$(jq -r .version "$PTH/package.json")" = 1.1.0 ] || { echo "ABORT: package tại installPath không phải 1.1.0 — gateway vẫn DỪNG, báo Claude Code"; exit 1; }
[ "$S_SPEC" = "$SPEC" ] || { echo "ABORT: index không phải $SPEC — gateway vẫn DỪNG, báo Claude Code"; exit 1; }

echo "== start $P"
SINCE=$(date '+%F %T'); systemctl --user start $U; OK=""; J=""
for i in $(seq 1 48); do
  J=$(journalctl --user -u $U --since "$SINCE" --no-pager || true)
  if grep -q "\[gateway\] ready" <<<"$J"; then OK=1; echo "ready sau ~$((i*5))s"; break; fi
  sleep 5
done
[ -n "$OK" ] || { echo "STOP: $P không ready — healthcheck timer vẫn TẮT, báo Claude Code"; grep -iE 'error|fail' <<<"$J" | tail -10 || true; exit 1; }
echo "readyz: $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/readyz)"
[ "$HC_WAS" = active ] && systemctl --user start openclaw-healthcheck.timer || true
echo "healthcheck.timer: $(systemctl --user is-active openclaw-healthcheck.timer || true)"
echo "OK 99 $MODE $P"
