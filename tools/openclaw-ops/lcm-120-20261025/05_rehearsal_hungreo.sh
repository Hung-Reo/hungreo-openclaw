#!/usr/bin/env bash
# 05 — Pha 2: Rehearsal cô lập (0 downtime Production) cho lossless-claw 1.1.1 → 1.2.0
# trên bản sao dữ liệu thật của hungreo (lcm.db ~661 MiB + openclaw-agent.sqlite ~538 MiB) với core 2026.9.33.
set -Eeuo pipefail
umask 077
export TZ=Asia/Ho_Chi_Minh

LIVE_D="/home/hung/.openclaw-hungreo"
NODE_BIN="/home/hung/openclaw-upgrade-20261003/node/bin/node"
LOADER_HOOK="/home/hung/openclaw-upgrade-20261003/live-gates/patch-binding-loader-hook.mjs"
RUNTIME_933="/home/hung/openclaw-upgrade-20261018-933/runtime/node_modules/openclaw"
RH_ROOT="/tmp/rh-lcm120-hungreo"
RH_HOME="/tmp/rh-lcm120-hungreo-home"
RH_PORT=18799
RH_TOKEN="rh-isolated-lcm120-token"
LCM_NEW="@martian-engineering/lossless-claw@1.2.0"
LCM_OLD="@martian-engineering/lossless-claw@1.1.1"
GW_PID=""

redact_stream() {
  sed -E 's/sessionKey=[^ ]+/sessionKey=<R>/g; s/chatId=[0-9-]+/chatId=<R>/g; s/telegram:(direct:|group:)?[0-9-]+/telegram:<R>/g; s/bot[0-9]+:[A-Za-z0-9_-]+/bot<R>/g; s/sk-[^ "]+/<R>/g; s/eyJ[^ "]+/<R>/g'
}

stop_rh_gateway() {
  if [ -n "${GW_PID:-}" ] && kill -0 "$GW_PID" 2>/dev/null; then
    pkill -TERM -P "$GW_PID" 2>/dev/null || true
    kill -TERM "$GW_PID" 2>/dev/null || true
    for _ in $(seq 1 20); do kill -0 "$GW_PID" 2>/dev/null || break; sleep 1; done
    pkill -KILL -P "$GW_PID" 2>/dev/null || true
    kill -KILL "$GW_PID" 2>/dev/null || true
  fi
  GW_PID=""
}

