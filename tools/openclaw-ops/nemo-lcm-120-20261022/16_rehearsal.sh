#!/usr/bin/env bash
# 16 — HƯNG CHẠY (nền: setsid nohup, CHỈ 1 LẦN). Rehearsal LCM 1.1.1 → 1.2.0 cho Nemo (core 10.5) trên BẢN SAO config/workspace.
#   [b] plugins update lossless-claw@1.2.0 (dry-run rồi thật) trên bản sao → gate config/index → [c] cách ly → [d] boot thử (Nemo live vẫn chạy)
#   → [e] TẠM DỪNG Nemo live, 2 lượt model (thường + recall qua lcm_grep), đo migrate cursor/gaps/duplicate/RAM
#   → [f] thử rollback mềm về 1.1.1 trên DB đã migrate (boot + 1 lượt) → bật lại Nemo live (trap luôn bật lại). Downtime Nemo ~4–6 phút.
# ssh … 'setsid nohup bash /home/hung/sandbox-nemo/ops-lcm120-20261022/16_rehearsal.sh > /home/hung/sandbox-nemo/ops-lcm120-20261022/rehearsal.log 2>&1 < /dev/null &'
set -Eeuo pipefail
umask 077
S=/home/hung/sandbox-nemo
R=$S/runtime-10.5
T=$S/ops-lcm120-20261022
C=$T/rh-config; W=$T/rh-workspace; N=$T/rh-npm; E=$T/rh.env; L=$T/rh-logs
RC=nemo-rh-lcm120
IMG=node:24.21.0-bookworm-slim
CA=/etc/ssl/certs/ca-certificates.crt
MODEL=1; for a in "$@"; do case "$a" in --no-model) MODEL=0;; esac; done
LCM_NEW="@martian-engineering/lossless-claw@1.2.0"; LCM_OLD="@martian-engineering/lossless-claw@1.1.1"
DMKEY=agent:main:main   # DM của Nemo (dmScope main) — conversation cũ, có sẵn trước 1.2.0
lcmidx() {  # $1 = thư mục config → in version lossless-claw + codex từ installedIndex
  python3 - "$1" <<'PYI'
import sqlite3,json,sys,pathlib
db=sqlite3.connect((pathlib.Path(sys.argv[1])/"state/openclaw.sqlite").as_uri()+"?mode=ro",uri=True)
idx=json.loads(db.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()[0])["index"]["installRecords"]
print(idx.get("lossless-claw",{}).get("version"), idx.get("codex",{}).get("version"))
PYI
}
ram_ok() { [ "$(free -m | awk '/^Mem:/{print $7}')" -ge "$1" ] || { echo "ABORT: RAM available < $1 MiB"; exit 1; }; }
appsrv() { docker exec "$1" sh -c 'grep -l "[a]pp-server" /proc/[0-9]*/cmdline 2>/dev/null | wc -l' 2>/dev/null || echo '?'; }

