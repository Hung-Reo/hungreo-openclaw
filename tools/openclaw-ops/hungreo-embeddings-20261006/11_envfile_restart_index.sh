#!/bin/bash
# 11 — HƯNG CHẠY sau khi GO. (A) Trả lại EnvironmentFile cho gateway Hungreo (mất từ upgrade 9.8 ngày 03/10 15:39)
# rồi restart; (B) dựng lại index memory cho embeddings mới. Không in giá trị key.
set -uo pipefail
export TZ=Asia/Ho_Chi_Minh
P=/home/hung/.openclaw-hungreo
U=openclaw-gateway-hungreo.service
D=/home/hung/.config/systemd/user/$U.d
ENVF=$P/gateway.systemd.env
OC=/home/hung/bin/openclaw

[ -f "$ENVF" ] || { echo "ABORT: thiếu $ENVF"; exit 1; }
echo "[1/5] drop-in EnvironmentFile (file mới, xoá file này = rollback)"
cat > "$D/zzzz-envfile.conf" <<EOF
# 2026-10-06: upgrade 9.8 (03/10) rewrote override.conf without this line → OpenRouter/TypeSafe/Brave keys missing.
[Service]
EnvironmentFile=-$ENVF
EOF
systemctl --user daemon-reload
systemctl --user show $U -p EnvironmentFiles --value

echo "[2/5] restart Hungreo (tắt healthcheck trong lúc restart)"
systemctl --user stop openclaw-healthcheck.timer
SINCE=$(date "+%F %T")
systemctl --user restart $U
for i in $(seq 1 48); do
  journalctl --user -u $U --since "$SINCE" --no-pager | grep -q "\[gateway\] ready" && { echo "  ready sau ~$((i*5))s"; break; }
  sleep 5
done
systemctl --user start openclaw-healthcheck.timer
PID=$(systemctl --user show $U -p MainPID --value)
echo "  active=$(systemctl --user is-active $U) pid=$PID timer=$(systemctl --user is-active openclaw-healthcheck.timer)"

echo "[3/5] key trong env gateway (chỉ tên)"
for v in $(cut -d= -f1 "$ENVF"); do echo "  $v=$(strings /proc/$PID/environ | grep -c "^$v=")"; done
echo "  SECRETS_DEGRADED sau restart: $(journalctl --user -u $U --since "$SINCE" --no-pager | grep -cE 'SECRETS_(DEGRADED|OWNER_UNAVAILABLE)')"

echo "[4/5] dựng lại index memory (CLI nạp cùng env file để resolve secret)"
date +%T
( set -a; . "$ENVF"; set +a
  OPENCLAW_STATE_DIR=$P OPENCLAW_CONFIG_PATH=$P/openclaw.json timeout 1500 $OC --profile hungreo memory index --force --agent main 2>&1 | grep -viE "sk-|token=" | tail -8
  OPENCLAW_STATE_DIR=$P OPENCLAW_CONFIG_PATH=$P/openclaw.json $OC --profile hungreo memory status --agent main 2>&1 \
    | grep -E "Provider|Indexed|Dirty|Vector search|Index identity" )
date +%T

echo "[5/5] xong — báo Claude Code kiểm (UAT + memory search)"