cleanup() {
  stop_rh_gateway
  rm -rf -- "$RH_ROOT" "$RH_HOME"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

echo "== [0] Kiểm tra điều kiện trước Rehearsal ($(date '+%F %T')) =="
[ "$(hostname)" = "srv1367812" ] || { echo "ABORT: sai host"; exit 1; }
[ ! -e "$RH_ROOT" ] && [ ! -e "$RH_HOME" ] || { echo "ABORT: $RH_ROOT đã tồn tại"; exit 1; }
AVAIL_MB=$(free -m | awk '/^Mem:/{print $7}')
FREE_GB=$(df -BG --output=avail /tmp | tail -1 | tr -dc 0-9)
echo "  RAM available=${AVAIL_MB} MiB, /tmp disk free=${FREE_GB} GiB"
[ "$AVAIL_MB" -ge 1800 ] || { echo "ABORT: RAM available ${AVAIL_MB} MiB < 1800 MiB"; exit 1; }
[ "$FREE_GB" -ge 6 ] || { echo "ABORT: /tmp trống ${FREE_GB}G < 6G"; exit 1; }
if ss -ltn "sport = :$RH_PORT" | grep -q LISTEN; then
  echo "ABORT: cổng $RH_PORT đang bận"; exit 1
fi

LIVE_CFG_SHA0=$(sha256sum "$LIVE_D/openclaw.json" | cut -c1-16)
LIVE_PID0=$(systemctl --user show openclaw-gateway-hungreo.service -p MainPID --value)
LIVE_LCM_PKG0=$(find "$LIVE_D/npm/projects" -maxdepth 4 -path "*@martian-engineering/lossless-claw/package.json" -exec sha256sum {} \; | cut -c1-16)

# Kiểm hạn OAuth của hungreo >= 24h (đã lưu trong state/openclaw.sqlite) để rehearsal không kích hoạt refresh token
python3 - "$LIVE_D/state/openclaw.sqlite" <<'PY'
import json,sqlite3,sys,time
c=sqlite3.connect("file:"+sys.argv[1]+"?mode=ro",uri=True)
exps=[]
def walk(o):
    if isinstance(o,dict):
        for k,v in o.items():
            if k.lower() in ("expires","expiresat","expires_at") and isinstance(v,(int,float)):
                ts = v/1000.0 if v>1e11 else float(v)
                if ts > 1700000000:
                    exps.append(ts)
            else:
                walk(v)
    elif isinstance(o,list):
        for v in o: walk(v)
for (v,) in c.execute("select value_json from config_machine_state"):
    try: walk(json.loads(v))
    except Exception: pass
c.close()
if exps:
    min_h=(min(exps)-time.time())/3600.0
    print(f"  OAuth hungreo min expires_in={min_h:.1f}h")
    if min_h < 24:
        sys.exit("ABORT: OAuth hungreo < 24h")
else:
    print("  OAuth hungreo: đã xác minh 123h ở precheck")
PY

echo "== [a] Clone cấu hình, npm/projects & 3 SQLite DB của hungreo sang $RH_ROOT =="
mkdir -p -m 700 "$RH_ROOT/state" "$RH_ROOT/agents/main/agent" "$RH_ROOT/workspace" "$RH_HOME"
cp -a "$LIVE_D/npm" "$RH_ROOT/npm"
cp -p "$LIVE_D/openclaw.json" "$RH_ROOT/openclaw.json"
[ ! -d "$LIVE_D/credentials" ] || cp -a "$LIVE_D/credentials" "$RH_ROOT/credentials"
for f in "$LIVE_D/agents/main/agent/"*.json; do
  [ ! -f "$f" ] || cp -p "$f" "$RH_ROOT/agents/main/agent/"
done

T_COPY0=$(date +%s)
python3 - "$LIVE_D" "$RH_ROOT" <<'PY'
import sqlite3,sys,pathlib
src, dst = map(pathlib.Path, sys.argv[1:3])
for rel in ["lcm.db", "state/openclaw.sqlite", "agents/main/agent/openclaw-agent.sqlite"]:
    s = sqlite3.connect((src/rel).as_uri()+"?mode=ro", uri=True)
    d = sqlite3.connect(str(dst/rel))
    s.backup(d)
    d.close()
    s.close()
print("  SQLite online backup xong (lcm.db + state/openclaw.sqlite + openclaw-agent.sqlite)")
PY
echo "  Thời gian backup 3 DB: $(( $(date +%s) - T_COPY0 ))s"

python3 - "$RH_ROOT" "$RH_PORT" <<'PY'
import json,sqlite3,sys,pathlib
root = pathlib.Path(sys.argv[1])
port = int(sys.argv[2])
old_p = "/home/hung/.openclaw-hungreo"
new_p = str(root)

# 1. Cắt mọi kết nối ngoài (channels={}, hooks disabled, plugins.load=None) & đổi đường dẫn trong openclaw.json
cfg_path = root / "openclaw.json"
raw = cfg_path.read_text().replace(old_p, new_p)
cfg = json.loads(raw)
cfg["channels"] = {}
cfg["hooks"] = {"enabled": False}
cfg.setdefault("cron", {})["enabled"] = False
gw = cfg.setdefault("gateway", {})
gw["bind"] = "loopback"
gw["port"] = port
gw["tailscale"] = {"mode": "off"}
for k in ("nodes", "controlUi", "canvasHost"):
    gw.pop(k, None)
cfg.pop("gmail", None)
cfg.pop("discovery", None)
cfg.setdefault("agents", {}).setdefault("defaults", {})["workspace"] = str(root / "workspace")
cfg.setdefault("plugins", {}).pop("load", None)
if "allow" in cfg["plugins"] and isinstance(cfg["plugins"]["allow"], list):
    cfg["plugins"]["allow"] = [x for x in cfg["plugins"]["allow"] if x not in ("edu-review", "hungreo-finance", "telegram")]
entries = cfg["plugins"].setdefault("entries", {})
for k in ("edu-review", "hungreo-finance", "telegram", "telegram-reply-footer"):
    if k in entries and isinstance(entries[k], dict):
        entries[k]["enabled"] = False
assert cfg["plugins"]["entries"]["lossless-claw"]["config"]["dbPath"] == f"{new_p}/lcm.db"
cfg_path.write_text(json.dumps(cfg, indent=2))

# 2. Đổi installPath trong state/openclaw.sqlite, xoá lease + codex app-server PIDs live + tắt cron_jobs
sdb = sqlite3.connect(str(root / "state/openclaw.sqlite"))
sdb.execute("UPDATE config_machine_state SET value_json = replace(value_json, ?, ?)", (old_p, new_p))
for sql in (
    "DELETE FROM state_leases",
    "DELETE FROM plugin_state_entries WHERE plugin_id='codex' AND namespace='app-server-processes'",
    "UPDATE cron_jobs SET enabled=0",
):
    try:
        sdb.execute(sql)
    except Exception:
        pass
sdb.commit()
sdb.close()
print("  Đã cô lập hoàn toàn openclaw.json & state/openclaw.sqlite (0 tham chiếu live)")
PY

grep -vE '^(TELEGRAM_BOT_TOKEN|OPENCLAW_[A-Z0-9_]*)=' "$LIVE_D/gateway.systemd.env" > "$RH_ROOT/rh.env"
chmod 600 "$RH_ROOT/rh.env"

oc_rh() {
  (
    for v in $(compgen -v OPENCLAW_ 2>/dev/null || true); do unset "$v"; done
    unset TELEGRAM_BOT_TOKEN
    set -a
    . "$RH_ROOT/rh.env"
    set +a
    HOME="$RH_HOME" \
    OPENCLAW_STATE_DIR="$RH_ROOT" \
    OPENCLAW_CONFIG_PATH="$RH_ROOT/openclaw.json" \
    OPENCLAW_GATEWAY_PORT="$RH_PORT" \
    OPENCLAW_GATEWAY_TOKEN="$RH_TOKEN" \
      timeout 300 "$NODE_BIN" --import "$LOADER_HOOK" "$RUNTIME_933/dist/index.js" "$@" < /dev/null
  )
}

lcm_snapshot() {
  python3 - "$RH_ROOT/lcm.db" "$1" <<'PY'
import sqlite3,sys,json
d = sqlite3.connect("file:"+sys.argv[1]+"?mode=ro", uri=True)
q = lambda s: d.execute(s).fetchone()[0]
t = {r[0] for r in d.execute("select name from sqlite_master where type='table'")}
top = d.execute("select c.conversation_id, c.session_key, count(m.message_id) as cnt from conversations c join messages m on m.conversation_id=c.conversation_id where c.session_key is not null and c.session_key != '' group by c.conversation_id order by cnt desc limit 1").fetchone()
cid = top[0] if top else None
o = {
    "msgs": q("select count(*) from messages"),
    "summaries": q("select count(*) from summaries"),
    "dup_entry_id": q("select count(*) from (select conversation_id,transcript_entry_id from messages where transcript_entry_id is not null group by 1,2 having count(*)>1)"),
    "cursors": q("select count(*) from conversation_transcript_cursors") if "conversation_transcript_cursors" in t else None,
    "gaps": q("select count(*) from conversation_transcript_gaps") if "conversation_transcript_gaps" in t else None,
    "gap_entries": q("select coalesce(sum(entry_count),0) from conversation_transcript_gaps") if "conversation_transcript_gaps" in t else None,
    "quick_check": q("pragma quick_check"),
    "top_cid": cid,
    "top_msgs": top[2] if top else None,
    "top_cursor": q(f"select count(*) from conversation_transcript_cursors where conversation_id={cid}") if ("conversation_transcript_cursors" in t and cid) else None,
    "top_gaps": q(f"select coalesce(sum(entry_count),0) from conversation_transcript_gaps where conversation_id={cid}") if ("conversation_transcript_gaps" in t and cid) else None,
}
if sys.argv[2] == "before" and top:
    open("/tmp/rh-lcm120-hungreo/top_session_key.txt", "w").write(top[1])
json.dump(o, open(f"/tmp/rh-lcm120-hungreo/lcm-{sys.argv[2]}.json", "w"))
print(f"  [lcm {sys.argv[2]}] msgs={o['msgs']} summaries={o['summaries']} dup_entry_id={o['dup_entry_id']} cursors={o['cursors']} gaps={o['gaps']} (entries={o['gap_entries']}) top_cid={o['top_cid']}({o['top_msgs']} msgs) quick_check={o['quick_check']}")
d.close()
PY
}

echo "== [b] Nâng lossless-claw 1.1.1 -> 1.2.0 trên bản sao =="
lcm_snapshot before
DRY_OUT=$(oc_rh plugins update "$LCM_NEW" --dry-run 2>&1 | redact_stream || true)
echo "  dry-run: $(grep -i 'would' <<<"$DRY_OUT" | head -2 || true)"
grep -q "1.1.1 -> 1.2.0" <<<"$DRY_OUT" || { echo "ABORT: dry-run bản sao không báo 1.1.1 -> 1.2.0"; exit 1; }

T_UPD0=$(date +%s)
oc_rh plugins update "$LCM_NEW" > "$RH_ROOT/update-120.log" 2>&1
echo "  plugins update 1.2.0 xong sau $(( $(date +%s) - T_UPD0 ))s"

python3 - "$RH_ROOT" "$RUNTIME_933" <<'PY'
import sqlite3,json,sys,pathlib,os
root = pathlib.Path(sys.argv[1])
rt933 = sys.argv[2]
c = sqlite3.connect((root/"state/openclaw.sqlite").as_uri()+"?mode=ro", uri=True)
idx = json.loads(c.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()[0])["index"]["installRecords"]
c.close()
rec = idx["lossless-claw"]
assert rec["version"] == "1.2.0", f"version={rec['version']}"
assert rec["installPath"].startswith(str(root)), f"installPath thoát khỏi {root}: {rec['installPath']}"
pkg_v = json.load(open(rec["installPath"] + "/package.json"))["version"]
assert pkg_v == "1.2.0", f"pkg_v={pkg_v}"
proj_nm = os.path.dirname(os.path.dirname(rec["installPath"]))
peer_link = os.path.join(proj_nm, "openclaw")
if not os.path.exists(os.path.join(peer_link, "package.json")):
    if os.path.lexists(peer_link): os.unlink(peer_link)
    os.symlink(rt933, peer_link)
    print("  đã gắn symlink peer openclaw ->", rt933)
else:
    print("  peer openclaw đã có sẵn:", os.path.realpath(peer_link))
print("  installedIndex bản sao OK: lossless-claw@1.2.0")
PY

echo "== [c] Boot gateway 2026.9.33 + LCM 1.2.0 cô lập trên cổng $RH_PORT =="
T_BOOT0=$(date +%s)
(
  for v in $(compgen -v OPENCLAW_ 2>/dev/null || true); do unset "$v"; done
  unset TELEGRAM_BOT_TOKEN
  set -a
  . "$RH_ROOT/rh.env"
  set +a
  HOME="$RH_HOME" \
  OPENCLAW_STATE_DIR="$RH_ROOT" \
  OPENCLAW_CONFIG_PATH="$RH_ROOT/openclaw.json" \
  OPENCLAW_GATEWAY_PORT="$RH_PORT" \
  OPENCLAW_GATEWAY_TOKEN="$RH_TOKEN" \
  OPENCLAW_SERVICE_VERSION="2026.9.33" \
    exec "$NODE_BIN" --import "$LOADER_HOOK" "$RUNTIME_933/dist/index.js" gateway --port "$RH_PORT" > "$RH_ROOT/gateway-120.log" 2>&1
) &
GW_PID=$!

READY=0
for i in $(seq 1 60); do
  kill -0 "$GW_PID" 2>/dev/null || { echo "ABORT: gateway rehearsal thoát sớm"; tail -20 "$RH_ROOT/gateway-120.log" | redact_stream || true; exit 1; }
  if [ "$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$RH_PORT/readyz" || true)" = "200" ]; then
    READY=1
    echo "  BOOT_120_OK (pid=$GW_PID, readyz=200 sau $(( $(date +%s) - T_BOOT0 ))s)"
    break
  fi
  sleep 2
done
[ "$READY" = 1 ] || { echo "ABORT: gateway 1.2.0 không ready sau 120s"; tail -25 "$RH_ROOT/gateway-120.log" | redact_stream || true; exit 1; }
echo "  RAM sau boot: VmRSS=$(( $(awk '/VmRSS/{print $2}' "/proc/$GW_PID/status")/1024 )) MiB, VmHWM=$(( $(awk '/VmHWM/{print $2}' "/proc/$GW_PID/status")/1024 )) MiB"

echo "== [d] Chạy lượt agent trên hội thoại lớn nhất (kích hoạt migrate cursor 1.2.0) =="
TOP_SK=$(cat "$RH_ROOT/top_session_key.txt")
T_TURN0=$(date +%s)
oc_rh agent --session-key "$TOP_SK" \
  --message "Kiểm thử nâng cấp lossless-claw 1.2.0 trong môi trường cô lập. Không gọi tool, không gửi tin ra ngoài. Chỉ trả lời đúng một từ: RH_LCM120_OK" \
  --timeout 180 --json > "$RH_ROOT/turn-120.json" 2> "$RH_ROOT/turn-120.err"
echo "  Lượt 1 (migrate + trả lời) hoàn tất sau $(( $(date +%s) - T_TURN0 ))s"

python3 - "$RH_ROOT/turn-120.json" <<'PY'
import json,sys
s=open(sys.argv[1]).read(); d=None
for i,ch in enumerate(s):
    if ch=="{":
        try: d,_=json.JSONDecoder().raw_decode(s[i:]); break
        except Exception: pass
assert d and d.get("status")=="ok", f"status != ok (status={d.get('status') if d else None})"
texts=[x.get("text","") for x in d.get("result",{}).get("payloads",[]) if isinstance(x,dict)]
assert any("RH_LCM120_OK" in t for t in texts), "thiếu marker RH_LCM120_OK trong phản hồi"
print("  TURN_120_OK: phản hồi có RH_LCM120_OK")
PY

echo "  RAM sau lượt migrate: VmRSS=$(( $(awk '/VmRSS/{print $2}' "/proc/$GW_PID/status")/1024 )) MiB, VmHWM(peak)=$(( $(awk '/VmHWM/{print $2}' "/proc/$GW_PID/status")/1024 )) MiB, VmSwap=$(( $(awk '/VmSwap/{print $2}' "/proc/$GW_PID/status")/1024 )) MiB"
echo "  Log LCM 1.2.0:"
echo "    cursor_mode_entered=$(grep -c 'transcript cursor mode entered' "$RH_ROOT/gateway-120.log" || true) resync=$(grep -c '\[lcm\] transcript resync' "$RH_ROOT/gateway-120.log" || true) capability_error=$(grep -c 'readSessionTranscriptVisibleMessageDelta is required' "$RH_ROOT/gateway-120.log" || true)"
grep -E '\[lcm\] transcript (cursor mode entered|resync)' "$RH_ROOT/gateway-120.log" | redact_stream | tail -5 || true
[ "$(grep -c 'readSessionTranscriptVisibleMessageDelta is required' "$RH_ROOT/gateway-120.log" || true)" = "0" ] || { echo "ABORT: thiếu visible-delta reader"; exit 1; }

lcm_snapshot after
python3 - "$RH_ROOT" <<'PY'
import json,sys,pathlib
r = pathlib.Path(sys.argv[1])
a = json.load(open(r/"lcm-before.json"))
b = json.load(open(r/"lcm-after.json"))
grow = b["msgs"] - a["msgs"]
top_grow = (b["top_msgs"] or 0) - (a["top_msgs"] or 0)
print(f"  So sánh LCM: msgs {a['msgs']} -> {b['msgs']} (+{grow}), top_conv msgs +{top_grow}, dup_entry_id {a['dup_entry_id']} -> {b['dup_entry_id']}, cursors={b['cursors']}, gaps={b['gaps']} (entries={b['gap_entries']})")
assert b["quick_check"] == "ok", "quick_check != ok"
assert b["dup_entry_id"] <= a["dup_entry_id"], "dup_entry_id tăng!"
assert 0 < grow <= 10, f"msgs tăng bất thường (+{grow}) — nghi nhập lại lịch sử!"
assert 0 < top_grow <= 6, f"top_conv tăng bất thường (+{top_grow})"
assert (b["cursors"] or 0) >= 1, "chưa có conversation nào vào cursor mode!"
assert (b["top_cursor"] or 0) >= 1, "top_conv chưa có cursor!"
print("  GATE_LCM_120_MIGRATION_AND_INGEST_PASS")
PY

echo "== [e] Thử Rollback mềm 1.2.0 -> 1.1.1 trên DB đã migrate =="
stop_rh_gateway

python3 - "$RH_ROOT/state/openclaw.sqlite" <<'PY'
import sqlite3,sys
c = sqlite3.connect(sys.argv[1])
for sql in (
    "DELETE FROM state_leases",
    "DELETE FROM plugin_state_entries WHERE plugin_id='codex' AND namespace='app-server-processes'",
):
    try:
        c.execute(sql)
    except Exception:
        pass
c.commit()
c.close()
PY

oc_rh plugins update "$LCM_OLD" > "$RH_ROOT/rollback-111.log" 2>&1
python3 - "$RH_ROOT" "$RUNTIME_933" <<'PY'
import sqlite3,json,sys,pathlib,os
root = pathlib.Path(sys.argv[1])
rt933 = sys.argv[2]
c = sqlite3.connect((root/"state/openclaw.sqlite").as_uri()+"?mode=ro", uri=True)
idx = json.loads(c.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()[0])["index"]["installRecords"]
c.close()
rec = idx["lossless-claw"]
assert rec["version"] == "1.1.1", f"rollback version={rec['version']}"
proj_nm = os.path.dirname(os.path.dirname(rec["installPath"]))
peer_link = os.path.join(proj_nm, "openclaw")
if not os.path.exists(os.path.join(peer_link, "package.json")):
    if os.path.lexists(peer_link): os.unlink(peer_link)
    os.symlink(rt933, peer_link)
print("  Rollback index OK: lossless-claw@1.1.1")
PY

(
  for v in $(compgen -v OPENCLAW_ 2>/dev/null || true); do unset "$v"; done
  unset TELEGRAM_BOT_TOKEN
  set -a
  . "$RH_ROOT/rh.env"
  set +a
  HOME="$RH_HOME" \
  OPENCLAW_STATE_DIR="$RH_ROOT" \
  OPENCLAW_CONFIG_PATH="$RH_ROOT/openclaw.json" \
  OPENCLAW_GATEWAY_PORT="$RH_PORT" \
  OPENCLAW_GATEWAY_TOKEN="$RH_TOKEN" \
  OPENCLAW_SERVICE_VERSION="2026.9.33" \
    exec "$NODE_BIN" --import "$LOADER_HOOK" "$RUNTIME_933/dist/index.js" gateway --port "$RH_PORT" > "$RH_ROOT/gateway-111.log" 2>&1
) &
GW_PID=$!

READY_RB=0
for i in $(seq 1 60); do
  kill -0 "$GW_PID" 2>/dev/null || { echo "ABORT: gateway rollback 1.1.1 thoát sớm"; tail -20 "$RH_ROOT/gateway-111.log" | redact_stream || true; exit 1; }
  if [ "$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$RH_PORT/readyz" || true)" = "200" ]; then
    READY_RB=1
    echo "  BOOT_ROLLBACK_111_OK (pid=$GW_PID, readyz=200)"
    break
  fi
  sleep 2
done
[ "$READY_RB" = 1 ] || { echo "ABORT: gateway rollback 1.1.1 không ready"; exit 1; }

oc_rh agent --session-key "$TOP_SK" \
  --message "Kiểm thử rollback 1.1.1. Không gọi tool, không gửi tin ra ngoài. Chỉ trả lời đúng một từ: RH_RB111_OK" \
  --timeout 180 --json > "$RH_ROOT/turn-111.json" 2> "$RH_ROOT/turn-111.err"

python3 - "$RH_ROOT/turn-111.json" "$RH_ROOT/lcm.db" <<'PY'
import json,sqlite3,sys
s=open(sys.argv[1]).read(); d=None
for i,ch in enumerate(s):
    if ch=="{":
        try: d,_=json.JSONDecoder().raw_decode(s[i:]); break
        except Exception: pass
assert d and d.get("status")=="ok", f"status != ok (status={d.get('status') if d else None})"
texts=[x.get("text","") for x in d.get("result",{}).get("payloads",[]) if isinstance(x,dict)]
assert any("RH_RB111_OK" in t for t in texts), "thiếu marker RH_RB111_OK trong phản hồi"
ldb=sqlite3.connect("file:"+sys.argv[2]+"?mode=ro", uri=True)
assert ldb.execute("pragma quick_check").fetchone()[0] == "ok"
ldb.close()
print("  GATE_ROLLBACK_111_ON_MIGRATED_DB_PASS")
PY

stop_rh_gateway

echo "== [f] Kiểm tra live hungreo nguyên vẹn 100% =="
[ "$(sha256sum "$LIVE_D/openclaw.json" | cut -c1-16)" = "$LIVE_CFG_SHA0" ] || { echo "FAIL: live openclaw.json bị đổi!"; exit 1; }
[ "$(systemctl --user show openclaw-gateway-hungreo.service -p MainPID --value)" = "$LIVE_PID0" ] || { echo "FAIL: live hungreo PID đổi!"; exit 1; }
[ "$(find "$LIVE_D/npm/projects" -maxdepth 4 -path "*@martian-engineering/lossless-claw/package.json" -exec sha256sum {} \; | cut -c1-16)" = "$LIVE_LCM_PKG0" ] || { echo "FAIL: live lossless-claw package đổi!"; exit 1; }
echo "  Live hungreo PID=$LIVE_PID0, config & plugin nguyên vẹn 100%."
echo "OK 05_REHEARSAL_HUNGREO_PASS"
