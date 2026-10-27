#!/usr/bin/env bash
# 10 — Gỡ plugin community `hermes-lcm-x` khỏi Hermes (GO Hưng 25/10, phương án A). HƯNG CHẠY:
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s check' < 10_remove.sh   # rehearsal trên BẢN SAO, không đổi live
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s apply' < 10_remove.sh   # rehearsal lại + gỡ thật
# Dùng CLI chính thống của Hermes (config unset context → config unset lcm → plugins disable → plugins remove). KHÔNG restart gateway;
# `disable` chỉ nhờ gateway reload plugin qua socket. Update v0.22.5 đã hoàn tất (update.log) → không đụng.
set -euo pipefail
umask 077
MODE=${1:?check|apply}
case "$MODE" in check|apply) ;; *) echo "ABORT: check|apply"; exit 1;; esac
H=/home/hung/.hermes; HB=/home/hung/.local/bin/hermes; PN=hermes-lcm-x; PL=$H/plugins/$PN
U=hermes-gateway.service
TS=$(TZ=Asia/Ho_Chi_Minh date +%Y%m%d-%H%M%S)
[ "$(hostname)" = srv1367812 ] || { echo "ABORT: sai host"; exit 1; }
exec 9>"$H/.lcmx-remove.lock"; flock -n 9 || { echo "ABORT: đang có 10_remove khác chạy"; exit 1; }
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

state() {  # in trạng thái LCM trong config $1 (yaml) — 1 dòng
  python3 - "$1" <<'PY'
import yaml,sys
c=yaml.safe_load(open(sys.argv[1])) or {}
p=(c.get("plugins") or {})
print(f"context={c.get('context')} lcm={c.get('lcm')} enabled={p.get('enabled')} disabled={p.get('disabled')}")
PY
}
cfgdiff() {  # $1 trước $2 sau → kiểm chỉ đổi context/lcm/plugins.enabled|disabled, và enabled = trước − lcm-x
  python3 - "$1" "$2" <<'PY'
import yaml,sys
a,b=(yaml.safe_load(open(f)) or {} for f in sys.argv[1:3]); out=[]
def w(x,y,p):
    if isinstance(x,dict) and isinstance(y,dict):
        for k in set(x)|set(y): w(x.get(k),y.get(k),p+[str(k)])
    elif x!=y: out.append(".".join(p))
w(a,b,[])
ok=("context","lcm","plugins.enabled","plugins.disabled")
bad=[k for k in out if not any(k==o or k.startswith(o+".") for o in ok)]
print("  khoá đổi:", sorted(out))
assert not bad, f"đổi ngoài phạm vi: {bad}"
ea=(a.get("plugins") or {}).get("enabled") or []; eb=(b.get("plugins") or {}).get("enabled") or []
assert eb==[x for x in ea if x!="hermes-lcm-x"], f"plugins.enabled sau = {eb}"
assert (b.get("context") or {}).get("engine") != "lcm-x", "context.engine vẫn là lcm-x"
assert not b.get("lcm"), "khối lcm còn nội dung"
da=(a.get("plugins") or {}).get("disabled") or []; db=(b.get("plugins") or {}).get("disabled") or []
assert set(db)-set(da) <= {"hermes-lcm-x"} and set(da) <= set(db), f"plugins.disabled đổi lạ: {da} → {db}"
print("  CFG_DIFF_OK (chỉ gỡ LCM-X)")
PY
}
run() {  # $1 = HERMES_HOME → chạy 4 lệnh gỡ, log ra $2
  local HH=$1 LOG=$2
  # unset engine TRƯỚC để lúc disable nhờ gateway reload, config không còn trỏ engine lcm-x
  { echo "+ config unset context" && HERMES_HOME=$HH "$HB" config unset context </dev/null &&
    echo "+ config unset lcm" && HERMES_HOME=$HH "$HB" config unset lcm </dev/null &&
    echo "+ plugins disable" && HERMES_HOME=$HH "$HB" plugins disable "$PN" </dev/null &&
    echo "+ plugins remove" && HERMES_HOME=$HH "$HB" plugins remove "$PN" </dev/null; } > "$LOG" 2>&1
}

