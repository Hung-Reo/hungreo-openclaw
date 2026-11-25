#!/usr/bin/env bash
# 30_stage_and_rehearsal_934.sh — Pha B1:
#   1. Stage openclaw@2026.9.34 (extended-stable) vào /home/hung/openclaw-upgrade-20261026-934/runtime bằng Node v24.22.1
#   2. Kiểm tra live-gates + hàm delta transcript trên 2026.9.34
#   3. Rehearsal cô lập (0 downtime Production) trên bản sao đầy đủ của hungreo (/tmp/rh-934-hungreo, cổng :18799):
#      - Cập nhật @openclaw/codex@2026.9.34 + relink peerDependencies sang 2026.9.34
#      - Kiểm tra doctor --lint & schema DB (đảm bảo 9.34 không ép migrate DB một chiều như 10.5+)
#      - Boot gateway 2026.9.34 + Node v24.22.1 + LCM 1.2.0
#      - Chạy 3 lượt agent LIÊN TIẾP trên hội thoại lớn nhất (top_session_key) để đo trực tiếp generation_mismatch / cursor_reset ở lượt 2-3
#      - Chạy 1 lượt recall (lcm_grep)
#      - Thử Rollback 9.34 -> 9.33 trên chính bản sao và chạy 1 lượt agent xác nhận tương thích 2 chiều
set -Eeuo pipefail
umask 077
export TZ=Asia/Ho_Chi_Minh
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

NODE_DIR="/home/hung/openclaw-node-24.22.1/node/bin"
NODE_BIN="${NODE_DIR}/node"
NPM_BIN="${NODE_DIR}/npm"
export PATH="${NODE_DIR}:/usr/local/bin:/usr/bin:/bin"

LOADER_HOOK="/home/hung/openclaw-upgrade-20261003/live-gates/patch-binding-loader-hook.mjs"
LIVE_GATES_DIR="/home/hung/openclaw-upgrade-20261003/live-gates"

ROOT_934="/home/hung/openclaw-upgrade-20261026-934"
RT_934="${ROOT_934}/runtime"
OC_934="${RT_934}/node_modules/openclaw"
EXPECTED_934_INTEGRITY="sha512-Wc+LPY2SNcq4Vv/SeMhHLyIm2omxzoKeJ6WTBV4W4ATSPAyDIlkwD1uFNNRbv2GDszstS2BiqfiLF7MHAsT13w=="

RT_933="/home/hung/openclaw-upgrade-20261018-933/runtime/node_modules/openclaw"
LIVE_D="/home/hung/.openclaw-hungreo"
RH_ROOT="/tmp/rh-934-hungreo"
RH_HOME="/tmp/rh-934-hungreo-home"
RH_PORT=18799
RH_TOKEN="rh-isolated-934-token"
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

echo "== [0] Precheck trước khi Stage & Rehearsal 2026.9.34 ($(date '+%F %T')) =="
[ "$(hostname)" = "srv1367812" ] || { echo "ABORT: sai host"; exit 1; }
[ -x "$NODE_BIN" ] && [ "$("$NODE_BIN" -v)" = "v24.22.1" ] || { echo "ABORT: cần Node v24.22.1 tại $NODE_BIN"; exit 1; }
[ ! -e "$RH_ROOT" ] && [ ! -e "$RH_HOME" ] || { echo "ABORT: $RH_ROOT đã tồn tại"; exit 1; }
AVAIL_MB=$(free -m | awk '/^Mem:/{print $7}')
FREE_GB=$(df -BG --output=avail /home/hung | tail -1 | tr -dc 0-9)
FREE_TMP_GB=$(df -BG --output=avail /tmp | tail -1 | tr -dc 0-9)
echo "  RAM available=${AVAIL_MB} MiB, /home/hung free=${FREE_GB} GiB, /tmp free=${FREE_TMP_GB} GiB"
[ "$AVAIL_MB" -ge 1800 ] || { echo "ABORT: RAM available ${AVAIL_MB} MiB < 1800 MiB"; exit 1; }
[ "$FREE_GB" -ge 6 ] || { echo "ABORT: disk free ${FREE_GB}G < 6G"; exit 1; }
[ "$FREE_TMP_GB" -ge 6 ] || { echo "ABORT: /tmp free ${FREE_TMP_GB}G < 6G"; exit 1; }
if ss -ltn "sport = :$RH_PORT" | grep -q LISTEN; then
  echo "ABORT: cổng $RH_PORT đang bận"; exit 1
