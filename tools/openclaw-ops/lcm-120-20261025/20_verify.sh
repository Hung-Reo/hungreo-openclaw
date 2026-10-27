#!/usr/bin/env bash
# 20 — READ-ONLY Verify sau khi nâng lossless-claw 1.1.1 → 1.2.0 cho suckhoe hoặc hungreo.
set -u
export TZ=Asia/Ho_Chi_Minh

P=${1:?bot (suckhoe|hungreo)}
D="$HOME/.openclaw-$P"
U="openclaw-gateway-$P.service"
case "$P" in
  suckhoe) PORT=18795 ;;
  hungreo) PORT=18789 ;;
  *) echo "ABORT: bot = suckhoe|hungreo"; exit 1 ;;
esac

redact_stream() {
  sed -E 's/sessionKey=[^ ]+/sessionKey=<R>/g; s/chatId=[0-9-]+/chatId=<R>/g; s/telegram:(direct:|group:)?[0-9-]+/telegram:<R>/g; s/bot[0-9]+:[A-Za-z0-9_-]+/bot<R>/g; s/sk-[^ "]+/<R>/g; s/eyJ[^ "]+/<R>/g'
}

oc_profile() {
  (
    for v in $(compgen -v OPENCLAW_ 2>/dev/null || true); do unset "$v"; done
    unset TELEGRAM_BOT_TOKEN
    set -a
    [ -f "$D/gateway.systemd.env" ] && . "$D/gateway.systemd.env"
    set +a
    OPENCLAW_PROFILE="$P" \
    OPENCLAW_STATE_DIR="$D" \
    OPENCLAW_CONFIG_PATH="$D/openclaw.json" \
    OPENCLAW_GATEWAY_PORT="$PORT" \
    OPENCLAW_SYSTEMD_UNIT="$U" \
      timeout 120 /home/hung/bin/openclaw --profile "$P" "$@" < /dev/null
  )
}

SINCE=$(systemctl --user show "$U" -p ActiveEnterTimestamp --value | awk '{print $2" "$3}')
PID=$(systemctl --user show "$U" -p MainPID --value)
echo "== $P $(systemctl --user is-active "$U") pid=$PID since=$SINCE NRestarts=$(systemctl --user show "$U" -p NRestarts --value) readyz=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/readyz") =="
echo "core=$(strings "/proc/$PID/environ" | grep ^OPENCLAW_SERVICE_VERSION= | cut -d= -f2) rss_MiB=$(( $(awk '/VmRSS/{print $2}' "/proc/$PID/status")/1024 )) swap_MiB=$(( $(awk '/VmSwap/{print $2}' "/proc/$PID/status")/1024 ))"
jq -c '{primary:.agents.defaults.model.primary,fb:.agents.defaults.model.fallbacks,slot:.plugins.slots.contextEngine,stream:.channels.telegram.streaming.mode}' "$D/openclaw.json"

miss=$(for v in $(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$D/gateway.systemd.env" | cut -d= -f1); do strings "/proc/$PID/environ" | grep -q "^$v=" || echo -n "$v "; done)
deg=$(journalctl --user -u "$U" --since "$SINCE" --no-pager | grep -cE 'SECRETS_(DEGRADED|OWNER_UNAVAILABLE)' || true)
echo "env_missing=[${miss}] secrets_degraded=${deg}"

DB=$(jq -r '.plugins.entries["lossless-claw"].config.dbPath // empty' "$D/openclaw.json"); DB=${DB/#\~/$HOME}; DB=${DB:-$D/lcm.db}
python3 - "$D/state/openclaw.sqlite" "$DB" <<'PY'
import sqlite3,sys,json,os
c=sqlite3.connect("file:"+sys.argv[1]+"?mode=ro",uri=True)
row=c.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()
idx=json.loads(row[0])["index"]["installRecords"] if row else {}
lcm=idx.get("lossless-claw",{})
pkg_ver=json.load(open(lcm["installPath"]+"/package.json"))["version"] if lcm.get("installPath") and os.path.exists(lcm["installPath"]+"/package.json") else "missing"
print(f"index: spec={lcm.get('spec')} version={lcm.get('version')} package.json={pkg_ver}")
c.close()

d=sqlite3.connect("file:"+sys.argv[2]+"?mode=ro",uri=True)
q=lambda s:d.execute(s).fetchone()[0]
tabs={r[0] for r in d.execute("select name from sqlite_master where type='table'")}
print("lcm quick_check:",q("pragma quick_check"))
print(f"  convs={q('select count(*) from conversations')} msgs={q('select count(*) from messages')} summaries={q('select count(*) from summaries')} pending={q('select count(*) from pending_summary_nodes')}")
print("  dup_entry_id:",q("select count(*) from (select conversation_id,transcript_entry_id from messages where transcript_entry_id is not null group by 1,2 having count(*)>1)"))
if "conversation_transcript_cursors" in tabs:
    print(f"  1.2.0 tables: cursors={q('select count(*) from conversation_transcript_cursors')} gaps={q('select count(*) from conversation_transcript_gaps')} gap_entries={q('select coalesce(sum(entry_count),0) from conversation_transcript_gaps')}")
else:
    print("  1.2.0 tables: (chưa tạo — sẽ tạo khi mở DB ở lượt đầu)")
print("  last message created_at:",q("select max(created_at) from messages"))
d.close()
PY

J=$(journalctl --user -u "$U" --since "$SINCE" --no-pager)
echo "-- log từ lúc start: dòng lỗi/cảnh báo (bỏ rss_threshold)"
grep -iE 'error|fail|warn|unhandled' <<<"$J" | grep -v rss_threshold | redact_stream | cut -c1-220 | tail -10 || true
echo "-- LCM 1.2.0 log counters:"
echo "  cursor_mode_entered=$(grep -c 'transcript cursor mode entered' <<<"$J" || true) resync=$(grep -c '\[lcm\] transcript resync' <<<"$J" || true) capability_error=$(grep -c 'readSessionTranscriptVisibleMessageDelta is required' <<<"$J" || true) lcm_error=$(grep -iE 'lossless|\[lcm\]' <<<"$J" | grep -ciE 'error|fail' || true)"
echo "-- rss_threshold warnings từ lúc start: $(grep -c rss_threshold <<<"$J" || true)"
echo "-- lượt Telegram từ lúc start: inbound=$(grep -c 'Inbound message' <<<"$J" || true) outbound_ok=$(grep -c 'outbound send ok' <<<"$J" || true)"

echo "-- CLI probe (oc_profile $P channels status --probe):"
oc_profile channels status --probe 2>&1 | redact_stream | tail -12 || true
free -m | sed -n 2,3p
