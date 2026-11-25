#!/usr/bin/env bash
# 99 — Nemo LCM 1.2.0 → 1.1.1: khôi phục config/workspace (gồm lcm.db trước migrate + bản ghi cài plugin) từ backup của 20, start lại cùng container.
# ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash /home/hung/sandbox-nemo/ops-lcm120-20261022/99_rollback.sh <BACKUP_DIR>'
# Lưu ý: tin/tóm tắt LCM phát sinh SAU lúc backup nằm ở *.failed-lcm120-*, không mất nhưng không còn trong bot.
set -Eeuo pipefail
S=/home/hung/sandbox-nemo
T=$S/ops-lcm120-20261022
B=${1:-$(cat "$T/backup-path")}
TS=$(TZ=Asia/Ho_Chi_Minh date +%Y%m%d-%H%M%S)
[ "$(hostname)" = srv1367812 ] || { echo "ABORT: sai host"; exit 1; }
case "$B" in /home/hung/backups/nemo-lcm120-[0-9]*) ;; *) echo "ABORT: $B không phải backup của việc này"; exit 1;; esac
[ -f "$B/config.tar" ] && [ -f "$B/workspace.tar" ] || { echo "ABORT: backup thiếu tar"; exit 1; }
(cd "$B" && sha256sum -c --quiet SHA256SUMS) || { echo "ABORT: SHA256 backup lệch"; exit 1; }
docker inspect nemo-sandbox >/dev/null 2>&1 || { echo "ABORT: không thấy container nemo-sandbox"; exit 1; }
rt=$(docker inspect nemo-sandbox --format '{{range .Mounts}}{{if eq .Destination "/sandbox/runtime"}}{{.Source}}{{end}}{{end}}')
[ "$rt" = "$S/runtime-10.5" ] || { echo "ABORT: nemo-sandbox mount runtime lạ ($rt) — báo Claude"; exit 1; }
oauth_hours() {  # giờ còn lại của OAuth Nemo (đọc từ container đang chạy)
  docker exec nemo-sandbox node /sandbox/runtime/node_modules/openclaw/dist/entry.js models auth list --json < /dev/null 2>/dev/null | python3 -c '
import json,sys,datetime as dt
s=sys.stdin.read(); d=None
for i,ch in enumerate(s):
    if ch in "[{":
        try: d,_=json.JSONDecoder().raw_decode(s[i:]); break
        except Exception: pass
ex=[]
def walk(o):
    if isinstance(o,dict):
        for k,v in o.items():
            if k.lower() in ("expires","expiresat","expires_at") and isinstance(v,(int,float,str)): ex.append(v)
            else: walk(v)
    elif isinstance(o,list):
        for v in o: walk(v)
walk(d); ts=[]
for e in ex:
    try: t=dt.datetime.fromtimestamp(e/1000 if e>1e11 else e,dt.timezone.utc) if isinstance(e,(int,float)) else dt.datetime.fromisoformat(str(e).replace("Z","+00:00"))
    except Exception: continue
    if t.year>2000: ts.append(t)
print(f"{(min(ts)-dt.datetime.now(dt.timezone.utc)).total_seconds()/3600:.0f} {min(ts):%Y-%m-%dT%H:%M}Z" if ts else "? ?")'
}
read -r _ OEXP_NOW < <(oauth_hours || echo "? ?")
docker stop -t 60 nemo-sandbox >/dev/null || true
mv "$S/config" "$S/config.failed-lcm120-$TS"
tar -C "$S" -xpf "$B/config.tar"
# workspace KHÔNG khôi phục (plugins update không đụng workspace; giữ file agent ghi sau cutover). Tar vẫn ở $B/workspace.tar nếu cần.
docker start nemo-sandbox >/dev/null
for i in $(seq 1 90); do
  if [ "$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:18796/readyz || true)" = 200 ]; then
    v=$(docker exec nemo-sandbox node -e 'console.log(require("/sandbox/runtime/node_modules/openclaw/package.json").version)' || echo '?')
    l=$(python3 - <<'PYI' || echo '?'
import sqlite3,json
db=sqlite3.connect("file:/home/hung/sandbox-nemo/config/state/openclaw.sqlite?mode=ro",uri=True)
print(json.loads(db.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()[0])["index"]["installRecords"]["lossless-claw"]["version"])
PYI
)
    read -r _ OEXP_AFTER < <(oauth_hours || echo "? ?")
    if [ "$OEXP_NOW" != "?" ] && [ "$OEXP_AFTER" != "$OEXP_NOW" ]; then
      echo "CẢNH BÁO RE-AUTH NGAY: OAuth trước rollback hết hạn $OEXP_NOW, sau khi khôi phục backup là $OEXP_AFTER — token cũ có thể đã bị thu hồi (refresh_token_reused). Hưng login lại OpenAI cho Nemo."
    fi
    [ "$v" = 2026.10.5 ] && [ "$l" = 1.1.1 ] && { echo "OK 99 — ROLLBACK_LCM_111_READY (core $v; state lỗi cất ở *.failed-lcm120-$TS)"; exit 0; }
    echo "FAILED: lên nhưng core=$v lcm=$l — báo Claude"; exit 1
  fi
  sleep 2
done
echo "ROLLBACK_NOT_READY — báo Claude"; exit 1
