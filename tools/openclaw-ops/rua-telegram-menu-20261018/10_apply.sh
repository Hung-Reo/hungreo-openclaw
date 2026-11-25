#!/bin/bash
# 10 — HƯNG CHẠY: ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 10_apply.sh
#   (chỉ kiểm, không ghi:  'bash -s check' < 10_apply.sh)
# Rùa (Hungreo): đặt channels.telegram.commands.nativeSkills=false → bỏ 47 lệnh skill riêng khỏi menu Telegram
# (giữ /skill), để menu từ 111 xuống ~64 lệnh và /lossless, /lcm cùng lệnh plugin khác không bị cắt ở mốc 100.
# Hot reload kênh telegram (không restart gateway). Không đổi model/auth/fallback/Suckhoe/Nemo.
set -euo pipefail
export TZ=Asia/Ho_Chi_Minh
MODE=${1:-apply}
P=hungreo; D=$HOME/.openclaw-$P; C=$D/openclaw.json; U=openclaw-gateway-$P.service
KEY=channels.telegram.commands.nativeSkills
EXPECT=7e281f81   # sha256 8 ký tự openclaw.json lúc soạn (18/10)
set -a; . $D/gateway.systemd.env; set +a
export OPENCLAW_STATE_DIR=$D OPENCLAW_CONFIG_PATH=$C
OC() { timeout 120 /home/hung/bin/openclaw --profile $P "$@" </dev/null; }
menu() {  # in: số lệnh + có lossless/lcm/lossless_claw không (token không in)
  curl -s --max-time 20 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMyCommands" |
    python3 -c 'import json,sys;d=json.load(sys.stdin);c=[x["command"] for x in d.get("result",[])];print("ok=%s n=%d lossless=%s lcm=%s lossless_claw=%s skill=%s"%(d.get("ok"),len(c),"lossless" in c,"lcm" in c,"lossless_claw" in c,"skill" in c))' 2>/dev/null
}

H=$(date +%H%M)
if [ "$MODE" = apply ] && { { [ "$H" -ge 0535 ] && [ "$H" -le 0720 ]; } || { [ "$H" -ge 1635 ] && [ "$H" -le 1655 ]; }; }; then
  echo "ABORT: đang trong khung job Rùa (05:35–07:20, 16:35–16:55) — chạy lại sau"; exit 1; fi
[ "$(systemctl --user is-active $U)" = active ] || { echo "ABORT: $U không active"; exit 1; }
PID0=$(systemctl --user show $U -p MainPID --value)
CUR=$(sha256sum $C | cut -c1-8)
VAL=$(jq -c '.channels.telegram.commands.nativeSkills' $C)
echo "== precheck $(date '+%F %T') pid=$PID0 config=$CUR nativeSkills=$VAL"
echo "menu trước: $(menu || echo 'menu lỗi')"
if [ "$VAL" = false ]; then echo "SKIP: đã là false, không đổi gì"; exit 0; fi
[ "$CUR" = "$EXPECT" ] || { echo "ABORT: openclaw.json đổi từ lúc soạn ($CUR ≠ $EXPECT) — báo Claude"; exit 1; }
[ "$VAL" = null ] || { echo "ABORT: giá trị hiện tại không phải null ($VAL)"; exit 1; }
TMPD=$(mktemp)
if OC config set $KEY false --strict-json --dry-run >"$TMPD" 2>&1; then rc=0; else rc=$?; fi
tail -1 "$TMPD"; rm -f "$TMPD"
[ $rc = 0 ] || { echo "ABORT: dry-run lỗi rc=$rc"; exit 1; }
[ "$(sha256sum $C | cut -c1-8)" = "$EXPECT" ] || { echo "ABORT: dry-run làm đổi file?!"; exit 1; }
if [ "$MODE" = check ]; then echo "CHECK OK — chưa ghi gì"; exit 0; fi

B=$HOME/backups/rua-telegram-menu-$(date +%Y%m%d-%H%M%S); mkdir -p "$B"; chmod 700 "$B"
cp -p $C "$B/openclaw.json"
[ "$(sha256sum "$B/openclaw.json" | cut -c1-8)" = "$EXPECT" ] || { echo "ABORT: backup lệch hash"; exit 1; }
echo "BACKUP=$B"
RB="Rollback: ssh … 'bash -s $B' < 99_rollback.sh   (nếu đổi lạ ngoài khoá: cp -p $B/openclaw.json $C)"
T0=$(date '+%F %T')

if OC config set $KEY false --strict-json >/dev/null 2>"$B/set.err"; then rc=0; else rc=$?; fi
[ $rc = 0 ] || { echo "FAILED: config set rc=$rc ($(tail -1 "$B/set.err"))"; echo "$RB"; exit 1; }
NV=$(jq -c '.channels.telegram.commands.nativeSkills' $C)
echo "-- readback: $KEY=$NV"
[ "$NV" = false ] || { echo "FAILED: readback ≠ false"; echo "$RB"; exit 1; }
CHG=$(python3 - "$B/openclaw.json" "$C" <<'PY'
import json,sys
a,b=(json.load(open(f)) for f in sys.argv[1:3])
out=[]
def walk(x,y,p):
    if isinstance(y,dict) and not isinstance(x,dict): x={}
    if isinstance(x,dict) and not isinstance(y,dict): y={}
    if isinstance(x,dict) and isinstance(y,dict):
        for k in set(x)|set(y): walk(x.get(k),y.get(k),p+[k])
    elif x!=y: out.append(".".join(p))
walk(a,b,[]); print(" ".join(sorted(k for k in out if k!="meta" and not k.startswith("meta."))))
PY
) || CHG="<diff lỗi>"
echo "-- khoá đổi (bỏ meta.*): ${CHG:-<none>}"
[ "$CHG" = "$KEY" ] || { echo "FAILED: đổi ngoài dự kiến"; echo "$RB"; exit 1; }

echo "-- chờ hot reload (tối đa 90s)"
J=""
for i in $(seq 1 18); do
  sleep 5
  J=$(journalctl --user -u $U --since "$T0" --no-pager 2>/dev/null) || J=""
  grep -qE 'reload\].*(applied|restart)' <<<"$J" && break
done
grep -E '\[reload\]|\[telegram\].*(limits bots|menu text|commands)' <<<"$J" | cut -c1-200 | tail -6 || true
echo "-- menu sau (đợi sync tối đa 60s)"
M=""
for i in $(seq 1 12); do M=$(menu) || M="menu lỗi"; grep -q 'lossless=True' <<<"$M" && break; sleep 5; done
echo "menu sau: $M"
PID1=$(systemctl --user show $U -p MainPID --value)
echo "gateway: $(systemctl --user is-active $U || true) pid $PID0 → $PID1 (kỳ vọng giữ nguyên) readyz=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18789/readyz || true)"
if grep -q 'lossless=True lcm=True' <<<"$M"; then
  echo "OK 10 — UAT: Hưng mở menu '/' của Rùa thấy /lossless, /lcm; gõ /lossless; gõ /skill lossless_claw"
else
  echo "CHƯA ĐẠT: menu chưa có /lossless — gửi output cho Claude (không rollback vội; có thể menu sync chậm)"
fi
echo "$RB"
