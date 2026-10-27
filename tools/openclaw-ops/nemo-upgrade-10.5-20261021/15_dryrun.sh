#!/usr/bin/env bash
# 15 — HƯNG CHẠY sau 10. Dry-run các lệnh ghi của cutover trên BẢN SAO config (Nemo live vẫn chạy, không bị đụng).
# ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash /home/hung/sandbox-nemo/ops-10.5-20261021/15_dryrun.sh'
set -Eeuo pipefail
S=/home/hung/sandbox-nemo
R=$S/runtime-10.5
T=$S/ops-10.5-20261021
C=$T/dry-config          # bản sao config, xoá ở cuối
IMG=node:24.21.0-bookworm-slim
CA=/etc/ssl/certs/ca-certificates.crt
[ "$(hostname)" = srv1367812 ] || { echo "ABORT: sai host"; exit 1; }
[ "$(jq -r .version "$R/node_modules/openclaw/package.json")" = 2026.10.5 ] || { echo "ABORT: chưa stage 10.5 (chạy 10 trước)"; exit 1; }
[ "$(free -m | awk '/^Mem:/{print $7}')" -ge 1800 ] || { echo "ABORT: RAM available < 1500 MiB"; exit 1; }
H0=$(sha256sum "$S/config/openclaw.json" | cut -c1-16)
rm -f "$T/dryrun-pass"
[ ! -e "$C" ] || { echo "STOP: $C còn sót từ lần trước — báo Claude"; exit 2; }
N=$T/dry-npm             # npm cache riêng, không dùng chung .npm của Nemo live
cleanup() { [ -d "$C" ] && rm -rf -- "$C"; [ -d "$N" ] && rm -rf -- "$N"; true; }
trap cleanup EXIT

echo "== copy config (bỏ -wal/-shm; SQLite sao bằng backup API cho nhất quán)"
mkdir -m 700 "$C" "$N"
# 3 DB chính không chép bằng tar (đang được ghi) mà tạo mới bằng backup API bên dưới; tar exit 1 = "file changed" chấp nhận được
{ tar -C "$S/config" --exclude='*.sqlite-wal' --exclude='*.sqlite-shm' --exclude='*.db-wal' --exclude='*.db-shm' \
    --exclude='./agents/main/agent/openclaw-agent.sqlite' --exclude='./state/openclaw.sqlite' --exclude='./lcm.db' -cf - . || [ $? = 1 ]; } | tar -C "$C" -xf -
python3 - "$S/config" "$C" <<'PY'
import sqlite3,sys,pathlib
src,dst=map(pathlib.Path,sys.argv[1:3])
for rel in ["agents/main/agent/openclaw-agent.sqlite","state/openclaw.sqlite","lcm.db"]:
    a=sqlite3.connect((src/rel).as_uri()+"?mode=ro",uri=True); b=sqlite3.connect(str(dst/rel)); a.backup(b); b.close(); a.close()
    print("  copied",rel)
PY

oc() {
  docker run --rm --user 1001:1001 --cpus 1 --memory 1100m --memory-swap 1100m --network bridge \
    --env-file "$S/nemo.env" -e HOME=/sandbox/config -e OPENCLAW_STATE_DIR=/sandbox/config \
    -e OPENCLAW_CONFIG_PATH=/sandbox/config/openclaw.json -e SSL_CERT_FILE="$CA" -e NODE_OPTIONS=--max-old-space-size=640 \
    -v "$CA:$CA:ro" -v "$R:/sandbox/runtime:ro" -v "$C:/sandbox/config" -v "$N:/sandbox/.npm" \
    "$IMG" node /sandbox/runtime/node_modules/openclaw/openclaw.mjs "$@" < /dev/null
}
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
echo "== chờ lease gateway-owner trong bản sao cũ ≥100s (giống bước 20 sau khi stop)"
wait_lease_stale "$C/state/openclaw.sqlite"
fail=0
run() { local name=$1; shift
  if oc "$@" > "$T/dry-$name.log" 2>&1; then echo "  PASS $name: $(tail -1 "$T/dry-$name.log" | cut -c1-160)"
  else echo "  FAIL $name rc=$?: $(tail -3 "$T/dry-$name.log" | tr '\n' ' ' | cut -c1-300)"; fail=1; fi; }
echo "== dry-run trên bản sao, bằng runtime 10.5"
run codex-update   plugins update "@openclaw/codex@2026.10.5" --dry-run
run lcm-inspect    plugins inspect lossless-claw
run codex-inspect  plugins inspect codex
run config-validate config validate
python3 - "$C" <<'PY'
import json,sys,pathlib
c=json.loads((pathlib.Path(sys.argv[1])/"openclaw.json").read_text())
print("  codex.sessionCatalog trong config:", c.get("plugins",{}).get("entries",{}).get("codex",{}).get("config",{}).get("sessionCatalog","<không đặt → mặc định của 10.5>"))
PY
[ "$(sha256sum "$S/config/openclaw.json" | cut -c1-16)" = "$H0" ] || { echo "FAIL: openclaw.json LIVE bị đổi?!"; fail=1; }
if [ $fail = 0 ]; then date +%s > "$T/dryrun-pass"; echo "OK 15 — DRYRUN_PASS (bản sao đã xoá)"; else echo "DRYRUN_FAILED — không cutover, gửi output cho Claude"; exit 1; fi
