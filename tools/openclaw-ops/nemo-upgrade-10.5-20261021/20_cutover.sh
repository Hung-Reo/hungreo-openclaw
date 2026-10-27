#!/usr/bin/env bash
# 20 — HƯNG CHẠY sau 10 + 15 PASS. Nemo 2026.10.4 → 2026.10.5, codex plugin 10.4 → 10.5, GIỮ LCM 1.1.1.
# ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash /home/hung/sandbox-nemo/ops-10.5-20261021/20_cutover.sh'
# Không đụng Hungreo/Suckhoe/Hermes (script kiểm PID/NRestarts trước–sau). Downtime Nemo ~2–5 phút.
set -Eeuo pipefail
umask 077
S=/home/hung/sandbox-nemo
R=$S/runtime-10.5
T=$S/ops-10.5-20261021
IMG=node:24.21.0-bookworm-slim
CA=/etc/ssl/certs/ca-certificates.crt
TS=$(TZ=Asia/Ho_Chi_Minh date +%Y%m%d-%H%M%S)
B=/home/hung/backups/nemo-10.5-$TS
CMD_EXPECT='["node","/sandbox/runtime/node_modules/openclaw/openclaw.mjs","gateway","run","--bind","lan","--port","18796"]'

ver() { docker exec nemo-sandbox node -e 'console.log(require("/sandbox/runtime/node_modules/openclaw/package.json").version)'; }
[ "$(hostname)" = srv1367812 ] || { echo "ABORT: sai host"; exit 1; }
[ "$(jq -r .version "$R/node_modules/openclaw/package.json")" = 2026.10.5 ] || { echo "ABORT: chưa stage 10.5"; exit 1; }
[ -f "$T/rehearsal-pass" ] || { echo "ABORT: chưa có 16_rehearsal.sh PASS"; exit 1; }
read -r RTS RH0 RMODE < "$T/rehearsal-pass" || true
[ "${RMODE:-}" = fix ] || { echo "ABORT: rehearsal PASS không phải chế độ fix (doctor --fix --non-interactive)"; exit 1; }
[ -n "${RTS:-}" ] && [ $(( $(date +%s) - RTS )) -lt 86400 ] || { echo "ABORT: rehearsal PASS đã quá 24h — chạy lại 16"; exit 1; }
[ "${RH0:-}" = "$(sha256sum "$S/config/openclaw.json" | cut -c1-16)" ] || { echo "ABORT: openclaw.json đổi từ lúc rehearsal — chạy lại 16"; exit 1; }
[ -f "$T/99_rollback.sh" ] || { echo "ABORT: thiếu $T/99_rollback.sh"; exit 1; }
CUR=$(ver || true); [ "$CUR" = 2026.10.4 ] || { echo "ABORT: Nemo đang chạy $CUR, không phải 10.4"; exit 1; }
[ "$(docker inspect nemo-sandbox --format '{{json .Config.Cmd}}')" = "$CMD_EXPECT" ] || { echo "ABORT: Cmd container khác dự kiến"; exit 1; }
[ "$(docker inspect nemo-sandbox --format '{{range .Mounts}}{{if eq .Destination "/sandbox/runtime"}}{{.Source}}{{end}}{{end}}')" = "$S/runtime-10.4" ] || { echo "ABORT: mount runtime hiện tại không phải runtime-10.4"; exit 1; }
! docker inspect nemo-sandbox-10.4 >/dev/null 2>&1 || { echo "ABORT: đã có container tên nemo-sandbox-10.4 — báo Claude"; exit 1; }
[ "$(free -m | awk '/^Mem:/{print $7}')" -ge 1200 ] || { echo "ABORT: RAM available < 1200 MiB"; exit 1; }

mkdir -p -m 700 "$B"
printf '%s\n' "$B" > "$T/backup-path"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
snap() { for u in openclaw-gateway-hungreo openclaw-gateway-suckhoe hermes-gateway; do
  echo "$u $(systemctl --user show $u.service -p MainPID --value || true) $(systemctl --user show $u.service -p NRestarts --value || true) $(systemctl --user is-active $u.service || true)"; done; }
snap > "$B/unaffected-before.txt"
docker inspect nemo-sandbox > "$B/container-inspect.json"
cp -p "$S/config/openclaw.json" "$B/openclaw.json.before"
cp -p "$S/nemo.env" "$B/nemo.env.before"
echo "codex_app_server_before=$(docker exec nemo-sandbox sh -c 'grep -l "[a]pp-server" /proc/[0-9]*/cmdline 2>/dev/null | wc -l' || echo '?')" | tee "$B/codex-before.txt"

