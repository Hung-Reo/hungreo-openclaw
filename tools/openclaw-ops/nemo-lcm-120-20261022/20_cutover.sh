#!/usr/bin/env bash
# 20 — HƯNG CHẠY (nền, CHỈ 1 LẦN) sau 16 PASS: Nemo LCM 1.1.1 → 1.2.0, core 10.5 giữ nguyên (cùng container, không đổi runtime).
# ssh … 'setsid nohup bash /home/hung/sandbox-nemo/ops-lcm120-20261022/20_cutover.sh > /home/hung/sandbox-nemo/ops-lcm120-20261022/cutover.log 2>&1 < /dev/null &'
# Không đụng Hungreo/Suckhoe/Hermes. Downtime Nemo ~3–4 phút (stop → backup → chờ lease ≥100s → update → start).
set -Eeuo pipefail
umask 077
S=/home/hung/sandbox-nemo
R=$S/runtime-10.5
T=$S/ops-lcm120-20261022
IMG=node:24.21.0-bookworm-slim
CA=/etc/ssl/certs/ca-certificates.crt
TS=$(TZ=Asia/Ho_Chi_Minh date +%Y%m%d-%H%M%S)
B=/home/hung/backups/nemo-lcm120-$TS
LCM_NEW="@martian-engineering/lossless-claw@1.2.0"
LOCK=$T/.cutover.lock

ver() { docker exec nemo-sandbox node -e 'console.log(require("/sandbox/runtime/node_modules/openclaw/package.json").version)'; }
lcmidx() {
  python3 - "$1" <<'PYI'
import sqlite3,json,sys,pathlib
db=sqlite3.connect((pathlib.Path(sys.argv[1])/"state/openclaw.sqlite").as_uri()+"?mode=ro",uri=True)
idx=json.loads(db.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()[0])["index"]["installRecords"]
print(idx.get("lossless-claw",{}).get("version"), idx.get("codex",{}).get("version"))
PYI
}
[ "$(hostname)" = srv1367812 ] || { echo "ABORT: sai host"; exit 1; }
# chặn chạy chồng (lệnh nền dễ bị bấm 2 lần)
exec 9>"$LOCK"; flock -n 9 || { echo "ABORT: đang có một 20_cutover khác chạy"; exit 1; }
[ -f "$T/rehearsal-pass" ] || { echo "ABORT: chưa có 16_rehearsal.sh PASS"; exit 1; }
read -r RTS RH0 RMODE < "$T/rehearsal-pass" || true
[ "${RMODE:-}" = lcm120 ] || { echo "ABORT: marker không phải rehearsal lcm120"; exit 1; }
[ -n "${RTS:-}" ] && [ $(( $(date +%s) - RTS )) -lt 86400 ] || { echo "ABORT: rehearsal PASS đã quá 24h — chạy lại 16"; exit 1; }
[ "${RH0:-}" = "$(sha256sum "$S/config/openclaw.json" | cut -c1-16)" ] || { echo "ABORT: openclaw.json đổi từ lúc rehearsal — chạy lại 16"; exit 1; }
[ -f "$T/99_rollback.sh" ] || { echo "ABORT: thiếu $T/99_rollback.sh"; exit 1; }
CUR=$(ver || true); [ "$CUR" = 2026.10.5 ] || { echo "ABORT: Nemo đang chạy '$CUR', không phải 10.5"; exit 1; }
[ "$(docker inspect nemo-sandbox --format '{{range .Mounts}}{{if eq .Destination "/sandbox/runtime"}}{{.Source}}{{end}}{{end}}')" = "$R" ] || { echo "ABORT: mount runtime không phải runtime-10.5"; exit 1; }
[ "$(lcmidx "$S/config")" = "1.1.1 2026.10.5" ] || { echo "ABORT: index hiện tại không phải LCM 1.1.1 + codex 10.5"; exit 1; }
[ "$(free -m | awk '/^Mem:/{print $7}')" -ge 1200 ] || { echo "ABORT: RAM available < 1200 MiB"; exit 1; }
[ "$(df --output=avail -BG / | tail -1 | tr -dc 0-9)" -ge 5 ] || { echo "ABORT: disk < 5G"; exit 1; }
python3 - "$S/config/openclaw.json" <<'PYP' || { echo "ABORT: config live không ở trạng thái mong đợi (slot/hook LCM)"; exit 1; }
import json,sys
c=json.load(open(sys.argv[1])); e=c['plugins']['entries']['lossless-claw']
assert c['plugins']['slots']['contextEngine']=='lossless-claw' and e['enabled'] and e['hooks']['allowConversationAccess']
PYP
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
read -r OH OEXP < <(oauth_hours || echo "? ?")
echo "OAuth Nemo: còn ${OH}h (hết hạn $OEXP)"
[ "$OH" != "?" ] && [ "$OH" -ge 48 ] || { echo "ABORT: OAuth Nemo < 48h hoặc không đọc được — rollback tar sẽ trả token cũ; chạy sau khi token tự refresh"; exit 1; }
echo "$OEXP" > "$T/oauth-before-cutover"