echo "== $MODE $(TZ=Asia/Ho_Chi_Minh date '+%F %T')"
# 0) điều kiện
[ "$(systemctl --user is-active $U)" = active ] || { echo "ABORT: $U không active"; exit 1; }
PID0=$(systemctl --user show $U -p MainPID --value); NR0=$(systemctl --user show $U -p NRestarts --value)
[ -x "$HB" ] || { echo "ABORT: không thấy $HB"; exit 1; }
[ -d "$PL" ] && [ ! -L "$PL" ] || { echo "SKIP/ABORT: không có thư mục plugin $PL (đã gỡ?)"; state "$H/config.yaml"; exit 1; }
echo "  live trước: $(state "$H/config.yaml")"
grep -q "hermes-lcm-x" "$H/config.yaml" || { echo "ABORT: config không nhắc tới hermes-lcm-x"; exit 1; }
[ "$(grep -c lcm "$H/profiles/vnstock/config.yaml" 2>/dev/null || true)" = 0 ] || { echo "ABORT: profile vnstock có nhắc lcm — báo Claude"; exit 1; }
for l in /proc/$PID0/fd/*; do t=$(readlink "$l" 2>/dev/null) || continue; case "$t" in "$PL"/*|"$H"/lcm.db*) echo "  ghi chú: gateway đang mở $t (plugin đã nạp live)";; esac; done
ACT=$(journalctl --user -u $U --since "-3 min" --no-pager 2>/dev/null | grep -vE "telegram_network|Managed worktree|^-- " | grep -cE "hermes\[" || true)
[ "$ACT" = 0 ] || { echo "ABORT: Hermes có $ACT dòng log trong 3 phút qua (đang bận) — chờ rảnh rồi chạy lại"; exit 1; }
livehash() { { sha256sum "$H/config.yaml" "$H/plugins/.install-metadata.json"; tar -C "$H/plugins" -cf - "$PN" 2>/dev/null | sha256sum; } | awk '{print $1}' | tr '\n' ' '; }
LH0=$(livehash)

# 1) rehearsal trên bản sao (ngoài ~/.hermes/profiles; KHÔNG chép socket) → reload không chạm gateway thật
RC=$(mktemp -d /home/hung/hermes-rh-lcmx.XXXXXX)
cleanup() { [ -n "${RC:-}" ] && [ -d "$RC" ] && rm -rf -- "$RC"; true; }
trap cleanup EXIT
cp -p "$H/config.yaml" "$H/.env" "$RC/"; cp -a "$H/plugins" "$RC/plugins"
J0=$(date '+%F %T')
if run "$RC" "$RC/rehearsal.log"; then echo "  rehearsal: 4 lệnh chạy xong"; else echo "  REHEARSAL_FAIL: $(tail -4 "$RC/rehearsal.log" | tr '\n' ' ' | cut -c1-300)"; exit 1; fi
grep -E "disabled|removed|refused|answered|unset|Removed" "$RC/rehearsal.log" | sed 's/^/    /' | cut -c1-200 || true
cfgdiff "$H/config.yaml" "$RC/config.yaml"
[ ! -e "$RC/plugins/$PN" ] || { echo "  FAIL: rehearsal chưa xoá thư mục plugin"; exit 1; }
! grep -q hermes-lcm-x "$RC/plugins/.install-metadata.json" || { echo "  FAIL: metadata bản sao còn hermes-lcm-x"; exit 1; }
echo "  metadata bản sao không còn hermes-lcm-x"
[ "$(livehash)" = "$LH0" ] || { echo "  FAIL: config/metadata/plugin LIVE đổi trong rehearsal!"; exit 1; }
echo "  hash live (config, metadata, plugin) không đổi qua rehearsal ✓"
sleep 2
JR=$(journalctl --user -u $U --since "$J0" --no-pager 2>/dev/null || true)
grep -qiE "reload-plugins|reloaded .*plugins|re-discover" <<<"$JR" && { echo "  FAIL: rehearsal đã chạm gateway thật (reload)"; exit 1; } || echo "  gateway thật không bị reload trong rehearsal ✓"
[ "$(systemctl --user show $U -p MainPID --value)" = "$PID0" ] || { echo "  FAIL: PID gateway đổi trong rehearsal"; exit 1; }
cleanup; RC=
if [ "$MODE" = check ]; then echo "CHECK OK — bản sao đã xoá, live chưa đổi gì"; exit 0; fi

# 2) backup live (giữ để 99 khôi phục)
B=$H/backups/lcmx-remove-$TS; mkdir -m 700 "$B"
cp -p "$H/config.yaml" "$B/config.yaml"
cp -p "$H/plugins/.install-metadata.json" "$B/install-metadata.json"
tar -C "$H/plugins" -cpf "$B/plugin-hermes-lcm-x.tar" "$PN"
for f in lcm.db; do [ -f "$H/$f" ] && python3 - "$H/$f" "$B/$f" <<'PY'
import sqlite3,sys
a=sqlite3.connect("file:"+sys.argv[1]+"?mode=ro",uri=True); b=sqlite3.connect(sys.argv[2]); a.backup(b); b.close(); a.close()
PY
done
(cd "$B" && sha256sum * > SHA256SUMS && sha256sum -c --quiet SHA256SUMS)
echo "BACKUP=$B"

# 3) gỡ thật trên live
J1=$(date '+%F %T')
if run "$H" "$B/apply.log"; then echo "  apply: 4 lệnh chạy xong"; else echo "  APPLY_FAIL: $(tail -4 "$B/apply.log" | tr '\n' ' ' | cut -c1-300)"; echo "  Rollback: ssh … 'bash -s $B' < 99_rollback.sh"; exit 1; fi
grep -E "disabled|removed|refused|answered|Removed" "$B/apply.log" | sed 's/^/    /' | cut -c1-220 || true
cfgdiff "$B/config.yaml" "$H/config.yaml" || { echo "  Rollback: ssh … 'bash -s $B' < 99_rollback.sh"; exit 1; }
[ ! -e "$PL" ] || { echo "  FAIL: thư mục plugin còn"; exit 1; }
# lcm.db do LCM-X tạo (0 msg) → cất vào backup nếu không ai mở
if [ -f "$H/lcm.db" ]; then
  busy=0; for l in /proc/[0-9]*/fd/*; do t=$(readlink "$l" 2>/dev/null) || continue; case "$t" in "$H"/lcm.db*) busy=1;; esac; done
  if [ $busy = 0 ]; then for f in "$H"/lcm.db "$H"/lcm.db-wal "$H"/lcm.db-shm; do [ -e "$f" ] && mv "$f" "$B/live-$(basename "$f")"; done; echo "  lcm.db* → $B/live-*"
  else echo "  ghi chú: lcm.db đang được mở — để nguyên (vô hại khi plugin đã gỡ)"; fi
fi

# 4) readback
echo "  live sau: $(state "$H/config.yaml")"
timeout 90 "$HB" plugins list --plain --no-bundled 2>/dev/null | grep -v "applied .* secrets" | sed 's/^/    /' || true
JA=$(journalctl --user -u $U --since "$J1" --no-pager 2>/dev/null || true)
echo "  gateway: $(systemctl --user is-active $U) pid $PID0 → $(systemctl --user show $U -p MainPID --value) NRestarts $NR0 → $(systemctl --user show $U -p NRestarts --value); log lỗi sau gỡ: $(grep -ciE 'error|traceback' <<<"$JA" || true)"
sha256sum "$H/config.yaml" "$H/plugins/.install-metadata.json" > "$B/post-apply.sha256"
echo "OK 10 — LCMX_REMOVED backup=$B"
echo "Rollback: ssh … 'bash -s $B' < 99_rollback.sh"