echo "== [1] stop nemo-sandbox + backup → $B"
docker stop -t 60 nemo-sandbox >/dev/null
on_backup_err() { trap - ERR; echo "BACKUP_FAILED — khởi động lại 10.4"; docker start nemo-sandbox >/dev/null || true; exit 1; }
trap on_backup_err ERR
tar -C "$S" -cpf "$B/config.tar" config
tar -C "$S" -cpf "$B/workspace.tar" workspace
(cd "$B" && sha256sum config.tar workspace.tar > SHA256SUMS && sha256sum -c --quiet SHA256SUMS)
chmod 600 "$B"/*
echo "NEMO_BACKUP_OK=$B"

# 10.5 từ chối CLI ở container khác khi lease 'gateway-owner' còn heartbeat < 90s → chờ lease cũ ≥ 100s (chỉ đọc, không sửa DB)
wait_lease_stale() {  # $1 = đường dẫn state/openclaw.sqlite
  python3 - "$1" <<'PY2'
import sqlite3,sys,time
db=sys.argv[1]; deadline=time.time()+400
while True:
    c=sqlite3.connect("file:"+db+"?mode=ro",uri=True)
    r=c.execute("select heartbeat_at from state_leases where scope='gateway-owner' and lease_key='global'").fetchone(); c.close()
    if r is None: print("  lease gateway-owner: không có", flush=True); break
    age=time.time()-r[0]/1000
    if age>=100: print(f"  lease gateway-owner cũ {age:.0f}s → tiếp tục", flush=True); break
    if time.time()>deadline: print(f"  TIMEOUT: lease vẫn mới ({age:.0f}s) — gateway khác còn chạy?"); sys.exit(1)
    print(f"  chờ lease cũ đủ 100s (hiện {age:.0f}s)…", flush=True)
    time.sleep(min(15,100-age+1))
PY2
}
on_cutover_err() { trap - ERR; echo "CUTOVER_FAILED — tự rollback về 10.4 (backup=$B)"; bash "$T/99_rollback.sh" "$B"; exit 1; }
trap on_cutover_err ERR

oc() {
  docker run --rm --user 1001:1001 --cpus 1 --memory 1300m --memory-swap 1300m \
    --env-file "$S/nemo.env" -e HOME=/sandbox/config -e OPENCLAW_STATE_DIR=/sandbox/config \
    -e OPENCLAW_CONFIG_PATH=/sandbox/config/openclaw.json -e SSL_CERT_FILE="$CA" -e NODE_OPTIONS=--max-old-space-size=640 \
    -v "$CA:$CA:ro" -v "$R:/sandbox/runtime:ro" -v "$S/config:/sandbox/config" \
    -v "$S/workspace:/sandbox/workspace" -v "$S/.npm:/sandbox/.npm" -v "$S/.cache:/sandbox/.cache" \
    "$IMG" node /sandbox/runtime/node_modules/openclaw/openclaw.mjs "$@" < /dev/null
}
echo "== [2] codex plugin → 2026.10.5 + validate"
wait_lease_stale "$S/config/state/openclaw.sqlite"
oc plugins update "@openclaw/codex@2026.10.5" --dry-run > "$B/codex-dryrun.log" 2>&1
oc plugins update "@openclaw/codex@2026.10.5" > "$B/codex-update.log" 2>&1
echo "== [2b] migrate schema DB: doctor --fix --non-interactive (GO 21/10; gateway đang dừng; đã thử y hệt ở 16)"
cp -p "$S/config/openclaw.json" "$B/openclaw.json.before-doctor"
touch "$B/.t0-doctor"
oc doctor --fix --non-interactive > "$B/doctor.log" 2>&1   # rehearsal 16: rc=0 cả 3 lần → rc≠0 ở đây = bất thường → ERR → rollback
find "$S/workspace" -newer "$B/.t0-doctor" -type f > "$B/ws-touched-by-doctor.txt" 2>/dev/null || true
echo "  doctor xong; file workspace bị đổi: $(wc -l < "$B/ws-touched-by-doctor.txt")"
oc config validate > "$B/config-validate.log" 2>&1
python3 - "$S" "$B" <<'PY'
import pathlib, json, sqlite3, sys
s, b = map(pathlib.Path, sys.argv[1:3])
before = json.loads((b/'openclaw.json.before').read_text()); after = json.loads((s/'config/openclaw.json').read_text())
for k in ['agents','channels','models','gateway','tools','memory','auth']:   # skills: chỉ cho phép summarize (kiểm dưới)
    assert before.get(k) == after.get(k), 'config drift ngoài dự kiến: ' + k
bd = json.loads((b/'openclaw.json.before-doctor').read_text()); diff = []
def w(x, y, p):
    if x is None and isinstance(y, dict): x = {}
    if y is None and isinstance(x, dict): y = {}
    if isinstance(x, dict) and isinstance(y, dict):
        for k in set(x) | set(y): w(x.get(k), y.get(k), p + [k])
    elif x != y: diff.append('.'.join(p))
ALLOW = ('meta', 'wizard', 'plugins.entries.openai', 'plugins.entries.perplexity', 'skills.entries.summarize')   # Hưng GO 21/10
w(bd, after, []); bad = [k for k in diff if not any(k == a or k.startswith(a + '.') for a in ALLOW)]
assert not bad, 'doctor đổi config ngoài allowlist: ' + ','.join(bad)
def strip_sum(x):
    x = json.loads(json.dumps(x or {})); (x.get('entries') or {}).pop('summarize', None)
    if x.get('entries') == {}: x.pop('entries')
    return x
assert strip_sum(after.get('skills')) == strip_sum(before.get('skills')), 'skills đổi ngoài summarize'
assert (s/'nemo.env').read_bytes() == (b/'nemo.env.before').read_bytes(), 'env drift'
assert after['plugins']['slots']['contextEngine'] == 'lossless-claw'
e = after['plugins']['entries']['lossless-claw']; assert e['enabled'] and e['hooks']['allowConversationAccess']
db = sqlite3.connect((s/'config/state/openclaw.sqlite').as_uri()+'?mode=ro', uri=True)
idx = json.loads(db.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()[0])['index']['installRecords']
assert idx['lossless-claw']['version'] == '1.1.1', idx['lossless-claw']
assert idx['codex']['version'] == '2026.10.5', idx['codex']
assert db.execute('pragma quick_check').fetchone()[0] == 'ok'; db.close()
l = sqlite3.connect((s/'config/lcm.db').as_uri()+'?mode=ro', uri=True); assert l.execute('pragma quick_check').fetchone()[0] == 'ok'; l.close()
a = sqlite3.connect((s/'config/agents/main/agent/openclaw-agent.sqlite').as_uri()+'?mode=ro', uri=True)
uv = a.execute('pragma user_version').fetchone()[0]; assert uv >= 25, f'agent DB user_version={uv} < 25 sau doctor --fix'
assert a.execute('pragma quick_check').fetchone()[0] == 'ok'; a.close()
print('AGENT_DB_SCHEMA_OK user_version=', uv)
print('CONFIG_AND_SQLITE_GATES_OK')
PY

echo "== [3] container mới trên runtime-10.5 (giữ nemo-sandbox-10.4 để rollback)"
docker rename nemo-sandbox nemo-sandbox-10.4
docker update --restart=no nemo-sandbox-10.4 >/dev/null
docker run -d --name nemo-sandbox --restart=unless-stopped --user 1001:1001 --cpus 1 \
  --memory 2560m --memory-swap 4608m --log-opt max-size=10m --log-opt max-file=3 \
  -p 127.0.0.1:18796:18796 -p 127.0.0.1:8789:8789 --env-file "$S/nemo.env" -e SSL_CERT_FILE="$CA" \
  -v "$CA:$CA:ro" -v "$S/.npm:/sandbox/.npm" -v "$R:/sandbox/runtime:ro" -v "$S/config:/sandbox/config" \
  -v "$S/config/openclaw.json:/sandbox/config/openclaw.json:ro" -v "$S/workspace:/sandbox/workspace" -v "$S/.cache:/sandbox/.cache" \
  "$IMG" node /sandbox/runtime/node_modules/openclaw/openclaw.mjs gateway run --bind lan --port 18796 > "$B/candidate-container-id"
ready=0
for i in $(seq 1 90); do
  [ "$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:18796/readyz || true)" = 200 ] && { ready=1; break; }
  [ "$(docker inspect nemo-sandbox --format '{{.State.Running}}' || true)" = true ]
  sleep 2
done
[ "$ready" = 1 ]
[ "$(ver || true)" = 2026.10.5 ]
snap > "$B/unaffected-after.txt"
cmp -s "$B/unaffected-before.txt" "$B/unaffected-after.txt" || { echo "CẢNH BÁO: trạng thái Hungreo/Suckhoe/Hermes đổi:"; diff "$B/unaffected-before.txt" "$B/unaffected-after.txt" || true; }
trap - ERR
chmod 600 "$B"/*
echo "OK 20 — CUTOVER_NEMO_10_5_READY backup=$B"
echo "UAT: nhắn Nemo 1 câu thường + 1 câu hỏi lại chuyện cũ; Claude chạy 30_verify.sh"
echo "Rollback: ssh … 'bash $T/99_rollback.sh $B'"
