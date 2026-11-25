#!/bin/bash
# 02 — HƯNG CHẠY (gateway đang dừng). Cập nhật + ghim plugin 9.6 → 9.8 bằng spec chính xác; chuyển skill google-sheets ra backup (Q3).
# KHÔNG đụng codex (giữ nguyên để test restart với lỗi 403 Suckhoe không bị lẫn biến số).
set -euo pipefail
trap 'echo "FAILED ở dòng $LINENO — gateways vẫn DỪNG, timer vẫn TẮT. Gửi output cho Claude Code, chưa chạy 03."' ERR
export TZ=Asia/Ho_Chi_Minh
OC=/home/hung/bin/openclaw
B=/home/hung/backups/maint-20261004-plugins
[ -f "$B/SHA256SUMS" ] || { echo "ABORT: chưa có backup 01"; exit 1; }
for s in hungreo suckhoe; do
  [ "$(systemctl --user is-active openclaw-gateway-$s.service || true)" != "active" ] || { echo "ABORT: $s đang chạy"; exit 1; }
done

upd() { # profile specs...
  local p=$1; shift
  echo "== $p: plugins update $*"
  OPENCLAW_STATE_DIR=$HOME/.openclaw-$p OPENCLAW_CONFIG_PATH=$HOME/.openclaw-$p/openclaw.json \
    timeout 300 $OC --profile $p plugins update "$@" < /dev/null
}
upd hungreo @openclaw/brave-plugin@2026.9.8 @openclaw/deepseek-provider@2026.9.8 @openclaw/parallel-plugin@2026.9.8 @openclaw/typesafe@2026.9.8
upd suckhoe @openclaw/brave-plugin@2026.9.8 @openclaw/deepseek-provider@2026.9.8

echo "== Q3: move skill google-sheets (hungreo) -> backup"
mkdir -p "$B/skills"
mv /home/hung/.openclaw-hungreo/workspace/skills/google-sheets "$B/skills/google-sheets"
ls -d "$B/skills/google-sheets"

echo "== config DIFF vs backup (expect: không đổi model/auth/fallback)"
for p in hungreo suckhoe; do
python3 - "$HOME/.openclaw-$p/openclaw.json" "$B/$p/openclaw.json" "$p" <<'EOF'
import json, sys
def flat(d, p=""):
    o = {}
    if isinstance(d, dict):
        for k, v in d.items(): o.update(flat(v, p + "." + k))
    else: o[p] = d
    return o
a = flat(json.load(open(sys.argv[1]))); b = flat(json.load(open(sys.argv[2])))
ks = [k for k in sorted(set(a) | set(b)) if a.get(k) != b.get(k)]
sens = lambda k: any(x in k.lower() for x in ("token", "key", "secret", "password"))
print(sys.argv[3], "changed keys:", len(ks))
for k in ks: print("  ", k, "| old=", "<R>" if sens(k) else b.get(k), "| new=", "<R>" if sens(k) else a.get(k))
EOF
done

echo "== versions after update"
for p in hungreo suckhoe; do
  OPENCLAW_STATE_DIR=$HOME/.openclaw-$p timeout 90 $OC --profile $p plugins list --json 2>/dev/null |
    python3 -c 'import json,sys;d=json.load(sys.stdin);ps=d.get("plugins",d);print(sys.argv[1],{x["id"]:x.get("version") for x in ps if x.get("origin")=="global"})' $p
done
echo "OK 02 — gateways vẫn DỪNG. Gửi output cho Claude Code xem DIFF trước khi chạy 03_start.sh"
