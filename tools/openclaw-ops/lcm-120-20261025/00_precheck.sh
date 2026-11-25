#!/usr/bin/env bash
# 00 — READ-ONLY Precheck trước khi chạy Pha 2 (Rehearsal) & Pha 3/4 (Nâng lossless-claw 1.1.1 → 1.2.0 trên core 2026.9.33).
# Không stop/restart, không sửa config/state. Không in secret/chatId/nội dung tin nhắn.
set -u
export TZ=Asia/Ho_Chi_Minh

SPEC="@martian-engineering/lossless-claw@1.2.0"
RUNTIME_933="/home/hung/openclaw-upgrade-20261018-933/runtime/node_modules/openclaw"

oc_profile() {
  local P="$1"; shift
  local D="$HOME/.openclaw-$P"
  local PORT=$([ "$P" = suckhoe ] && echo 18795 || echo 18789)
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
    OPENCLAW_SYSTEMD_UNIT="openclaw-gateway-$P.service" \
      timeout 300 /home/hung/bin/openclaw --profile "$P" "$@" < /dev/null
  )
}

echo "== [0] Thời gian & Tài nguyên VPS ($(date '+%F %T %Z')) =="
free -m
df -Th / /tmp /home/hung

echo ""
echo "== [1] Kiểm runtime 2026.9.33 có đủ hàm delta transcript cho LCM 1.2.0 =="
/home/hung/openclaw-upgrade-20261003/node/bin/node - "$RUNTIME_933" <<'PY' || { echo "ABORT: runtime 2026.9.33 thiếu hàm delta transcript"; exit 1; }
const path = require("path");
const rt = process.argv[2];
const pkg = require(path.join(rt, "package.json"));
const sdk = require(path.join(rt, "dist/plugin-sdk/session-transcript-runtime.js"));
console.log("runtime_version:", pkg.version);
console.log("has_readSessionTranscriptVisibleMessageDelta:", typeof sdk.readSessionTranscriptVisibleMessageDelta === "function");
console.log("has_readSessionTranscriptRawDelta:", typeof sdk.readSessionTranscriptRawDelta === "function");
if (pkg.version !== "2026.9.33" || typeof sdk.readSessionTranscriptVisibleMessageDelta !== "function" || typeof sdk.readSessionTranscriptRawDelta !== "function") {
  process.exit(1);
}
PY

for p in suckhoe hungreo; do
  D="$HOME/.openclaw-$p"
  U="openclaw-gateway-$p.service"
  PORT=$([ "$p" = suckhoe ] && echo 18795 || echo 18789)
  echo ""
  echo "################ $p (:$PORT) ################"
  echo "gateway=$(systemctl --user is-active "$U") pid=$(systemctl --user show "$U" -p MainPID --value) since=$(systemctl --user show "$U" -p ActiveEnterTimestamp --value) NRestarts=$(systemctl --user show "$U" -p NRestarts --value) readyz=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/readyz")"
  echo "-- config LCM & load:"
  jq -c '{slot:.plugins.slots.contextEngine, lcm:.plugins.entries["lossless-claw"], load:.plugins.load, allow:(.plugins.allow // null)}' "$D/openclaw.json"
  echo "-- DB files & sizes:"
  DB=$(jq -r '.plugins.entries["lossless-claw"].config.dbPath // empty' "$D/openclaw.json"); DB=${DB/#\~/$HOME}; [ -z "$DB" ] && DB="$D/lcm.db"
  ls -lh "$DB"* "$D/state/openclaw.sqlite"* "$D/agents/main/agent/openclaw-agent.sqlite"* 2>/dev/null || true
  python3 - "$D/state/openclaw.sqlite" "$DB" <<'PY' || { echo "ABORT: kiểm SQLite $p lỗi"; exit 1; }
import sqlite3,sys,json
s_db, l_db = sys.argv[1:3]
c = sqlite3.connect("file:"+s_db+"?mode=ro", uri=True)
row = c.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()
idx = json.loads(row[0])["index"]["installRecords"] if row else {}
lcm_rec = idx.get("lossless-claw", {})
print(f"  installedIndex: spec={lcm_rec.get('spec')} version={lcm_rec.get('version')} path={lcm_rec.get('installPath')}")
c.close()

l = sqlite3.connect("file:"+l_db+"?mode=ro", uri=True)
q = lambda sql: l.execute(sql).fetchone()[0]
tabs = {r[0] for r in l.execute("select name from sqlite_master where type='table'")}
print(f"  lcm quick_check={q('pragma quick_check')} convs={q('select count(*) from conversations')} msgs={q('select count(*) from messages')} summaries={q('select count(*) from summaries')} pending={q('select count(*) from pending_summary_nodes')}")
print(f"  dup_entry_id={q('select count(*) from (select conversation_id,transcript_entry_id from messages where transcript_entry_id is not null group by 1,2 having count(*)>1)')} has_120_cursors={'conversation_transcript_cursors' in tabs}")
convs = l.execute("select conversation_id, (select count(*) from messages m where m.conversation_id=conversations.conversation_id) as mc, case when session_key='agent:main:main' then 'agent:main:main' else '<redacted-session>' end as sk from conversations order by updated_at desc limit 5").fetchall()
print("  recent 5 convs (id, msgs, key_type):", convs)
l.close()
PY
  echo "-- DRY-RUN plugins update $SPEC:"
  H0=$(sha256sum "$D/openclaw.json" | cut -c1-12)
  DRY=$(oc_profile "$p" plugins update "$SPEC" --dry-run 2>&1 | sed -E 's/sessionKey=[^ ]+/sessionKey=<R>/g; s/chatId=[0-9-]+/chatId=<R>/g; s/telegram:(direct:|group:)?[0-9-]+/telegram:<R>/g; s/bot[0-9]+:[A-Za-z0-9_-]+/bot<R>/g; s/sk-[^ "]+/<R>/g; s/eyJ[^ "]+/<R>/g' || true)
  echo "$DRY" | tail -5
  H1=$(sha256sum "$D/openclaw.json" | cut -c1-12)
  echo "  config_hash: $H0 -> $H1"
  grep -q "1.1.1 -> 1.2.0" <<<"$DRY" || { echo "ABORT: dry-run $p không báo 1.1.1 -> 1.2.0"; exit 1; }
  [ "$H0" = "$H1" ] || { echo "ABORT: dry-run làm đổi config $p"; exit 1; }
done

echo ""
echo "OK 00_PRECHECK_PASS"
