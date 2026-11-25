#!/bin/bash
# 10 — HƯNG CHẠY, từng profile: gỡ khai báo auth.profiles."anthropic:manual" khỏi openclaw.json.
# Phạm vi đúng 1 key; không đụng model/fallback/auth khác, không xoá file token cũ (việc đó là bước 20, GO riêng).
# Chạy (suckhoe trước, hungreo sau; tránh 05:30–07:00):
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s suckhoe' < 10_remove_profile.sh
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s hungreo' < 10_remove_profile.sh
set -euo pipefail
trap 'echo "FAILED ở dòng $LINENO — gửi output cho Claude Code"' ERR
P="${1:-}"; case "$P" in hungreo|suckhoe) ;; *) echo "ABORT: tham số phải là hungreo hoặc suckhoe"; exit 1;; esac
export TZ=Asia/Ho_Chi_Minh
HM=$(date +%H%M); if [ "$HM" -ge 0530 ] && [ "$HM" -lt 0700 ]; then echo "ABORT: đang trong khung gửi sáng 05:30–07:00"; exit 1; fi
S=/home/hung/.openclaw-$P; C=$S/openclaw.json; U=openclaw-gateway-$P.service
B=/home/hung/backups/anthropic-removal-20261009/$P; KEY='auth.profiles.anthropic:manual'
export OPENCLAW_STATE_DIR=$S OPENCLAW_CONFIG_PATH=$C
set -a; . $S/gateway.systemd.env; set +a
OC="timeout 120 /home/hung/bin/openclaw --profile $P"
pid() { systemctl --user show $U -p MainPID --value; }

echo "[1/6] precheck $P"
[ "$(systemctl --user is-active $U)" = active ] || { echo "ABORT: $U không active"; exit 1; }
if ! jq -e '.auth.profiles["anthropic:manual"]' "$C" >/dev/null; then echo "Không còn anthropic:manual trong config — đã gỡ từ trước, dừng."; exit 0; fi
REFS=$(jq -r 'paths(scalars) as $p | [$p[]|tostring]|join(".")' "$C" | grep -i anthropic | grep -v '^auth\.profiles\.anthropic:manual\.' || true)
[ -z "$REFS" ] || { echo "ABORT: còn chỗ khác tham chiếu anthropic: $REFS"; exit 1; }
PID0=$(pid); echo "  config chỉ có đúng auth.profiles.anthropic:manual ✓  PID=$PID0"

echo "[2/6] backup"
umask 077; mkdir -p "$B"
cp -p "$C" "$B/openclaw.json.pre-anthropic-removal"
sha256sum "$B/openclaw.json.pre-anthropic-removal" | cut -c1-16

echo "[3/6] gỡ key (CLI, có validate)"
{ $OC config unset "$KEY" 2>&1 || echo "CONFIG_UNSET_RC=$?"; } | grep -vE 'sk-ant' | tail -4 || true

echo "[4/6] DIFF: chỉ được khác đúng key anthropic:manual"
D=$(diff <(jq -S 'del(.auth.profiles["anthropic:manual"], .meta)' "$B/openclaw.json.pre-anthropic-removal") <(jq -S 'del(.meta)' "$C") || true)
if [ -n "$D" ]; then echo "DIFF NGOÀI DỰ KIẾN:"; echo "$D" | head -20; echo "→ rollback"; cp -p "$B/openclaw.json.pre-anthropic-removal" "$C"; exit 1; fi
jq -e '.auth.profiles["anthropic:manual"]' "$C" >/dev/null && { echo "ABORT: key vẫn còn"; exit 1; }
echo "  diff đúng 1 key ✓  model.primary=$(jq -r .agents.defaults.model.primary "$C") fallbacks=$(jq -c .agents.defaults.model.fallbacks "$C")"

echo "[5/6] chờ gateway nạp lại (tối đa 120s)"
for i in $(seq 1 24); do sleep 5
  [ "$(systemctl --user is-active $U)" = active ] && curl -fsS -m 3 "http://127.0.0.1:$(jq -r .gateway.port "$C")/readyz" >/dev/null 2>&1 && break
done
PID1=$(pid); echo "  active=$(systemctl --user is-active $U) PID $PID0→$PID1 readyz=$(curl -s -o /dev/null -w '%{http_code}' -m 3 http://127.0.0.1:$(jq -r .gateway.port "$C")/readyz)"
journalctl --user -u $U --since "-3min" --no-pager | grep -E '\[reload\]|SECRETS_DEGRADED|Invalid|error' | cut -c1-200 | tail -5 || true
$OC models auth list 2>&1 | grep -iE 'anthropic' && { echo "CẢNH BÁO: models auth list vẫn thấy anthropic"; } || echo "  models auth list: không còn anthropic ✓"

echo "[6/6] UAT model (không gửi Telegram)"
OUT=$($OC agent --json --timeout 150 --session-id "uat-anthropic-removal-$P-$(date +%H%M)" --message "Reply with exactly UAT_OK and nothing else." 2>/dev/null || true)
printf '%s' "$OUT" | jq -r '"  text=\(.result.payloads[0].text // .payloads[0].text // "?") winner=\(.result.meta.executionTrace.winnerProvider // "?")/\(.result.meta.executionTrace.winnerModel // "?") attempts=\(.result.meta.executionTrace.attempts|length? // "?")"' 2>/dev/null || echo "  UAT: không parse được output — gửi Claude Code"
echo "OK 10 $P — backup $B. Rollback: cp -p $B/openclaw.json.pre-anthropic-removal $C"
