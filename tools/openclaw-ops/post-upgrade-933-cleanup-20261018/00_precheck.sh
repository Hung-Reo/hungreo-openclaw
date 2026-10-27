#!/bin/bash
# 00_precheck.sh — READ-ONLY + dry-run thật cho cả suckhoe và hungreo trước khi stop dịch vụ.
set -euo pipefail
export TZ=Asia/Ho_Chi_Minh
OC=/home/hung/bin/openclaw

oc_profile() {
  local P="$1"; shift
  local D="$HOME/.openclaw-$P"
  local PORT=$([ "$P" = suckhoe ] && echo 18795 || echo 18789)
  (
    for v in $(compgen -v OPENCLAW_ 2>/dev/null || true); do unset "$v"; done
    unset TELEGRAM_BOT_TOKEN
    set -a
    [ -f "$D/gateway.systemd.env" ] && . "$D/gateway.systemd.env"
    set +a
    OPENCLAW_PROFILE="$P" OPENCLAW_STATE_DIR="$D" OPENCLAW_CONFIG_PATH="$D/openclaw.json" \
      OPENCLAW_GATEWAY_PORT="$PORT" OPENCLAW_SYSTEMD_UNIT="openclaw-gateway-$P.service" \
      timeout 180 "$OC" --profile "$P" "$@" < /dev/null
  )
}

for P in suckhoe hungreo; do
  U="openclaw-gateway-$P.service"
  D="$HOME/.openclaw-$P"
  echo "=== [PRECHECK] $P ($(date '+%F %T')) ==="
  echo "  service: $(systemctl --user is-active "$U") pid=$(systemctl --user show "$U" -p MainPID --value)"
  if [ "$P" = suckhoe ]; then
    SPECS=("@openclaw/brave-plugin@2026.9.33" "@openclaw/deepseek-provider@2026.9.33")
  else
    SPECS=("@openclaw/brave-plugin@2026.9.33" "@openclaw/deepseek-provider@2026.9.33" "@openclaw/parallel-plugin@2026.9.33" "@openclaw/typesafe@2026.9.33")
  fi
  for S in "${SPECS[@]}"; do
    OUT=$(oc_profile "$P" plugins update "$S" --dry-run 2>&1 | grep -vE 'sk-|eyJ' || true)
    LINE=$(grep -i 'would update' <<<"$OUT" | head -1 || true)
    echo "  dry-run $S -> $LINE"
    grep -q "2026.9.8 -> 2026.9.33" <<<"$OUT" || { echo "ABORT: dry-run $S không khớp 2026.9.8 -> 2026.9.33"; exit 1; }
  done
  python3 - "$D/state/openclaw.sqlite" "$D/lcm.db" <<'PY'
import sqlite3, sys
for db in sys.argv[1:]:
    con = sqlite3.connect("file:" + db + "?mode=ro", uri=True)
    try:
        qc = con.execute("pragma quick_check").fetchone()[0]
        print(f"  quick_check {db.split('/')[-1]}: {qc}")
        if qc != "ok":
            sys.exit(1)
    finally:
        con.close()
PY
done
echo "PRECHECK_ALL_OK"
