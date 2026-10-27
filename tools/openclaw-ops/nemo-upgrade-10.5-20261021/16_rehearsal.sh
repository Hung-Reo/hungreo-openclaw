#!/usr/bin/env bash
# 16 — HƯNG CHẠY (nền: setsid nohup). Rehearsal 10.5 trên BẢN SAO; Nemo live 10.4 TẠM DỪNG ~3–5 phút ở pha boot + lượt model (GO 21/10), trap luôn bật lại.
#   Thứ tự giống 20: codex update → doctor --fix (trên config THẬT của bản sao, env không có token Telegram)
#   → gate schema + 8 khoá config không đổi → RỒI mới cách ly (bỏ channels.telegram, cron OFF, bind loopback)
#   → boot thử gateway (không cổng host, openclaw.json mount :ro, restart=no) → 1 lượt model → dọn.
# ssh … 'bash /home/hung/sandbox-nemo/ops-10.5-20261021/16_rehearsal.sh'            (có 1 lượt model qua route mặc định Muse/OpenRouter)
# ssh … 'bash …/16_rehearsal.sh --no-model'   |   mặc định doctor --fix --non-interactive (GO 21/10); --doctor-safe = doctor --non-interactive
set -Eeuo pipefail
umask 077
S=/home/hung/sandbox-nemo
R=$S/runtime-10.5
T=$S/ops-10.5-20261021
C=$T/rh-config; W=$T/rh-workspace; N=$T/rh-npm; E=$T/rh.env; L=$T/rh-logs
RC=nemo-rh-105
IMG=node:24.21.0-bookworm-slim
CA=/etc/ssl/certs/ca-certificates.crt
MODEL=1; DMODE=fix   # Hưng GO 21/10: Nemo dùng doctor --fix (chế độ safe từ chối migrate session-entry-state)
for a in "$@"; do case "$a" in --no-model) MODEL=0;; --doctor-safe) DMODE=safe;; esac; done
if [ "$DMODE" = fix ]; then DOCTOR_ARGS=(doctor --fix --non-interactive); else DOCTOR_ARGS=(doctor --non-interactive); fi
ram_ok() { [ "$(free -m | awk '/^Mem:/{print $7}')" -ge "$1" ] || { echo "ABORT: RAM available < $1 MiB"; exit 1; }; }
appsrv() { docker exec "$1" sh -c 'grep -l "[a]pp-server" /proc/[0-9]*/cmdline 2>/dev/null | wc -l' 2>/dev/null || echo '?'; }

[ "$(hostname)" = srv1367812 ] || { echo "ABORT: sai host"; exit 1; }
[ "$(jq -r .version "$R/node_modules/openclaw/package.json")" = 2026.10.5 ] || { echo "ABORT: chưa stage 10.5"; exit 1; }
ram_ok 2000
[ "$(docker inspect nemo-sandbox --format '{{range .Mounts}}{{if eq .Destination "/sandbox/runtime"}}{{.Source}}{{end}}{{end}}')" = "$S/runtime-10.4" ] || { echo "ABORT: Nemo live không ở runtime-10.4"; exit 1; }
for p in "$C" "$W" "$N" "$E"; do [ ! -e "$p" ] || { echo "STOP: $p còn sót — báo Claude"; exit 2; }; done
! docker inspect "$RC" >/dev/null 2>&1 || { echo "STOP: container $RC còn sót — báo Claude"; exit 2; }
# OAuth: bản sao mang refresh token của Nemo live; nếu token sắp hết hạn, rehearsal có thể refresh → làm hỏng token live (refresh_token_reused)
docker exec nemo-sandbox node /sandbox/runtime/node_modules/openclaw/dist/entry.js models auth list --json < /dev/null 2>/dev/null | python3 -c '
import json,sys,datetime as dt
s=sys.stdin.read(); d=None
for i,ch in enumerate(s):
    if ch in "[{":
        try: d,_=json.JSONDecoder().raw_decode(s[i:]); break
        except Exception: pass
exps=[]
def walk(o):
    if isinstance(o,dict):
        for k,v in o.items():
            if k.lower() in ("expires","expiresat","expires_at") and isinstance(v,(int,float,str)): exps.append(v)
            else: walk(v)
    elif isinstance(o,list):
        for v in o: walk(v)