mkdir -p -m 700 "$B"
printf '%s\n' "$B" > "$T/backup-path"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
snap() { for u in openclaw-gateway-hungreo openclaw-gateway-suckhoe hermes-gateway; do
  echo "$u $(systemctl --user show $u.service -p MainPID --value || true) $(systemctl --user show $u.service -p NRestarts --value || true) $(systemctl --user is-active $u.service || true)"; done; }
snap > "$B/unaffected-before.txt"
docker inspect nemo-sandbox > "$B/container-inspect.json"
cp -p "$S/config/openclaw.json" "$B/openclaw.json.before"
cp -p "$S/nemo.env" "$B/nemo.env.before"

echo "== [1] stop nemo-sandbox + backup → $B"
docker stop -t 60 nemo-sandbox >/dev/null
on_backup_err() { trap - ERR; echo "BACKUP_FAILED — khởi động lại Nemo (LCM 1.1.1)"; docker start nemo-sandbox >/dev/null || true; exit 1; }
trap on_backup_err ERR
tar -C "$S" -cpf "$B/config.tar" config
tar -C "$S" -cpf "$B/workspace.tar" workspace
(cd "$B" && sha256sum config.tar workspace.tar > SHA256SUMS && sha256sum -c --quiet SHA256SUMS)
chmod 600 "$B"/*
echo "NEMO_BACKUP_OK=$B"

on_cutover_err() { trap - ERR; echo "CUTOVER_FAILED — tự rollback về LCM 1.1.1 (backup=$B)"; bash "$T/99_rollback.sh" "$B"; exit 1; }
trap on_cutover_err ERR

oc() {
  docker run --rm --user 1001:1001 --cpus 1 --memory 1300m --memory-swap 1300m \
    --env-file "$S/nemo.env" -e HOME=/sandbox/config -e OPENCLAW_STATE_DIR=/sandbox/config \
    -e OPENCLAW_CONFIG_PATH=/sandbox/config/openclaw.json -e SSL_CERT_FILE="$CA" -e NODE_OPTIONS=--max-old-space-size=640 \
    -v "$CA:$CA:ro" -v "$R:/sandbox/runtime:ro" -v "$S/config:/sandbox/config" \
    -v "$S/workspace:/sandbox/workspace" -v "$S/.npm:/sandbox/.npm" -v "$S/.cache:/sandbox/.cache" \
    "$IMG" node /sandbox/runtime/node_modules/openclaw/openclaw.mjs "$@" < /dev/null
}
wait_lease_stale() {  # chỉ đọc; CLI 10.5 từ chối khi lease gateway-owner < 90s
  python3 - "$1" <<'PY2'
import sqlite3,sys,time
db=sys.argv[1]; deadline=time.time()+400
while True:
    c=sqlite3.connect("file:"+db+"?mode=ro",uri=True)
    r=c.execute("select heartbeat_at from state_leases where scope='gateway-owner' and lease_key='global'").fetchone(); c.close()
    if r is None: print("  lease gateway-owner: không có", flush=True); break
    age=time.time()-r[0]/1000
    if age>=100: print(f"  lease gateway-owner cũ {age:.0f}s → tiếp tục", flush=True); break
    if time.time()>deadline: print(f"  TIMEOUT lease ({age:.0f}s)"); sys.exit(1)
    print(f"  chờ lease cũ đủ 100s (hiện {age:.0f}s)…", flush=True); time.sleep(min(15,100-age+1))
PY2
}
echo "== [2] lossless-claw → 1.2.0 (dry-run rồi thật) + validate"
wait_lease_stale "$S/config/state/openclaw.sqlite"
oc plugins update "$LCM_NEW" --dry-run > "$B/lcm-dryrun.log" 2>&1
grep -q '1.1.1 -> 1.2.0' "$B/lcm-dryrun.log"
oc plugins update "$LCM_NEW" > "$B/lcm-update.log" 2>&1
oc config validate > "$B/config-validate.log" 2>&1
python3 - "$S" "$B" <<'PY'
import pathlib, json, sqlite3, sys
s, b = map(pathlib.Path, sys.argv[1:3])
before = json.loads((b/'openclaw.json.before').read_text()); after = json.loads((s/'config/openclaw.json').read_text())
diff = []
def w(x, y, p):
    if x is None and isinstance(y, dict): x = {}
    if y is None and isinstance(x, dict): y = {}
    if isinstance(x, dict) and isinstance(y, dict):
        for k in set(x) | set(y): w(x.get(k), y.get(k), p + [k])
    elif x != y: diff.append('.'.join(p))
w(before, after, []); bad = [k for k in diff if not any(k == a or k.startswith(a + '.') for a in ('meta', 'wizard'))]
assert not bad, 'update đổi config: ' + ','.join(bad)
assert (s/'nemo.env').read_bytes() == (b/'nemo.env.before').read_bytes(), 'env drift'
assert after['plugins']['slots']['contextEngine'] == 'lossless-claw'
e = after['plugins']['entries']['lossless-claw']; assert e['enabled'] and e['hooks']['allowConversationAccess']
db = sqlite3.connect((s/'config/state/openclaw.sqlite').as_uri()+'?mode=ro', uri=True)
idx = json.loads(db.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()[0])['index']['installRecords']
assert idx['lossless-claw']['version'] == '1.2.0', idx['lossless-claw']
assert idx['codex']['version'] == '2026.10.5', idx['codex']
assert db.execute('pragma quick_check').fetchone()[0] == 'ok'; db.close()
l = sqlite3.connect((s/'config/lcm.db').as_uri()+'?mode=ro', uri=True); assert l.execute('pragma quick_check').fetchone()[0] == 'ok'; l.close()
print('CONFIG_INDEX_SQLITE_GATES_OK lossless-claw=1.2.0')
PY

echo "== [3] start lại nemo-sandbox (cùng container, runtime 10.5)"
docker start nemo-sandbox >/dev/null
ready=0
for i in $(seq 1 90); do
  [ "$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:18796/readyz || true)" = 200 ] && { ready=1; break; }
  [ "$(docker inspect nemo-sandbox --format '{{.State.Running}}' || true)" = true ]
  sleep 2
done
[ "$ready" = 1 ]
[ "$(ver || true)" = 2026.10.5 ]
ST=$(docker inspect nemo-sandbox --format '{{.State.StartedAt}}' || true)
[ "$(docker logs --since "$ST" nemo-sandbox 2>&1 | grep -c 'readSessionTranscriptVisibleMessageDelta is required' || true)" = 0 ]
snap > "$B/unaffected-after.txt"
cmp -s "$B/unaffected-before.txt" "$B/unaffected-after.txt" || { echo "CẢNH BÁO: trạng thái Hungreo/Suckhoe/Hermes đổi:"; diff "$B/unaffected-before.txt" "$B/unaffected-after.txt" || true; }
trap - ERR
chmod 600 "$B"/*
echo "OK 20 — CUTOVER_NEMO_LCM_120_READY backup=$B"
echo "Chờ ~1 phút rồi UAT: nhắn Nemo 1 câu thường + 1 câu hỏi lại chuyện cũ; Claude chạy 30_verify.sh"
echo "Rollback: ssh … 'bash $T/99_rollback.sh $B'"
