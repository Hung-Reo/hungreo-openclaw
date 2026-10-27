#!/usr/bin/env bash
# 30 — Soak READ-ONLY sau LCM 1.2.0 cho Suckhoe + Hungreo (Claude Code soạn 25/10 16:15). CLAUDE CHẠY:
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 30_soak.sh
# Mốc: sau lượt agent đầu tiên của Suckhoe (= lần migrate cursor đầu + lần dùng model đầu → OAuth hạn 17:26 25/10 mới refresh), +24h, +48h.
# Lưu ý (VERIFIED 25/10 20:30): cron 19:30 Suckhoe gửi thẳng qua message.action, KHÔNG qua agent → không bao giờ vào LCM (cả 1.1.1);
# chỉ dùng để biết job còn chạy. Gate LCM tính theo inbound (lượt agent), không theo outbound.
# Chỉ đếm/hạn/kích thước; không in nội dung tin, không in secret. Không ghi file nào (sqlite mode=ro, không mở backup có -wal).
set -u
export TZ=Asia/Ho_Chi_Minh XDG_RUNTIME_DIR="/run/user/$(id -u)"
NOW=$(date '+%F %T'); NOWS=$(date +%s)
ok()   { echo "  PASS  $*"; }
warn() { echo "  WARN  $*"; }
fail() { echo "  FAIL  $*"; }
info() { echo "  INFO  $*"; }
R='s/[0-9]{8,}/<R>/g; s/(ey[A-Za-z0-9_-]{10,}|sk-[A-Za-z0-9_-]+|bot[0-9]+:[A-Za-z0-9_-]+)/<R>/g'

main() {
echo "== soak LCM 1.2.0 H/S — $NOW"
for p in suckhoe hungreo; do
  case $p in
    suckhoe) PORT=18795; UP="2026-10-25 14:24:40" ;;
    hungreo) PORT=18789; UP="2026-10-25 14:28:36" ;;
  esac
  U=openclaw-gateway-$p.service; D=$HOME/.openclaw-$p
  echo; echo "### $p (nâng lúc $UP)"
  ACT=$(systemctl --user is-active $U); PID=$(systemctl --user show $U -p MainPID --value)
  SINCE=$(date -d "$(systemctl --user show $U -p ActiveEnterTimestamp --value)" '+%F %T' 2>/dev/null)
  NR=$(systemctl --user show $U -p NRestarts --value); RZ=$(curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/readyz)
  [ "$ACT" = active ] && [ "$RZ" = 200 ] && ok "active readyz=200 pid=$PID NRestarts=$NR" || fail "active=$ACT readyz=$RZ NRestarts=$NR"
  [ "$SINCE" = "$UP" ] && ok "chưa restart từ lúc nâng" || warn "đã start lại lúc $SINCE (khác mốc nâng $UP) — tra journal"
  if [ -r /proc/$PID/status ]; then
    RSS=$(( $(awk '/VmRSS/{print $2}' /proc/$PID/status)/1024 )); HWM=$(( $(awk '/VmHWM/{print $2}' /proc/$PID/status)/1024 )); SW=$(( $(awk '/VmSwap/{print $2}' /proc/$PID/status)/1024 ))
    info "RSS=${RSS}MiB HWM=${HWM}MiB swap=${SW}MiB"
  fi

  J=$(journalctl --user -u $U --since "$UP" --no-pager -o short-iso 2>/dev/null)
  IN=$(grep -c 'Inbound message' <<<"$J"); OUT=$(grep -c 'outbound send ok' <<<"$J")
  CAP=$(grep -c 'readSessionTranscriptVisibleMessageDelta is required\|readSessionTranscriptRawDelta is required' <<<"$J")
  LERR=$(grep -E '\[lcm\]|lossless' <<<"$J" | grep -ciE 'error|fail')
  REB=$(grep -c 'session-rebound' <<<"$J")
  info "từ lúc nâng: inbound=$IN outbound_ok=$OUT"
  [ "$CAP" = 0 ] && ok "capability_error=0" || fail "capability_error=$CAP (1.2.0 KHÔNG ingest được — cân nhắc 99_rollback soft)"
  [ "$LERR" = 0 ] && ok "lỗi lcm/lossless=0" || { warn "lỗi lcm/lossless=$LERR:"; grep -E '\[lcm\]|lossless' <<<"$J" | grep -iE 'error|fail' | sed -E "$R" | cut -c1-200 | tail -4; }
  [ "$REB" = 0 ] && ok "session-rebound=0" || warn "session-rebound=$REB (#178608)"
  echo -n "  INFO  rss_threshold/ngày từ lúc nâng:"; grep rss_threshold <<<"$J" | cut -c1-10 | sort | uniq -c | awk '{printf " %s=%s",substr($2,6),$1}'; echo
  [ $p = hungreo ] && info "baseline Rùa trên 1.1.1 (19→24/10): 167 · 261 · 238 · 209 · 206 · 96 /ngày"
  # LCM ghi info vào /tmp/openclaw/lossless-claw-<ngày>.log (chung uid cho cả 2 bot) → lọc theo sessionKey prefix không được vì đã ẩn;
  # đếm theo conversation id có cursor của bot này (id 2 bot có thể trùng nhau → số này là xấp xỉ). 25/10: Rùa reset generation_mismatch 3/3 lượt (resync toàn bộ ~11k entry/lượt).
  CIDS=$(python3 -c "import sqlite3,sys;l=sqlite3.connect('file:$D/lcm.db?mode=ro',uri=True);print('|'.join(str(r[0]) for r in l.execute('select conversation_id from conversation_transcript_cursors')))" 2>/dev/null)
  if [ -n "$CIDS" ]; then
    LL=$(cat /tmp/openclaw/lossless-claw-$(date -d "$UP" +%F).log /tmp/openclaw/lossless-claw-$(date +%F).log 2>/dev/null | sort -u | grep -E "conversation=($CIDS) " | awk -v t="$(date -u -d "@$(date -d "$UP" +%s)" +%FT%T)" -F'"time":"' '{split($2,a,"\"");if(a[1]>=t)print}')
    RS=$(grep -c 'transcript cursor reset' <<<"$LL"); RSY=$(grep -c 'transcript resync' <<<"$LL"); HG=$(grep -c 'history gaps recorded' <<<"$LL")
    info "LCM log từ lúc nâng (conv có cursor): cursor_reset=$RS [$(grep -o 'reason=[a-z_]*; resyncing' <<<"$LL" | sort | uniq -c | awk '{printf "%s×%s ",$2,$1}')] resync=$RSY gaps_recorded_warn=$HG — reset/lượt ≈ $RS/$IN (mong đợi ≪1; 25/10 Rùa = 3/4)"
  fi

  UPUTC=$(date -u -d "@$(date -d "$UP" +%s)" '+%F %T')   # lcm.db lưu created_at theo UTC
  python3 - "$D" "$UPUTC" "$IN" <<'PY'