fi

LIVE_PID_H0=$(systemctl --user show openclaw-gateway-hungreo.service -p MainPID --value)
LIVE_PID_S0=$(systemctl --user show openclaw-gateway-suckhoe.service -p MainPID --value)
LIVE_CFG_H0=$(sha256sum "$LIVE_D/openclaw.json" | cut -c1-16)

python3 - "$LIVE_D/state/openclaw.sqlite" <<'PY'
import json, sqlite3, sys, time
c = sqlite3.connect("file:" + sys.argv[1] + "?mode=ro", uri=True)
exps = []
def walk(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k.lower() in ("expires", "expiresat", "expires_at") and isinstance(v, (int, float)):
                ts = v / 1000.0 if v > 1e11 else float(v)
                if ts > 1700000000:
                    exps.append(ts)
            else:
                walk(v)
    elif isinstance(o, list):
        for v in o:
            walk(v)
for (v,) in c.execute("select value_json from config_machine_state"):
    try:
        walk(json.loads(v))
    except Exception:
        pass
c.close()
min_h = (min(exps) - time.time()) / 3600.0 if exps else 0
print(f"  OAuth hungreo min expires_in={min_h:.1f}h")
assert min_h >= 24, f"ABORT: OAuth hungreo < 24h ({min_h:.1f}h)"
PY

echo "== [1] Stage openclaw@2026.9.34 vào ${RT_934} =="
mkdir -p -m 755 "$RT_934/bin" "$ROOT_934/npm-cache" "$ROOT_934/ops"
if [ -f "$OC_934/package.json" ] && [ "$(jq -r .version "$OC_934/package.json" 2>/dev/null || true)" = "2026.9.34" ]; then
  echo "  openclaw@2026.9.34 đã được stage sẵn tại $OC_934"
else
  cat << 'EOF_PKG' > "$RT_934/package.json"
{
  "name": "openclaw-staged-runtime-934",
  "private": true,
  "dependencies": {
    "openclaw": "2026.9.34"
  }
}
EOF_PKG
  (
    cd "$RT_934"
    npm_config_cache="$ROOT_934/npm-cache" \
      "$NODE_BIN" "$NPM_BIN" install --omit=dev --no-audit --no-fund --package-lock
  )
fi

LOCK_INTEGRITY=$(jq -r '.packages["node_modules/openclaw"].integrity // empty' "$RT_934/package-lock.json")
echo "  package-lock integrity=$LOCK_INTEGRITY"
[ "$LOCK_INTEGRITY" = "$EXPECTED_934_INTEGRITY" ] || { echo "ABORT: integrity mismatch ($LOCK_INTEGRITY != $EXPECTED_934_INTEGRITY)"; exit 1; }

cat << EOF_WRAP > "$RT_934/bin/openclaw"
#!/usr/bin/env bash
export PATH="${NODE_DIR}:\$PATH"
exec "${NODE_BIN}" "${OC_934}/dist/index.js" "\$@"
EOF_WRAP
chmod 755 "$RT_934/bin/openclaw"

echo "== [2] Kiểm tra Live-Gates & Hàm Delta Transcript trên 2026.9.34 =="
"$NODE_BIN" --test "$LIVE_GATES_DIR/patch-openclaw-plugin-binding-decline-fallback.test.mjs" >/dev/null
"$NODE_BIN" "$LIVE_GATES_DIR/verify-command-registry-98.mjs" "$OC_934/dist"
"$NODE_BIN" - "$OC_934" <<'JS'
const path = require("node:path");
const rt = process.argv[2];
const pkg = require(path.join(rt, "package.json"));
const sdk = require(path.join(rt, "dist/plugin-sdk/session-transcript-runtime.js"));
console.log("  9.34 check:", {
  version: pkg.version,
  engines: pkg.engines,
  hasVisibleDelta: typeof sdk.readSessionTranscriptVisibleMessageDelta === "function",
  hasRawDelta: typeof sdk.readSessionTranscriptRawDelta === "function",
});
if (pkg.version !== "2026.9.34" || typeof sdk.readSessionTranscriptVisibleMessageDelta !== "function" || typeof sdk.readSessionTranscriptRawDelta !== "function") {
  process.exit(1);
}
JS
echo "  STAGE_AND_GATES_934_OK"

echo "== [3] Clone dữ liệu hungreo sang $RH_ROOT (cô lập hoàn toàn) =="
mkdir -p -m 700 "$RH_ROOT/state" "$RH_ROOT/agents/main/agent" "$RH_ROOT/workspace" "$RH_HOME"
cp -a "$LIVE_D/npm" "$RH_ROOT/npm"
cp -p "$LIVE_D/openclaw.json" "$RH_ROOT/openclaw.json"
[ ! -d "$LIVE_D/credentials" ] || cp -a "$LIVE_D/credentials" "$RH_ROOT/credentials"
for f in "$LIVE_D/agents/main/agent/"*.json; do
  [ ! -f "$f" ] || cp -p "$f" "$RH_ROOT/agents/main/agent/"
done

T_COPY0=$(date +%s)
python3 - "$LIVE_D" "$RH_ROOT" "$RH_PORT" <<'PY'
import json, pathlib, sqlite3, sys
src, dst = map(pathlib.Path, sys.argv[1:3])
port = int(sys.argv[3])
for rel in ["lcm.db", "state/openclaw.sqlite", "agents/main/agent/openclaw-agent.sqlite"]:
    s = sqlite3.connect((src / rel).as_uri() + "?mode=ro", uri=True)
    d = sqlite3.connect(str(dst / rel))
    s.backup(d)
    d.close()
    s.close()

old_p = str(src)
new_p = str(dst)
cfg_path = dst / "openclaw.json"
cfg = json.loads(cfg_path.read_text().replace(old_p, new_p))
cfg["channels"] = {}
cfg["hooks"] = {"enabled": False}
cfg.setdefault("cron", {})["enabled"] = False
gw = cfg.setdefault("gateway", {})
gw["bind"] = "loopback"
gw["port"] = port
gw["tailscale"] = {"mode": "off"}
for k in ("nodes", "controlUi", "canvasHost", "remote"):
    gw.pop(k, None)
cfg.pop("gmail", None)
cfg.pop("discovery", None)
cfg.setdefault("agents", {}).setdefault("defaults", {})["workspace"] = str(dst / "workspace")
cfg.setdefault("plugins", {}).pop("load", None)
if "allow" in cfg["plugins"] and isinstance(cfg["plugins"]["allow"], list):
    cfg["plugins"]["allow"] = [x for x in cfg["plugins"]["allow"] if x not in ("edu-review", "hungreo-finance", "telegram")]
entries = cfg["plugins"].setdefault("entries", {})
for k in ("edu-review", "hungreo-finance", "telegram", "telegram-reply-footer"):
    if k in entries and isinstance(entries[k], dict):
        entries[k]["enabled"] = False
assert cfg["plugins"]["entries"]["lossless-claw"]["config"]["dbPath"] == f"{new_p}/lcm.db"
cfg_path.write_text(json.dumps(cfg, indent=2))

sdb = sqlite3.connect(str(dst / "state/openclaw.sqlite"))
sdb.execute("UPDATE config_machine_state SET value_json = replace(value_json, ?, ?)", (old_p, new_p))
row = sdb.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()
records = json.loads(row[0])["index"]["installRecords"]
(dst / "peer-records.json").write_text(json.dumps(records, indent=2))
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

ldb = sqlite3.connect(f"file:{dst}/lcm.db?mode=ro", uri=True)
top = ldb.execute("select c.conversation_id, c.session_key, count(m.message_id) as cnt from conversations c join messages m on m.conversation_id=c.conversation_id where c.session_key is not null and c.session_key != '' group by c.conversation_id order by cnt desc limit 1").fetchone()
ldb.close()
assert top, "Không tìm thấy top conversation"
(dst / "top_session_key.txt").write_text(top[1])
(dst / "top_cid.txt").write_text(str(top[0]))
print(f"  Clone 3 DB & cô lập xong (top_cid={top[0]}, msgs={top[2]})")
PY
echo "  Thời gian clone: $(( $(date +%s) - T_COPY0 ))s"

grep -vE '^(TELEGRAM_BOT_TOKEN|OPENCLAW_[A-Z0-9_]*)=' "$LIVE_D/gateway.systemd.env" > "$RH_ROOT/rh.env" || true
chmod 600 "$RH_ROOT/rh.env"

oc_rh() {
  local rt_dir="$1"; shift
  (
    for v in $(compgen -v OPENCLAW_ 2>/dev/null || true); do unset "$v"; done
    unset TELEGRAM_BOT_TOKEN
    set -a
    . "$RH_ROOT/rh.env"
    set +a
    export PATH="${NODE_DIR}:/usr/bin:/bin"
    export NODE_OPTIONS="--max-old-space-size=512"
    export npm_config_cache="$ROOT_934/npm-cache"
    HOME="$RH_HOME" \
    OPENCLAW_STATE_DIR="$RH_ROOT" \
    OPENCLAW_CONFIG_PATH="$RH_ROOT/openclaw.json" \
    OPENCLAW_GATEWAY_PORT="$RH_PORT" \
    OPENCLAW_GATEWAY_TOKEN="$RH_TOKEN" \
    OPENCLAW_GATEWAY_REMOTE_TOKEN="$RH_TOKEN" \
      timeout 300 "$NODE_BIN" --import "$LOADER_HOOK" "$rt_dir/dist/index.js" "$@" < /dev/null
  )
}

relink_peers() {
  local target_rt="$1"
  python3 - "$RH_ROOT" "$target_rt" <<'PY'
import json, os, pathlib, shutil, sqlite3, sys
root = pathlib.Path(sys.argv[1])
target_rt = sys.argv[2]
c = sqlite3.connect(f"file:{root}/state/openclaw.sqlite?mode=ro", uri=True)
idx = json.loads(c.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()[0])["index"]["installRecords"]
c.close()

def force_link(peer: pathlib.Path):
    assert str(peer).startswith(str(root) + "/npm/projects/"), f"Unsafe peer path: {peer}"
    peer.parent.mkdir(parents=True, exist_ok=True)
    if peer.is_symlink() or peer.is_file():
        peer.unlink()
    elif peer.is_dir():
        shutil.rmtree(peer)
    os.symlink(target_rt, str(peer))

# 1. Cập nhật mọi symlink openclaw hiện có dưới npm/projects (cả outer lẫn inner node_modules/openclaw)
all_links = 0
for p in (root / "npm/projects").rglob("openclaw"):
    if p.is_symlink():
        force_link(p)
        all_links += 1

# 2. Đảm bảo từng plugin trong installedIndex có cả outer & inner node_modules/openclaw trỏ tới target_rt
relinked = []
for pid, rec in idx.items():
    ipath = rec.get("installPath") or ""
    if not ipath.startswith(str(root)) or "/npm/projects/" not in ipath:
        continue
    pkg_dir = pathlib.Path(ipath)
    nm = pkg_dir.parent
    if nm.name.startswith("@"):
        nm = nm.parent
    force_link(nm / "openclaw")
    force_link(pkg_dir / "node_modules/openclaw")
    relinked.append(pid)
print(f"  Relinked peer openclaw -> {target_rt} (rglob_links={all_links}, plugins={relinked})")
PY
}

lcm_snap() {
  local label="$1"
  python3 - "$RH_ROOT" "$label" <<'PY'
import json, pathlib, sqlite3, sys
r = pathlib.Path(sys.argv[1])
label = sys.argv[2]
cid = int((r / "top_cid.txt").read_text().strip())
d = sqlite3.connect(f"file:{r}/lcm.db?mode=ro", uri=True)
d.row_factory = sqlite3.Row
q = lambda s: d.execute(s).fetchone()[0]
row = d.execute(f"select * from conversation_transcript_cursors where conversation_id={cid}").fetchone()
cur_row = {k: (v[:16] + "..." if k == "cursor" and isinstance(v, str) else v) for k, v in dict(row).items() if "path" not in k.lower() and "session" not in k.lower()} if row else None
o = {
    "msgs": q("select count(*) from messages"),
    "top_msgs": q(f"select count(*) from messages where conversation_id={cid}"),
    "summaries": q("select count(*) from summaries"),
    "dup_entry_id": q("select count(*) from (select conversation_id, transcript_entry_id from messages where transcript_entry_id is not null group by 1,2 having count(*)>1)"),
    "cursors": q("select count(*) from conversation_transcript_cursors"),
    "gaps": q("select count(*) from conversation_transcript_gaps"),
    "gap_entries": q("select coalesce(sum(entry_count),0) from conversation_transcript_gaps"),
    "top_cursor": cur_row,
    "quick_check": q("pragma quick_check"),
}
d.close()
(r / f"lcm-{label}.json").write_text(json.dumps(o, indent=2))
print(f"  [lcm {label}] msgs={o['msgs']} top_msgs={o['top_msgs']} summaries={o['summaries']} dup_entry_id={o['dup_entry_id']} cursors={o['cursors']} gaps={o['gaps']}({o['gap_entries']}) top_cursor={cur_row} quick_check={o['quick_check']}")
PY
}

echo "== [4] Cập nhật @openclaw/codex@2026.9.34 & Relink Peers trên bản sao =="
lcm_snap before
DRY_CODEX=$(oc_rh "$OC_934" plugins update "@openclaw/codex@2026.9.34" --dry-run 2>&1 | redact_stream || true)
echo "  dry-run codex: $(grep -i 'Would update codex' <<<"$DRY_CODEX" || true)"
grep -q "Would update codex: 2026.9.33 -> 2026.9.34" <<<"$DRY_CODEX" || { echo "ABORT: dry-run codex không khớp"; echo "$DRY_CODEX" | tail -15; exit 1; }

oc_rh "$OC_934" plugins update "@openclaw/codex@2026.9.34" > "$RH_ROOT/codex-934-update.log" 2>&1
relink_peers "$OC_934"

echo "== [5] Boot Gateway 2026.9.34 + Node v24.22.1 + LCM 1.2.0 trên cổng $RH_PORT =="
T_BOOT0=$(date +%s)
(
  for v in $(compgen -v OPENCLAW_ 2>/dev/null || true); do unset "$v"; done
  unset TELEGRAM_BOT_TOKEN
  set -a
  . "$RH_ROOT/rh.env"
  set +a
  export PATH="${NODE_DIR}:/usr/bin:/bin"
  HOME="$RH_HOME" \
  OPENCLAW_STATE_DIR="$RH_ROOT" \
  OPENCLAW_CONFIG_PATH="$RH_ROOT/openclaw.json" \
  OPENCLAW_GATEWAY_PORT="$RH_PORT" \
  OPENCLAW_GATEWAY_TOKEN="$RH_TOKEN" \
  OPENCLAW_SERVICE_VERSION="2026.9.34" \
    exec "$NODE_BIN" --import "$LOADER_HOOK" "$OC_934/dist/index.js" gateway --port "$RH_PORT" > "$RH_ROOT/gateway-934.log" 2>&1
) &
GW_PID=$!

READY=0
for _ in $(seq 1 60); do
  kill -0 "$GW_PID" 2>/dev/null || { echo "ABORT: gateway 9.34 thoát sớm"; tail -25 "$RH_ROOT/gateway-934.log" | redact_stream || true; exit 1; }
  if [ "$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$RH_PORT/readyz" || true)" = "200" ]; then
    READY=1
    echo "  BOOT_934_OK (pid=$GW_PID, readyz=200 sau $(( $(date +%s) - T_BOOT0 ))s)"
    break
  fi
  sleep 2
done
[ "$READY" = 1 ] || { echo "ABORT: gateway 9.34 không ready sau 120s"; tail -25 "$RH_ROOT/gateway-934.log" | redact_stream || true; exit 1; }

echo "== [6] Chạy 3 lượt agent LIÊN TIẾP trên top_session_key để đo generation_mismatch + 1 lượt recall lcm_grep =="
TOP_SK=$(cat "$RH_ROOT/top_session_key.txt")
TOP_CID=$(cat "$RH_ROOT/top_cid.txt")

for turn_idx in 1 2 3; do
  T0=$(date +%s)
  MARKER="RH_934_TURN_${turn_idx}_OK"
  oc_rh "$OC_934" agent --session-key "$TOP_SK" \
    --message "Kiểm thử rehearsal OpenClaw 2026.9.34 lượt ${turn_idx}/3 trong môi trường cô lập. Không gọi tool, không gửi tin ra ngoài. Chỉ trả lời đúng một từ: ${MARKER}" \
    --timeout 180 --json > "$RH_ROOT/turn-${turn_idx}.json" 2> "$RH_ROOT/turn-${turn_idx}.err"
  DT=$(( $(date +%s) - T0 ))
  python3 - "$RH_ROOT/turn-${turn_idx}.json" "$MARKER" "$turn_idx" "$DT" <<'PY'
import json, sys
s = open(sys.argv[1]).read()
marker, idx, dt = sys.argv[2], sys.argv[3], sys.argv[4]
d = None
for i, ch in enumerate(s):
    if ch == "{":
        try:
            d, _ = json.JSONDecoder().raw_decode(s[i:])
            break
        except Exception:
            pass
assert d and d.get("status") == "ok", f"Turn {idx} status != ok"
texts = [x.get("text", "") for x in d.get("result", {}).get("payloads", []) if isinstance(x, dict)]
assert any(marker in t for t in texts), f"Thiếu {marker} ở lượt {idx}"
print(f"  TURN_{idx}_OK ({dt}s): có {marker}")
PY
  sleep 2
  lcm_snap "turn${turn_idx}"
done

echo "  -- Chạy lượt 4: Recall qua lcm_grep trên 2026.9.34:"
T_REC0=$(date +%s)
oc_rh "$OC_934" agent --session-key "$TOP_SK" \
  --message "Dùng đúng công cụ lcm_grep tìm cụm từ 'RH_934_TURN_1_OK' trong hội thoại hiện tại, không gọi công cụ khác, rồi trả lời kèm chuỗi RECALL_934_OK." \
  --timeout 180 --json > "$RH_ROOT/turn-recall.json" 2> "$RH_ROOT/turn-recall.err"
echo "  Lượt recall hoàn tất sau $(( $(date +%s) - T_REC0 ))s"
python3 - "$RH_ROOT/turn-recall.json" <<'PY'
import json, sys
s = open(sys.argv[1]).read()
d = None
for i, ch in enumerate(s):
    if ch == "{":
        try:
            d, _ = json.JSONDecoder().raw_decode(s[i:])
            break
        except Exception:
            pass
assert d and d.get("status") == "ok", "Recall status != ok"
texts = [x.get("text", "") for x in d.get("result", {}).get("payloads", []) if isinstance(x, dict)]
assert any("RECALL_934_OK" in t for t in texts), "Thiếu RECALL_934_OK ở lượt recall"
print("  RECALL_TURN_OK:", any("RECALL_934_OK" in t for t in texts))
PY
sleep 2
lcm_snap after_recall

echo "  -- Phân tích log LCM & gateway 9.34 sau 4 lượt liên tiếp:"
echo "    VmRSS=$(( $(awk '/VmRSS/{print $2}' "/proc/$GW_PID/status")/1024 )) MiB, VmHWM(peak)=$(( $(awk '/VmHWM/{print $2}' "/proc/$GW_PID/status")/1024 )) MiB, VmSwap=$(( $(awk '/VmSwap/{print $2}' "/proc/$GW_PID/status")/1024 )) MiB"
echo "    gateway log cursor_reset=$(grep -c 'transcript cursor reset' "$RH_ROOT/gateway-934.log" || true) resync=$(grep -c 'transcript resync' "$RH_ROOT/gateway-934.log" || true) capability_error=$(grep -c 'readSessionTranscriptVisibleMessageDelta is required' "$RH_ROOT/gateway-934.log" || true) degraded_legacy=$(grep -c 'degraded to "legacy"' "$RH_ROOT/gateway-934.log" || true)"
[ "$(grep -c 'readSessionTranscriptVisibleMessageDelta is required' "$RH_ROOT/gateway-934.log" || true)" = "0" ] || { echo "ABORT: capability_error > 0"; exit 1; }
grep -iE 'transcript (cursor|resync)|generation_mismatch|lossless|context-engine|degraded|peer' "$RH_ROOT/gateway-934.log" | redact_stream | tail -15 || true
if [ -s "$RH_ROOT/turn-1.err" ]; then
  echo "    turn-1.err:"
  cat "$RH_ROOT/turn-1.err" | redact_stream | tail -10 || true
fi

# Kiểm tra cả /tmp/openclaw/lossless-claw-<date>.log trong khung giờ chạy rehearsal
START_UTC=$(date -u -d "@$T_BOOT0" '+%FT%T')
LCM_TMP_LOG="/tmp/openclaw/lossless-claw-$(date +%F).log"
if [ -f "$LCM_TMP_LOG" ]; then
  RH_LCM_LINES=$(awk -v t="$START_UTC" -F'"time":"' '{split($2,a,"\""); if(a[1]>=t) print}' "$LCM_TMP_LOG" | grep "conversation=${TOP_CID} " || true)
  echo "    /tmp/openclaw log (conv=${TOP_CID}, since $START_UTC): cursor_reset=$(grep -c 'transcript cursor reset' <<<"$RH_LCM_LINES" || true) resync=$(grep -c 'transcript resync' <<<"$RH_LCM_LINES" || true)"
  grep -E 'transcript (cursor|resync)|generation_mismatch' <<<"$RH_LCM_LINES" | redact_stream | tail -10 || true
fi

python3 - "$RH_ROOT" <<'PY'
import json, pathlib, sqlite3
r = pathlib.Path(__import__("sys").argv[1])
b0 = json.loads((r / "lcm-before.json").read_text())
b3 = json.loads((r / "lcm-after_recall.json").read_text())
adb = sqlite3.connect(f"file:{r}/agents/main/agent/openclaw-agent.sqlite?mode=ro", uri=True)
uv = adb.execute("pragma user_version").fetchone()[0]
adb.close()
print(f"  So sánh LCM (before -> after 4 turns): msgs {b0['msgs']} -> {b3['msgs']} (+{b3['msgs']-b0['msgs']}), top_msgs +{b3['top_msgs']-b0['top_msgs']}, dup_entry_id={b3['dup_entry_id']}, gaps={b0['gaps']}->{b3['gaps']}, agent_db_user_version={uv}")
assert b3["quick_check"] == "ok", "lcm quick_check != ok"
assert b3["dup_entry_id"] == 0, f"dup_entry_id={b3['dup_entry_id']} != 0"
assert 4 <= (b3["top_msgs"] - b0["top_msgs"]) <= 20, f"top_msgs tăng bất thường: +{b3['top_msgs'] - b0['top_msgs']}"
assert uv == 24, f"agent DB user_version bị đổi ({uv} != 24)"
print("  GATE_934_MULTI_TURN_AND_SCHEMA_PASS")
PY

echo "== [7] Thử Rollback 2026.9.34 -> 2026.9.33 trên bản sao =="
stop_rh_gateway
python3 - "$RH_ROOT/state/openclaw.sqlite" <<'PY'
import sqlite3, sys
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

oc_rh "$RT_933" plugins update "@openclaw/codex@2026.9.33" > "$RH_ROOT/codex-933-rb.log" 2>&1
relink_peers "$RT_933"

(
  for v in $(compgen -v OPENCLAW_ 2>/dev/null || true); do unset "$v"; done
  unset TELEGRAM_BOT_TOKEN
  set -a
  . "$RH_ROOT/rh.env"
  set +a
  export PATH="${NODE_DIR}:/usr/bin:/bin"
  HOME="$RH_HOME" \
  OPENCLAW_STATE_DIR="$RH_ROOT" \
  OPENCLAW_CONFIG_PATH="$RH_ROOT/openclaw.json" \
  OPENCLAW_GATEWAY_PORT="$RH_PORT" \
  OPENCLAW_GATEWAY_TOKEN="$RH_TOKEN" \
  OPENCLAW_SERVICE_VERSION="2026.9.33" \
    exec "$NODE_BIN" --import "$LOADER_HOOK" "$RT_933/dist/index.js" gateway --port "$RH_PORT" > "$RH_ROOT/gateway-933-rb.log" 2>&1
) &
GW_PID=$!

READY_RB=0
for _ in $(seq 1 60); do
  kill -0 "$GW_PID" 2>/dev/null || { echo "ABORT: gateway rollback 9.33 thoát sớm"; tail -20 "$RH_ROOT/gateway-933-rb.log" | redact_stream || true; exit 1; }
  if [ "$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$RH_PORT/readyz" || true)" = "200" ]; then
    READY_RB=1
    echo "  BOOT_ROLLBACK_933_OK (pid=$GW_PID, readyz=200)"
    break
  fi
  sleep 2
done
[ "$READY_RB" = 1 ] || { echo "ABORT: gateway rollback 9.33 không ready"; exit 1; }

oc_rh "$RT_933" agent --session-key "$TOP_SK" \
  --message "Kiểm thử rollback 9.34 về 9.33. Không gọi tool, không gửi tin ra ngoài. Chỉ trả lời đúng một từ: RH_RB933_OK" \
  --timeout 180 --json > "$RH_ROOT/turn-rb933.json" 2> "$RH_ROOT/turn-rb933.err"

python3 - "$RH_ROOT/turn-rb933.json" "$RH_ROOT/lcm.db" <<'PY'
import json, sqlite3, sys
s = open(sys.argv[1]).read()
d = None
for i, ch in enumerate(s):
    if ch == "{":
        try:
            d, _ = json.JSONDecoder().raw_decode(s[i:])
            break
        except Exception:
            pass
assert d and d.get("status") == "ok", "Rollback 9.33 status != ok"
texts = [x.get("text", "") for x in d.get("result", {}).get("payloads", []) if isinstance(x, dict)]
assert any("RH_RB933_OK" in t for t in texts), "Thiếu RH_RB933_OK"
ldb = sqlite3.connect("file:" + sys.argv[2] + "?mode=ro", uri=True)
assert ldb.execute("pragma quick_check").fetchone()[0] == "ok"
ldb.close()
print("  GATE_ROLLBACK_934_TO_933_PASS")
PY

stop_rh_gateway

echo "== [8] Xác minh live hungreo & suckhoe nguyên vẹn 100% =="
[ "$(systemctl --user show openclaw-gateway-hungreo.service -p MainPID --value)" = "$LIVE_PID_H0" ] || { echo "FAIL: live hungreo PID đổi!"; exit 1; }
[ "$(systemctl --user show openclaw-gateway-suckhoe.service -p MainPID --value)" = "$LIVE_PID_S0" ] || { echo "FAIL: live suckhoe PID đổi!"; exit 1; }
[ "$(sha256sum "$LIVE_D/openclaw.json" | cut -c1-16)" = "$LIVE_CFG_H0" ] || { echo "FAIL: live hungreo config đổi!"; exit 1; }
echo "  Live hungreo PID=$LIVE_PID_H0, suckhoe PID=$LIVE_PID_S0, config nguyên vẹn 100%"
echo "OK 30_STAGE_AND_REHEARSAL_934_PASS"