[ "$(hostname)" = srv1367812 ] || { echo "ABORT: sai host"; exit 1; }
[ "$(jq -r .version "$R/node_modules/openclaw/package.json")" = 2026.10.5 ] || { echo "ABORT: chưa stage 10.5"; exit 1; }
ram_ok 2000
[ "$(df --output=avail -BG / | tail -1 | tr -dc 0-9)" -ge 5 ] || { echo "ABORT: disk < 5G"; exit 1; }
[ "$(docker inspect nemo-sandbox --format '{{range .Mounts}}{{if eq .Destination "/sandbox/runtime"}}{{.Source}}{{end}}{{end}}')" = "$S/runtime-10.5" ] || { echo "ABORT: Nemo live không ở runtime-10.5"; exit 1; }
[ "$(lcmidx "$S/config")" = "1.1.1 2026.10.5" ] || { echo "ABORT: Nemo live không ở LCM 1.1.1 + codex 10.5 ($(lcmidx "$S/config"))"; exit 1; }
mkdir -p -m 700 "$T"
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
restore_nemo() {  # Nemo live chỉ dừng trong pha lượt model + thử rollback; luôn bật lại
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
ALLOW=("wizard",)   # nâng plugin không được đổi config (LCM 1.1.0→1.1.1 trên H/S: 0 khoá đổi)
bad=[k for k in ch if not any(k==a or k.startswith(a+".") for a in ALLOW)]
if sys.argv[3]=="strict" and bad: print("  FAIL: update đổi config ngoài allowlist:", bad, "→ bước 20 sẽ rollback"); sys.exit(1)
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

echo "== [b] giống bước 20: plugins update lossless-claw 1.2.0 trên bản sao (dry-run rồi thật)"
dbstat before
cp -p "$C/openclaw.json" "$L/config.before.json"
lcmstat() {  # $1 nhãn → số liệu LCM của bản sao (không nội dung)
  python3 - "$C/lcm.db" "$L/lcm-$1.json" "$1" <<'PYL'
import sqlite3,sys,json
d=sqlite3.connect("file:"+sys.argv[1]+"?mode=ro",uri=True); q=lambda s:d.execute(s).fetchone()[0]
t={r[0] for r in d.execute("select name from sqlite_master where type='table'")}
o={"msgs":q("select count(*) from messages"),"summaries":q("select count(*) from summaries"),
   "dup_entry_id":q("select count(*) from (select conversation_id,transcript_entry_id from messages where transcript_entry_id is not null group by 1,2 having count(*)>1)"),
   "cursors":q("select count(*) from conversation_transcript_cursors") if "conversation_transcript_cursors" in t else None,
   "gaps":q("select count(*) from conversation_transcript_gaps") if "conversation_transcript_gaps" in t else None,
   "gap_entries":q("select coalesce(sum(entry_count),0) from conversation_transcript_gaps") if "conversation_transcript_gaps" in t else None,
   "quick_check":q("pragma quick_check")}
cid=d.execute("select conversation_id from conversations where session_key='agent:main:main' order by updated_at desc limit 1").fetchone()
o["dm_conv"]=cid[0] if cid else None
o["dm_msgs"]=q(f"select count(*) from messages where conversation_id={cid[0]}") if cid else None
o["dm_cursor"]=(q(f"select count(*) from conversation_transcript_cursors where conversation_id={cid[0]}") if "conversation_transcript_cursors" in t and cid else None)
o["dm_gaps"]=(q(f"select coalesce(sum(entry_count),0) from conversation_transcript_gaps where conversation_id={cid[0]}") if "conversation_transcript_gaps" in t and cid else None)
json.dump(o,open(sys.argv[2],"w")); print(f"  [lcm {sys.argv[3]}]",o)
PYL
}
lcmstat before
step lcm-dryrun plugins update "$LCM_NEW" --dry-run
grep -q '1.1.1 -> 1.2.0' "$L/lcm-dryrun.log" || { echo "  FAIL: dry-run không báo '1.1.1 -> 1.2.0': $(tail -2 "$L/lcm-dryrun.log" | tr '\n' ' ' | cut -c1-200)"; exit 1; }
step lcm-update plugins update "$LCM_NEW"
step validate-1 config validate
[ "$(lcmidx "$C")" = "1.2.0 2026.10.5" ] || { echo "  FAIL: index bản sao sau update = $(lcmidx "$C")"; exit 1; }
echo "  index bản sao: lossless-claw 1.2.0, codex 2026.10.5"
cfgdiff "$L/config.before.json" "$C/openclaw.json" strict
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

echo "== [d] boot thử gateway 10.5 + LCM 1.2.0, giới hạn GIỐNG live 2560m/4608m, --verbose (Nemo live vẫn chạy ở pha này)"
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

turn() {  # $1=tên $2=marker $3=câu hỏi (rỗng = câu mặc định) $4..=tham số thêm
  local name=$1 mark=$2 msg=$3 ok=0 n; shift 3
  [ -n "$msg" ] || msg="Kiểm thử nâng cấp, không dùng công cụ, không gửi ra ngoài. Trả lời đúng một từ: $mark"
  for n in $(seq 1 12); do   # agent còn "startup inspection" sau readyz (integrity gate do lease doctor để lại) → thử lại mỗi 15s, tối đa 3 phút
    if docker exec "$RC" node /sandbox/runtime/node_modules/openclaw/openclaw.mjs agent --session-key "${TURN_KEY:-agent:main:rh-lcm120-$name}" \
        --message "$msg" --timeout 180 --json "$@" \
        > "$L/rh-turn-$name.json" 2> "$L/rh-turn-$name.err" < /dev/null; then ok=1; break; fi
    grep -q 'has not completed startup inspection' "$L/rh-turn-$name.json" "$L/rh-turn-$name.err" 2>/dev/null || break
    echo "  agent chưa xong startup inspection ($(( $(date +%s) - BOOT_TS ))s sau readyz) — thử lại sau 15s" ; sleep 15
  done
  [ "$name" = default ] && echo "  AGENT_READY_AFTER_READYZ ~$(( $(date +%s) - BOOT_TS ))s" || true
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
assert d.get("status")=="ok", "status != ok"
if mark=="-":
    print(f"  TURN_OK {name} route={seen} | reply: {(' '.join(texts))[:200]!r}")
else:
    assert any(mark in t for t in texts), f"reply không có {mark}"
    print(f"  TURN_OK {name} (reply có {mark}) route={seen}")
PY
  else echo "  TURN_FAIL $name: $(tail -2 "$L/rh-turn-$name.err" | sed -E 's/sk-or-[^ "]+/<R>/g' | tr '\n' ' ' | cut -c1-240) | container: $(docker inspect "$RC" --format 'running={{.State.Running}} oom={{.State.OOMKilled}} exit={{.State.ExitCode}}' 2>/dev/null || echo 'đã chết')"; mempeak; docker logs --tail 30 "$RC" 2>&1 | sed -E 's/sk-or-[^ "]+/<R>/g' > "$L/rh-gateway-tail.log" || true; exit 1; fi
}
lcmlog() {  # đếm dòng log LCM 1.2.0 trong container rehearsal
  local G; G=$(docker logs "$RC" 2>&1 || true)
  echo "  log LCM: cursor_mode_entered=$(grep -c 'transcript cursor mode entered' <<<"$G" || true) resync=$(grep -c '\[lcm\] transcript resync' <<<"$G" || true) capability_error=$(grep -c 'readSessionTranscriptVisibleMessageDelta is required' <<<"$G" || true) lcm_error=$(grep -iE '\[lcm\]' <<<"$G" | grep -ciE 'error|fail' || true)"
  grep -E '\[lcm\] transcript (cursor mode entered|resync)' <<<"$G" | sed -E 's/conversation=[0-9]+/conversation=#/' | cut -c1-220 | tail -3 || true
  [ "$(grep -c 'readSessionTranscriptVisibleMessageDelta is required' <<<"$G" || true)" = 0 ] || { echo "  FAIL: LCM báo thiếu visible-delta reader"; exit 1; }
}
if [ "$MODEL" = 1 ]; then
  echo "== [e] tạm dừng Nemo live rồi chạy lượt model thật (session riêng, không gửi ra ngoài)"
  [ "$(docker inspect nemo-sandbox --format '{{range .Mounts}}{{if eq .Destination "/sandbox/runtime"}}{{.Source}}{{end}}{{end}}')" = "$S/runtime-10.5" ] || { echo "ABORT: Nemo live không ở 10.5"; exit 1; }
  NEMO_STOP_TS=$(date +%s); NEMO_STOPPED=1
  docker stop -t 60 nemo-sandbox >/dev/null
  echo "  Nemo live đã dừng $(date +%T); RAM available $(free -m | awk '/^Mem:/{print $7}') MiB"
  ram_ok 2600
  turn default RH120_OK ""
  # lượt trên conversation DM CŨ → buộc LCM 1.2.0 resync/migrate conversation đã có từ 1.1.1 (đường Prod sẽ đi ở tin đầu tiên)
  TURN_KEY=$DMKEY turn dm - "Dùng công cụ lcm_grep (tìm qua tool_search nếu cần) để tìm 'security audit' trong lịch sử hội thoại, rồi trả lời ngắn: audit đó có bao nhiêu critical. Không gửi ra ngoài."
  lcmlog
  lcmstat after
  python3 - "$L" <<'PYC'
import json,sys,pathlib
L=pathlib.Path(sys.argv[1]); a=json.load(open(L/"lcm-before.json")); b=json.load(open(L/"lcm-after.json"))
grow=b["msgs"]-a["msgs"]
print(f"  LCM: msgs {a['msgs']}→{b['msgs']} (+{grow}), dup_entry_id {a['dup_entry_id']}→{b['dup_entry_id']}, cursors {a['cursors']}→{b['cursors']}, gaps {b['gaps']} ({b['gap_entries']} entry), quick_check {b['quick_check']}")
assert b["quick_check"]=="ok", "lcm quick_check fail"
assert b["dup_entry_id"]<=a["dup_entry_id"], "duplicate entry id tăng"
assert 0 < grow <= 25, f"msgs tăng bất thường (+{grow}) — có thể nhập lại lịch sử"
assert (b["cursors"] or 0) >= 1, "không có conversation nào vào cursor mode"
dg=(b["dm_msgs"] or 0)-(a["dm_msgs"] or 0)
print(f"  DM cũ (conv {b['dm_conv']}): msgs {a['dm_msgs']}→{b['dm_msgs']} (+{dg}), cursor={b['dm_cursor']}, gap_entries={b['dm_gaps']}")
assert b["dm_conv"] is not None and b["dm_conv"]==a["dm_conv"], "conversation DM đổi/mất"
assert 0 < dg <= 8, f"DM cũ tăng +{dg} msgs (kỳ vọng 2–8) — nghi nhập lại lịch sử"
assert (b["dm_cursor"] or 0) >= 1, "conversation DM cũ chưa vào cursor mode"
print("  LCM_120_INGEST_OK")
PYC
  echo "  codex app-server trong rehearsal: $(appsrv "$RC")"
  mempeak
  echo "== [f] thử rollback mềm về LCM 1.1.1 trên DB đã migrate (Nemo live vẫn dừng) — CHỈ để biết 1.1.1 còn đọc được DB mới; Prod rollback = 99 (tar), KHÔNG dùng rollback mềm rồi lên lại 1.2.0"
  docker stop -t 30 "$RC" >/dev/null || docker rm -f "$RC" >/dev/null || true
  kill "$SAMPLER" 2>/dev/null || true; SAMPLER=
  docker rm -f "$RC" >/dev/null 2>&1 || true
  wait_lease_stale "$C/state/openclaw.sqlite"
  # cách ly đang ghi trong openclaw.json bản sao; plugins update không đụng channels/cron
  step lcm-rollback plugins update "$LCM_OLD"
  [ "$(lcmidx "$C")" = "1.1.1 2026.10.5" ] || { echo "  FAIL: rollback index = $(lcmidx "$C")"; exit 1; }
  docker run -d --name "$RC" --restart=no --user 1001:1001 --cpus 1 --memory 2560m --memory-swap 4608m \
    --env-file "$E" -e HOME=/sandbox/config -e OPENCLAW_STATE_DIR=/sandbox/config -e OPENCLAW_CONFIG_PATH=/sandbox/config/openclaw.json \
    -e SSL_CERT_FILE="$CA" -v "$CA:$CA:ro" -v "$R:/sandbox/runtime:ro" -v "$C:/sandbox/config" -v "$C/openclaw.json:/sandbox/config/openclaw.json:ro" \
    -v "$W:/sandbox/rh-workspace" -v "$N:/sandbox/.npm" \
    "$IMG" node /sandbox/runtime/node_modules/openclaw/openclaw.mjs gateway run --bind loopback --port 18796 > /dev/null
  ready=0
  for i in $(seq 1 90); do
    [ "$(docker inspect "$RC" --format '{{.State.Running}}' 2>/dev/null || true)" = true ] || break
    if docker exec "$RC" node -e 'fetch("http://127.0.0.1:18796/readyz").then(r=>process.exit(r.status===200?0:1)).catch(()=>process.exit(1))' >/dev/null 2>&1; then ready=1; break; fi
    sleep 2
  done
  [ "$ready" = 1 ] || { echo "  ROLLBACK_BOOT_FAIL"; docker logs --tail 20 "$RC" 2>&1 | sed -E 's/sk-or-[^ "]+/<R>/g' | cut -c1-200; KEEP=1; exit 1; }
  BOOT_TS=$(date +%s)
  turn rb RH111_OK ""
  python3 - "$C/lcm.db" <<'PYR'
import sqlite3,sys
d=sqlite3.connect("file:"+sys.argv[1]+"?mode=ro",uri=True)
print("  sau rollback 1.1.1: msgs=",d.execute("select count(*) from messages").fetchone()[0],"quick_check=",d.execute("pragma quick_check").fetchone()[0])
assert d.execute("pragma quick_check").fetchone()[0]=="ok"
PYR
  echo "  ROLLBACK_SOFT_111_OK (1.1.1 boot + trả lời trên DB đã migrate)"
fi
docker stop -t 30 "$RC" >/dev/null || docker rm -f "$RC" >/dev/null || true
kill "$SAMPLER" 2>/dev/null || true; SAMPLER=
restore_nemo
[ "$(sha256sum "$S/config/openclaw.json" | cut -c1-16)" = "$H0" ] || { echo "FAIL: openclaw.json LIVE bị đổi?!"; exit 1; }
[ "$(docker inspect nemo-sandbox --format '{{.State.Running}}')" = true ] || { echo "FAIL: Nemo live không chạy?!"; exit 1; }
[ "$(docker exec nemo-sandbox node -e 'console.log(require("/sandbox/runtime/node_modules/openclaw/package.json").version)')" = 2026.10.5 ] || { echo "FAIL: Nemo live không ở 10.5?!"; exit 1; }
[ "$(lcmidx "$S/config")" = "1.1.1 2026.10.5" ] || { echo "FAIL: Nemo live LCM đổi?!"; exit 1; }
[ "$MODEL" = 1 ] || { echo "KHÔNG ghi marker: chạy --no-model chưa đủ để mở khoá bước 20"; exit 0; }
echo "$(date +%s) $H0 lcm120" > "$T/rehearsal-pass"
echo "OK 16 — REHEARSAL_PASS (log giữ ở $L, đã xoá bản sao/config đầy đủ/container rehearsal)"
