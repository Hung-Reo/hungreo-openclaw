#!/bin/bash
# 11 — HƯNG CHẠY sau 10, từng profile: xoá credential anthropic:manual (token sk-ant-oat01 plaintext) khỏi kho auth
# cấp máy state/openclaw.sqlite (config_machine_state.authProfiles.store) bằng CLI chính thức `models auth logout`.
# Không sửa DB tay. Không đụng openai/openrouter. In ra chỉ số đếm, không in token.
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s suckhoe' < 11_logout_profile.sh
set -euo pipefail
trap 'echo "FAILED ở dòng $LINENO — gửi output cho Claude Code"' ERR
P="${1:-}"; case "$P" in hungreo|suckhoe) ;; *) echo "ABORT: tham số phải là hungreo hoặc suckhoe"; exit 1;; esac
export TZ=Asia/Ho_Chi_Minh
HM=$(date +%H%M); if [ "$HM" -ge 0530 ] && [ "$HM" -lt 0700 ]; then echo "ABORT: khung gửi sáng 05:30–07:00"; exit 1; fi
S=/home/hung/.openclaw-$P; C=$S/openclaw.json; U=openclaw-gateway-$P.service
B=/home/hung/backups/anthropic-removal-20261009/$P
export OPENCLAW_STATE_DIR=$S OPENCLAW_CONFIG_PATH=$C
set -a; . $S/gateway.systemd.env; set +a
OC="timeout 120 /home/hung/bin/openclaw --profile $P"
count() { python3 - "$S/state/openclaw.sqlite" <<'PY'
import sqlite3, sys, json
c = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
r = c.execute("select value_json from config_machine_state where state_key='authProfiles.store'").fetchone()
d = json.loads(r[0]) if r else {}
prof = d.get("profiles", {})
import re
print(f"profiles={[re.sub(r'[^:@]+@[^)\\s]+', '<EMAIL>', k) for k in sorted(prof)]} anthropic_in_store={'anthropic:manual' in prof} sk-ant_rows={0 if not r else r[0].count('sk-ant-')}")
PY
}

echo "[1/5] precheck $P"
[ "$(systemctl --user is-active $U)" = active ] || { echo "ABORT: $U không active"; exit 1; }
jq -e '.auth.profiles["anthropic:manual"]' "$C" >/dev/null && { echo "ABORT: config còn khai báo — chạy 10_remove_profile.sh $P trước"; exit 1; }
echo "  trước: $(count)"
PID0=$(systemctl --user show $U -p MainPID --value)

echo "[2/5] backup kho auth (sqlite backup API, chmod 600)"
umask 077; mkdir -p "$B"
python3 - "$S/state/openclaw.sqlite" "$B/state-openclaw.sqlite.pre-anthropic-logout" <<'PY'
import sqlite3, sys
a = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True); b = sqlite3.connect(sys.argv[2]); a.backup(b); b.close(); a.close()
PY
ls -l "$B/state-openclaw.sqlite.pre-anthropic-logout" | awk '{print "  "$1, $5, $9}'

echo "[3/5] models auth logout anthropic:manual"
{ $OC models auth logout anthropic:manual --yes 2>&1 || echo "LOGOUT_RC=$?"; } | grep -v 'sk-ant' | tail -5 || true

echo "[4/5] kiểm"
echo "  sau: $(count)"
$OC models auth list 2>&1 | grep -iE 'anthropic' && echo "  CẢNH BÁO: models auth list vẫn thấy anthropic" || echo "  models auth list: không còn anthropic ✓"
$OC models auth list 2>&1 | grep -E '^- openai' | sed -E 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}/<EMAIL>/g' | sed 's/^/  /'
journalctl --user -u $U --since "-2min" --no-pager | grep -E 'auth|reload|error' | cut -c1-180 | tail -4 || true
echo "  PID $PID0→$(systemctl --user show $U -p MainPID --value) active=$(systemctl --user is-active $U)"

echo "[5/5] UAT model (không gửi Telegram)"
OUT=$($OC agent --json --timeout 150 --session-id "uat-anthropic-logout-$P-$(date +%H%M)" --message "Reply with exactly UAT_OK and nothing else." 2>/dev/null || true)
printf '%s' "$OUT" | jq -r '"  text=\(.result.payloads[0].text // .payloads[0].text // "?") winner=\(.result.meta.executionTrace.winnerProvider // "?")/\(.result.meta.executionTrace.winnerModel // "?") attempts=\(.result.meta.executionTrace.attempts|length? // "?")"' 2>/dev/null || echo "  UAT: không parse được — gửi Claude Code"
echo "OK 11 $P — backup kho auth: $B/state-openclaw.sqlite.pre-anthropic-logout (chứa token cũ; xoá ở bước 20 sau khi revoke)"
