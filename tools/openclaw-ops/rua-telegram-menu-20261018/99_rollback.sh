#!/bin/bash
# 99 — HƯNG CHẠY nếu cần: ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s <BACKUP_DIR>' < 99_rollback.sh
# Bỏ channels.telegram.commands.nativeSkills (về mặc định "auto" như trước) bằng CLI unset; hot reload kênh telegram.
set -euo pipefail
export TZ=Asia/Ho_Chi_Minh
P=hungreo; D=$HOME/.openclaw-$P; C=$D/openclaw.json; U=openclaw-gateway-$P.service
KEY=channels.telegram.commands.nativeSkills
B=${1:?cần BACKUP_DIR do 10_apply.sh in ra}
case "$B" in "$HOME"/backups/rua-telegram-menu-[0-9]*) ;; *) echo "ABORT: $B không phải backup của việc này"; exit 1;; esac
[ -f "$B/openclaw.json" ] || { echo "ABORT: không thấy $B/openclaw.json"; exit 1; }
[ "$(sha256sum "$B/openclaw.json" | cut -c1-8)" = 7e281f81 ] || { echo "ABORT: backup không đúng bản gốc 7e281f81"; exit 1; }
set -a; . $D/gateway.systemd.env; set +a
export OPENCLAW_STATE_DIR=$D OPENCLAW_CONFIG_PATH=$C
OC() { timeout 120 /home/hung/bin/openclaw --profile $P "$@" </dev/null; }
VAL=$(jq -c '.channels.telegram.commands.nativeSkills' $C)
echo "hiện tại: $KEY=$VAL"
if [ "$VAL" = null ]; then echo "SKIP: khoá đã không còn, không đổi gì"; exit 0; fi
cp -p $C "$B/openclaw.json.pre-rollback-$(date +%H%M%S)"
if OC config unset $KEY --dry-run >/dev/null 2>&1; then :; else echo "ABORT: dry-run unset lỗi"; exit 1; fi
T0=$(date '+%F %T')
if OC config unset $KEY >/dev/null 2>"$B/unset.err"; then rc=0; else rc=$?; fi
[ $rc = 0 ] || { echo "FAILED: unset rc=$rc ($(tail -1 "$B/unset.err")) — khôi phục tay: cp -p $B/openclaw.json $C"; exit 1; }
NV=$(jq -c '.channels.telegram.commands.nativeSkills' $C)
echo "readback: $KEY=$NV"
[ "$NV" = null ] || { echo "FAILED: readback ≠ null — khôi phục tay: cp -p $B/openclaw.json $C"; exit 1; }
J=""
for i in $(seq 1 18); do sleep 5; J=$(journalctl --user -u $U --since "$T0" --no-pager 2>/dev/null) || J=""; grep -qE 'reload\].*(applied|restart)' <<<"$J" && break; done
grep -E '\[reload\]|\[telegram\].*(limits bots|menu text)' <<<"$J" | cut -c1-200 | tail -4 || true
sleep 10
M=$(curl -s --max-time 20 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMyCommands" |
  python3 -c 'import json,sys;d=json.load(sys.stdin);c=[x["command"] for x in d.get("result",[])];print("menu: n=%d lossless_claw=%s"%(len(c),"lossless_claw" in c))' 2>/dev/null) || M="menu lỗi"
echo "$M"
echo "OK 99 — gateway $(systemctl --user is-active $U || true) readyz=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18789/readyz || true)"