walk(d)
now=dt.datetime.now(dt.timezone.utc); ok=[]
for e in exps:
    try:
        t=dt.datetime.fromtimestamp(e/1000 if e>1e11 else e,dt.timezone.utc) if isinstance(e,(int,float)) else dt.datetime.fromisoformat(str(e).replace("Z","+00:00"))
    except Exception: continue
    if t.year>2000: ok.append(t)
if not ok: print("ABORT: không đọc được hạn OAuth của Nemo"); sys.exit(1)
m=min(ok); h=(m-now).total_seconds()/3600
print(f"  OAuth Nemo hết hạn {m:%Y-%m-%d %H:%M}Z (còn {h:.0f}h)")
sys.exit(0 if h>=48 else 1)' || { echo "ABORT: OAuth Nemo còn < 48h hoặc không đọc được — chạy sau khi token tự refresh"; exit 1; }

H0=$(sha256sum "$S/config/openclaw.json" | cut -c1-16)
rm -f "$T/rehearsal-pass"
mkdir -p -m 700 "$L"
NEMO_STOPPED=0
restore_nemo() {  # GO 21/10: Nemo live chỉ dừng trong pha boot + lượt model; luôn bật lại 10.4
  [ "$NEMO_STOPPED" = 1 ] || return 0
  docker start nemo-sandbox >/dev/null 2>&1 || { sleep 5; docker start nemo-sandbox >/dev/null 2>&1; } || echo "  CẢNH BÁO: docker start nemo-sandbox lỗi — Hưng chạy tay: docker start nemo-sandbox"
  local i; for i in $(seq 1 90); do
    [ "$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:18796/readyz || true)" = 200 ] && break; sleep 2; done
  echo "  NEMO_LIVE_RESTARTED readyz=$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:18796/readyz || true) core=$(docker exec nemo-sandbox node -e 'console.log(require("/sandbox/runtime/node_modules/openclaw/package.json").version)' 2>/dev/null || echo '?') (downtime $(( $(date +%s) - NEMO_STOP_TS ))s)"
  NEMO_STOPPED=0
}
cleanup() {
  [ -n "${SAMPLER:-}" ] && kill "$SAMPLER" 2>/dev/null || true
  docker rm -f "$RC" >/dev/null 2>&1 || true
  restore_nemo
  if [ "${KEEP:-0}" = 1 ]; then echo "  GIỮ bản sao để debug: $C $W $N $E (Claude xoá sau)"; rm -f -- "$L"/config.*.json; return 0; fi
  [ -d "$C" ] && rm -rf -- "$C"; [ -d "$W" ] && rm -rf -- "$W"; [ -d "$N" ] && rm -rf -- "$N"; [ -f "$E" ] && rm -f -- "$E"
  rm -f -- "$L"/config.*.json
  true
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

wait_lease_stale() {  # chỉ đọc; chờ lease gateway-owner của bản sao cũ ≥100s
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
oc() {
  docker run --rm --user 1001:1001 --cpus 1 --memory 1100m --memory-swap 1100m \
    --env-file "$E" -e HOME=/sandbox/config -e OPENCLAW_STATE_DIR=/sandbox/config \
    -e OPENCLAW_CONFIG_PATH=/sandbox/config/openclaw.json -e SSL_CERT_FILE="$CA" -e NODE_OPTIONS=--max-old-space-size=640 \
    -v "$CA:$CA:ro" -v "$R:/sandbox/runtime:ro" -v "$C:/sandbox/config" -v "$W:/sandbox/rh-workspace" -v "$N:/sandbox/.npm" \
    "$IMG" node /sandbox/runtime/node_modules/openclaw/openclaw.mjs "$@" < /dev/null
}
step() { local name=$1; shift
  if oc "$@" > "$L/$name.log" 2>&1; then echo "  PASS $name"; else local rc=$?; echo "  rc=$rc $name: $(tail -2 "$L/$name.log" | tr '\n' ' ' | cut -c1-240)"; return $rc; fi; }
dbstat() {  # user_version + quick_check + số dòng mỗi bảng (không nội dung)
  python3 - "$C" "$L/db-$1.json" "$1" <<'PY'
import sqlite3,sys,pathlib,json
c=pathlib.Path(sys.argv[1]); out={}
for rel in ["agents/main/agent/openclaw-agent.sqlite","state/openclaw.sqlite","lcm.db"]:
    d=sqlite3.connect((c/rel).as_uri()+"?mode=ro",uri=True)
    t=[r[0] for r in d.execute("select name from sqlite_master where type='table' and name not like 'sqlite_%' and name not like '%_fts%'")]
    out[rel]={"user_version":d.execute("pragma user_version").fetchone()[0],"quick_check":d.execute("pragma quick_check").fetchone()[0],
              "rows":{x:d.execute(f'select count(*) from "{x}"').fetchone()[0] for x in t}}
    d.close()
json.dump(out,open(sys.argv[2],"w"),indent=1)
for k,v in out.items(): print(f"  [{sys.argv[3]}] {k}: user_version={v['user_version']} quick_check={v['quick_check']} tables={len(v['rows'])}")
PY
}
cfgdiff() {  # $1 trước $2 sau → in khoá đổi; $3=strict thì fail nếu 8 mục cốt lõi đổi
  python3 - "$1" "$2" "${3:-}" <<'PY'
import json,sys
a,b=(json.load(open(f)) for f in sys.argv[1:3]); out=[]
def w(x,y,p):
    if isinstance(x,dict) and isinstance(y,dict):
        for k in set(x)|set(y): w(x.get(k),y.get(k),p+[k])
    elif x!=y: out.append(".".join(p))
w(a,b,[]); ch=sorted(o for o in out if not o.startswith("meta"))
print("  khoá config đổi:", ch or "không")
ALLOW=("wizard.","plugins.entries.openai","plugins.entries.perplexity","skills.entries.summarize")   # Hưng GO 21/10
bad=[k for k in ch if not k.startswith(ALLOW)]
if sys.argv[3]=="strict" and bad: print("  FAIL: doctor đổi config ngoài allowlist:", bad, "→ bước 20 sẽ rollback"); sys.exit(1)
if sys.argv[3]=="strict":
    for k in ("agents","models","auth","channels","gateway"):
        if a.get(k)!=b.get(k): print("  FAIL: mục",k,"đổi"); sys.exit(1)
    print("  allowlist OK; agents/models/auth/channels/gateway giữ nguyên")
PY
}

echo "== [a] bản sao config + workspace (SQLite qua backup API); env bỏ TELEGRAM_BOT_TOKEN"
mkdir -m 700 "$C" "$W" "$N"
{ tar -C "$S/config" --exclude='*.sqlite-wal' --exclude='*.sqlite-shm' --exclude='*.db-wal' --exclude='*.db-shm' \
    --exclude='./agents/main/agent/openclaw-agent.sqlite' --exclude='./state/openclaw.sqlite' --exclude='./lcm.db' -cf - . || [ $? = 1 ]; } | tar -C "$C" -xf -
{ tar -C "$S/workspace" -cf - . || [ $? = 1 ]; } | tar -C "$W" -xf -
python3 - "$S/config" "$C" <<'PY'
import sqlite3,sys,pathlib
src,dst=map(pathlib.Path,sys.argv[1:3])
for rel in ["agents/main/agent/openclaw-agent.sqlite","state/openclaw.sqlite","lcm.db"]:
    a=sqlite3.connect((src/rel).as_uri()+"?mode=ro",uri=True); b=sqlite3.connect(str(dst/rel)); a.backup(b); b.close(); a.close()
print("  copied 3 DB")
PY
grep -v '^TELEGRAM_BOT_TOKEN=' "$S/nemo.env" > "$E"; chmod 600 "$E"
! grep -q '^TELEGRAM_BOT_TOKEN=' "$E" || { echo "ABORT: env rehearsal còn token Telegram"; exit 1; }
wait_lease_stale "$C/state/openclaw.sqlite"

echo "== [b] giống bước 20: codex update → lint → doctor --fix (config chưa cách ly)"
dbstat before
cp -p "$C/openclaw.json" "$L/config.before.json"
step codex-update plugins update "@openclaw/codex@2026.10.5"
step validate-1 config validate
if oc doctor --lint --json > "$L/doctor-lint.json" 2> "$L/doctor-lint.err"; then LINT=0; else LINT=$?; fi
echo "  doctor --lint rc=$LINT"
python3 - "$L/doctor-lint.json" <<'PY'
import json,sys,collections
s=open(sys.argv[1]).read(); d=None
for i,ch in enumerate(s):
    if ch in "[{":
        try: d,_=json.JSONDecoder().raw_decode(s[i:]); break
        except Exception: pass
f=(d.get("findings") if isinstance(d,dict) else d) or []
print("  lint findings:",dict(collections.Counter(x.get("severity","?") for x in f if isinstance(x,dict))))
for x in f:
    if isinstance(x,dict) and x.get("severity") in ("error","warning"): print("   -",x.get("severity"),x.get("id") or x.get("checkId"),str(x.get("message") or x.get("summary"))[:160])
PY
cp -p "$C/openclaw.json" "$L/config.before-doctor.json"
if oc "${DOCTOR_ARGS[@]}" > "$L/doctor-fix.log" 2>&1; then FIX=0; else FIX=$?; fi
echo "  ${DOCTOR_ARGS[*]} rc=$FIX"
{ grep -E "Upgraded agent database|Retired|Updated official plugin|enabled automatically|installed for existing|Disabled |Cleared |Canonicalized|Updated config" "$L/doctor-fix.log" || true; } | sed -E 's/[│├└┌┐┘┤─╮╯╰╭]+//g' | sed 's/^ */   doctor: /' | cut -c1-160; tail -5 "$L/doctor-fix.log" | sed -E 's/sk-or-[^ "]+/<R>/g; s/bot[0-9]+:[A-Za-z0-9_-]+/bot<R>/g' | cut -c1-200
dbstat after
python3 - "$L" <<'PY'
import json,sys,pathlib
L=pathlib.Path(sys.argv[1]); a=json.load(open(L/"db-before.json")); b=json.load(open(L/"db-after.json"))
for k in a:
    ch={t:(a[k]["rows"].get(t),b[k]["rows"].get(t)) for t in set(a[k]["rows"])|set(b[k]["rows"]) if a[k]["rows"].get(t)!=b[k]["rows"].get(t)}
    print(f"  {k}: user_version {a[k]['user_version']}→{b[k]['user_version']}; bảng đổi số dòng: {ch if ch else 'không'}")
ua=b["agents/main/agent/openclaw-agent.sqlite"]["user_version"]
assert ua>=25, f"agent DB user_version={ua} < 25 sau doctor (chế độ này không migrate)"
assert all(v["quick_check"]=="ok" for v in b.values()), "quick_check fail"
print("  MIGRATE_OK agent_db_user_version=",ua)
PY
cfgdiff "$L/config.before-doctor.json" "$C/openclaw.json" strict
cfgdiff "$L/config.before.json" "$C/openclaw.json" > "$L/config-diff-total.txt"; cat "$L/config-diff-total.txt"
step validate-2 config validate

echo "== [c] cách ly bản sao để boot: bỏ Telegram, cron OFF, bind loopback, workspace riêng"
python3 - "$C/openclaw.json" <<'PY'
import json,sys
p=sys.argv[1]; c=json.load(open(p))
c.setdefault("channels",{}).pop("telegram",None)
c.setdefault("cron",{})["enabled"]=False
c.setdefault("gateway",{})["bind"]="loopback"
c.setdefault("agents",{}).setdefault("defaults",{})["workspace"]="/sandbox/rh-workspace"
json.dump(c,open(p,"w"),indent=2)
assert "telegram" not in c["channels"] and c["cron"]["enabled"] is False
print("  isolation OK: channels=",list(c["channels"].keys()))
PY

echo "== [d] boot thử gateway 10.5, giới hạn GIỐNG live 2560m/4608m, --verbose (Nemo live vẫn chạy ở pha này)"
ram_ok 2000
docker run -d --name "$RC" --restart=no --user 1001:1001 --cpus 1 --memory 2560m --memory-swap 4608m \
  --env-file "$E" -e HOME=/sandbox/config -e OPENCLAW_STATE_DIR=/sandbox/config -e OPENCLAW_CONFIG_PATH=/sandbox/config/openclaw.json \
  -e SSL_CERT_FILE="$CA" -v "$CA:$CA:ro" -v "$R:/sandbox/runtime:ro" -v "$C:/sandbox/config" -v "$C/openclaw.json:/sandbox/config/openclaw.json:ro" \
  -v "$W:/sandbox/rh-workspace" -v "$N:/sandbox/.npm" \
  "$IMG" node /sandbox/runtime/node_modules/openclaw/openclaw.mjs gateway run --bind loopback --port 18796 --verbose > /dev/null
ready=0
for i in $(seq 1 90); do
  [ "$(docker inspect "$RC" --format '{{.State.Running}}' 2>/dev/null || true)" = true ] || break
  if docker exec "$RC" node -e 'fetch("http://127.0.0.1:18796/readyz").then(r=>process.exit(r.status===200?0:1)).catch(()=>process.exit(1))' >/dev/null 2>&1; then ready=1; break; fi
  sleep 2
done
RCID=$(docker inspect "$RC" --format '{{.Id}}' 2>/dev/null || true)
CG=/sys/fs/cgroup/system.slice/docker-$RCID.scope
( while docker inspect "$RC" >/dev/null 2>&1; do docker stats --no-stream --format '{{.MemUsage}}' "$RC" 2>/dev/null | cut -d/ -f1; sleep 1; done ) > "$L/mem-samples.txt" 2>/dev/null &
SAMPLER=$!
mempeak() {  # đỉnh RAM/swap của container rehearsal (cgroup v2 nếu đọc được, kèm mẫu docker stats)
  local mp sp oom
  mp=$(cat "$CG/memory.peak" 2>/dev/null || echo ''); sp=$(cat "$CG/memory.swap.peak" 2>/dev/null || echo '')
  oom=$(awk '/^oom_kill /{print $2}' "$CG/memory.events" 2>/dev/null || echo '?')
  echo "  MEM_PEAK cgroup=${mp:+$((mp/1048576))MiB} swap_peak=${sp:+$((sp/1048576))MiB} oom_kill=$oom; docker-stats max=$(python3 -c '
import re,sys
v=[]
for l in open(sys.argv[1]):
    m=re.match(r"\s*([\d.]+)\s*([KMG]i?B)",l)
    if m: v.append(float(m.group(1))*{"KiB":1/1024,"MiB":1,"GiB":1024,"kB":1/1000,"MB":1,"GB":1000}.get(m.group(2),1))
print(f"{max(v):.0f}MiB" if v else "?")' "$L/mem-samples.txt" 2>/dev/null || echo '?')"
}
docker logs "$RC" 2>&1 | sed -E 's/sk-or-[^ "]+/<R>/g; s/bot[0-9]+:[A-Za-z0-9_-]+/bot<R>/g' > "$L/rh-gateway.log" || true
if [ "$ready" != 1 ]; then
  echo "  BOOT_FAIL: $(docker inspect "$RC" --format 'status={{.State.Status}} exit={{.State.ExitCode}}' 2>/dev/null || true)"
  { grep -iE 'error|schema|doctor|refus' "$L/rh-gateway.log" || true; } | tail -6 | cut -c1-240
  { grep -iE 'error|fail|refus|reason|cannot|denied|EACCES|ENOENT' "$L/rh-gateway.log" || true; } | grep -v 'startup phase' | tail -10 | cut -c1-260
  mempeak; KEEP=1; echo "REHEARSAL_FAILED — gửi output cho Claude"; exit 1
fi
BOOT_TS=$(date +%s)
echo "  BOOT_OK readyz=200 sau ~$((i*2))s; $(grep -E 'http server listening' "$L/rh-gateway.log" | tail -1 | grep -oE '\([0-9]+ plugins' || true)"
echo "  dòng log telegram start/poll: $(grep -ciE 'telegram.*(start|connect|poll)' "$L/rh-gateway.log" || true) (kỳ vọng 0)"
docker stats --no-stream --format '  mem={{.MemUsage}} pids={{.PIDs}}' "$RC"

turn() {  # $1=tên $2=marker $3..=tham số thêm (vd --model …)
  local name=$1 mark=$2 ok=0 n; shift 2
  for n in $(seq 1 12); do   # agent còn "startup inspection" sau readyz (integrity gate do lease doctor để lại) → thử lại mỗi 15s, tối đa 3 phút
    if docker exec "$RC" node /sandbox/runtime/node_modules/openclaw/openclaw.mjs agent --session-key "agent:main:rh-105-$name" \
        --message "Kiểm thử nâng cấp, không dùng công cụ, không gửi ra ngoài. Trả lời đúng một từ: $mark" --timeout 150 --json "$@" \
        > "$L/rh-turn-$name.json" 2> "$L/rh-turn-$name.err" < /dev/null; then ok=1; break; fi
    grep -q 'has not completed startup inspection' "$L/rh-turn-$name.json" "$L/rh-turn-$name.err" 2>/dev/null || break
    echo "  agent chưa xong startup inspection ($(( $(date +%s) - BOOT_TS ))s sau readyz) — thử lại sau 15s" ; sleep 15
  done
  [ "$name" = default ] && echo "  AGENT_READY_AFTER_READYZ ~$(( $(date +%s) - BOOT_TS ))s"
  if [ "$ok" = 1 ]; then
    python3 - "$L/rh-turn-$name.json" "$mark" "$name" <<'PY' || { echo "  TURN_NO_MARKER $name"; exit 1; }
import json,sys
s=open(sys.argv[1]).read(); mark,name=sys.argv[2:4]; d=None
for i,ch in enumerate(s):
    if ch=="{":
        try: d,_=json.JSONDecoder().raw_decode(s[i:]); break
        except Exception: pass
d=d or {}
texts=[x.get("text","") for x in d.get("result",{}).get("payloads",[]) if isinstance(x,dict)]
seen={}
def walk(o):
    if isinstance(o,dict):
        for k,v in o.items():
            if k in ("provider","model","modelId","runtime","agentRuntime","fallbackUsed","attempts") and not isinstance(v,(dict,list)): seen.setdefault(k,v)
            walk(v)
    elif isinstance(o,list):
        for v in o: walk(v)
walk(d.get("result",{}))
assert d.get("status")=="ok" and any(mark in t for t in texts), f"reply không có {mark}"
print(f"  TURN_OK {name} (reply có {mark}) route={seen}")
PY
  else echo "  TURN_FAIL $name: $(tail -2 "$L/rh-turn-$name.err" | sed -E 's/sk-or-[^ "]+/<R>/g' | tr '\n' ' ' | cut -c1-240) | container: $(docker inspect "$RC" --format 'running={{.State.Running}} oom={{.State.OOMKilled}} exit={{.State.ExitCode}}' 2>/dev/null || echo 'đã chết')"; mempeak; docker logs --tail 30 "$RC" 2>&1 | sed -E 's/sk-or-[^ "]+/<R>/g' > "$L/rh-gateway-tail.log" || true; exit 1; fi
}
if [ "$MODEL" = 1 ]; then
  echo "== [e] tạm dừng Nemo live (GO 21/10) rồi chạy lượt model thật (session riêng, không gửi ra ngoài)"
  [ "$(docker inspect nemo-sandbox --format '{{range .Mounts}}{{if eq .Destination "/sandbox/runtime"}}{{.Source}}{{end}}{{end}}')" = "$S/runtime-10.4" ] || { echo "ABORT: Nemo live không ở 10.4"; exit 1; }
  NEMO_STOP_TS=$(date +%s); NEMO_STOPPED=1
  docker stop -t 60 nemo-sandbox >/dev/null
  echo "  Nemo live đã dừng $(date +%T); RAM available $(free -m | awk '/^Mem:/{print $7}') MiB"
  ram_ok 2600
  turn default RH105_OK
  turn sol RH105_SOL_OK --model openai/gpt-6.1-sol
  python3 - "$C/lcm.db" <<'PY'
import sqlite3,sys
d=sqlite3.connect("file:"+sys.argv[1]+"?mode=ro",uri=True)
print("  lcm sau lượt: msgs=",d.execute("select count(*) from messages").fetchone()[0],"quick_check=",d.execute("pragma quick_check").fetchone()[0])
PY
fi
echo "  codex app-server trong rehearsal: $(appsrv "$RC")"
mempeak
docker stop -t 30 "$RC" >/dev/null || docker rm -f "$RC" >/dev/null || true
kill "$SAMPLER" 2>/dev/null || true; SAMPLER=
restore_nemo
[ "$(sha256sum "$S/config/openclaw.json" | cut -c1-16)" = "$H0" ] || { echo "FAIL: openclaw.json LIVE bị đổi?!"; exit 1; }
[ "$(docker inspect nemo-sandbox --format '{{.State.Running}}')" = true ] || { echo "FAIL: Nemo live không chạy?!"; exit 1; }
[ "$(docker exec nemo-sandbox node -e 'console.log(require("/sandbox/runtime/node_modules/openclaw/package.json").version)')" = 2026.10.4 ] || { echo "FAIL: Nemo live không về 10.4?!"; exit 1; }
echo "$(date +%s) $H0 $DMODE" > "$T/rehearsal-pass"
echo "OK 16 — REHEARSAL_PASS (log giữ ở $L, đã xoá bản sao/config đầy đủ/container rehearsal)"