import sqlite3,json,sys,pathlib
c=pathlib.Path(sys.argv[1]); up=sys.argv[2]; turns=int(sys.argv[3])
def say(lv,m): print(f"  {lv:<5} {m}")
st=sqlite3.connect((c/'state/openclaw.sqlite').as_uri()+'?mode=ro',uri=True)
idx=json.loads(st.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()[0])['index']['installRecords']
v=idx.get('lossless-claw',{}).get('version')
say("PASS" if v=="1.2.0" else "FAIL", f"installedIndex lossless-claw={v}")
cfg=json.loads((c/'openclaw.json').read_text())
dbp=cfg.get('plugins',{}).get('entries',{}).get('lossless-claw',{}).get('config',{}).get('dbPath') or str(c/'lcm.db')
m=cfg['agents']['defaults']['model']; say("INFO", f"model={m.get('primary')} fb={m.get('fallbacks')}")
l=sqlite3.connect(pathlib.Path(dbp).as_uri()+'?mode=ro',uri=True); q=lambda s,*a:l.execute(s,a).fetchone()[0]
qc=q('pragma quick_check'); say("PASS" if qc=="ok" else "FAIL", f"quick_check={qc}")
dup=q("select count(*) from (select conversation_id,transcript_entry_id from messages where transcript_entry_id is not null group by 1,2 having count(*)>1)")
say("PASS" if dup==0 else "FAIL", f"dup_entry_id={dup}")
dupi=q("select count(*) from (select conversation_id,identity_hash from messages where identity_hash is not null group by 1,2 having count(*)>1)")
new=q("select count(*) from messages where created_at>=?",up)
say("INFO", f"msgs={q('select count(*) from messages')} (+{new} từ lúc nâng) summaries={q('select count(*) from summaries')} dup_identity={dupi} (16:00 25/10: Rùa 4219 · Suckhoe 1408) last_msg_utc={q('select max(created_at) from messages')}")
if turns>0 and new==0: say("WARN",f"có {turns} inbound sau nâng nhưng LCM 0 tin mới — ingest có thể dừng")
elif new>0: say("PASS","LCM ingest tin mới sau nâng")
else: say("INFO","chưa có lượt agent nào sau nâng → chưa kiểm được ingest")
cur=l.execute("select origin,mode,count(*) from conversation_transcript_cursors group by 1,2").fetchall()
nc=sum(r[2] for r in cur)
if nc>0: say("PASS", f"cursors={nc} {cur}")
elif turns==0: say("INFO","cursors=0 — chưa có lượt agent nào sau nâng, migrate live chưa chạy (chờ)")
else: say("WARN", f"cursors=0 dù đã có {turns} inbound — conversation chưa vào cursor mode")
g=l.execute("select count(*),coalesce(sum(entry_count),0),count(distinct conversation_id) from conversation_transcript_gaps").fetchone()
gs=l.execute("select source,count(*),sum(entry_count) from conversation_transcript_gaps group by 1").fetchall()
gn=q("select count(*) from conversation_transcript_gaps where detected_at>=?",up)
say("INFO", f"gaps={g[0]} (entries={g[1]}, conv={g[2]}) theo source={gs} | phát hiện từ lúc nâng={gn}  (16:05: Rùa 8 · Suckhoe 0; gaps = lịch sử cũ không nhập lại, không phải mất tin mới)")
PY

  echo "  -- OAuth (chỉ hạn)"
  ( set -a; . $D/gateway.systemd.env; set +a; OPENCLAW_STATE_DIR=$D OPENCLAW_CONFIG_PATH=$D/openclaw.json timeout 90 /home/hung/bin/openclaw --profile $p models auth list --json </dev/null 2>/dev/null ) | python3 -c '
import json,sys,datetime as dt
s=sys.stdin.read(); d=None
for i,ch in enumerate(s):
    if ch in "[{":
        try: d,_=json.JSONDecoder().raw_decode(s[i:]); break
        except Exception: pass
now=dt.datetime.now(dt.timezone.utc); seen=0
P=(d or {}).get("profiles") or {} if isinstance(d,dict) else (d or [])
items=P.items() if isinstance(P,dict) else [(str(x.get("id") or x.get("profileId") or "?"),x) for x in P if isinstance(x,dict)]
def fe(o):  # tìm trường hạn ở mọi tầng của 1 profile
    if isinstance(o,dict):
        for k,v in o.items():
            if k.lower() in ("expires","expiresat","expires_at") and not isinstance(v,(dict,list)): return v
            r=fe(v)
            if r is not None: return r
    elif isinstance(o,list):
        for v in o:
            r=fe(v)
            if r is not None: return r
for pid,pr in items:
    e=fe(pr)
    if e is None: continue
    try: t=dt.datetime.fromisoformat(str(e).replace("Z","+00:00")) if isinstance(e,str) else dt.datetime.fromtimestamp(float(e)/(1000 if float(e)>1e11 else 1),dt.timezone.utc)
    except Exception: print("  INFO  ",pid[:12]+"…","expires=",str(e)[:25]); continue
    if t.year<2000: continue
    seen+=1; loc=t.astimezone(dt.timezone(dt.timedelta(hours=7))).strftime("%F %H:%M")
    lv="PASS" if t>now else "WARN"
    print(f"  {lv:<5} OAuth {pid.split(chr(58))[0]}:<R> hạn {loc}" + ("" if t>now else " — ĐÃ QUÁ HẠN, chưa refresh (runtime chỉ refresh khi có lượt dùng model)"))
if not seen: print("  WARN  không đọc được hạn OAuth")
'
  OP='refresh_token|oauth.*(fail|error|expired|invalid)|token refresh.*(fail|error)|\b401\b|unauthorized'
  OE=$(grep -iE "$OP" <<<"$J" | grep -viE 'rss_threshold' | wc -l)
  [ "$OE" = 0 ] && ok "log lỗi OAuth/401 từ lúc nâng=0" || { warn "log lỗi OAuth/401=$OE:"; grep -iE "$OP" <<<"$J" | sed -E "$R" | cut -c1-200 | tail -3; }

  if [ $p = suckhoe ]; then
    T=$(date +%F)
    if [ "$NOWS" -ge "$(date -d "$T 19:45" +%s)" ]; then
      C=$(journalctl --user -u $U --since "$T 19:25" --until "$T 19:45" --no-pager 2>/dev/null | grep -c 'outbound send ok')
      [ "$C" -ge 1 ] && ok "cron 19:30 hôm nay chạy: outbound_ok=$C (gửi thẳng, không qua LCM)" || warn "cron 19:30 hôm nay: 0 outbound trong 19:25–19:45 (22→25/10 đều có 1)"
    else info "chưa tới 19:45 — mốc cron 19:30 chưa kiểm"; fi
  fi
done

echo; echo "### VPS + bot khác"
free -m | awk 'NR==2{printf "  INFO  RAM avail=%sMiB/%sMiB\n",$7,$2} NR==3{printf "  INFO  swap used=%sMiB/%sMiB\n",$3,$2}'
df -h / | awk 'NR==2{print "  INFO  disk free="$4" ("$5" used)"}'
for u in hermes-gateway openclaw-healthcheck.timer; do s=$u; [[ $u == *.timer ]] || s=$u.service; echo "  INFO  $s $(systemctl --user is-active $s) NRestarts=$(systemctl --user show $s -p NRestarts --value 2>/dev/null)"; done
docker inspect nemo-sandbox --format '  INFO  nemo running={{.State.Running}} restarts={{.RestartCount}} oom={{.State.OOMKilled}}' 2>/dev/null
}

OUTP=$(main 2>&1); echo "$OUTP"
NFAIL=$(grep -c '^  FAIL' <<<"$OUTP"); NWARN=$(grep -c '^  WARN' <<<"$OUTP"); NERR=$(grep -c '^Traceback' <<<"$OUTP")
echo; echo "== KẾT: FAIL=$NFAIL WARN=$NWARN script_error=$NERR"
[ "$NERR" = 0 ] || echo "   script_error → lỗi của script, không phải của bot; báo Claude sửa."
[ "$NFAIL" = 0 ] || echo "   FAIL → xem 99_rollback.sh <bot> soft (giữ lcm.db) trước khi cân nhắc hard; báo Hưng trước khi chạy."
