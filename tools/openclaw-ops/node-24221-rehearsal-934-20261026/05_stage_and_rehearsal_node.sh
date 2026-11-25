#!/usr/bin/env bash
# 05_stage_and_rehearsal_node.sh — Stage Node.js v24.22.1 tại /home/hung/openclaw-node-24.22.1/node
# (giữ nguyên /home/hung/openclaw-upgrade-20261003/node v24.21.0) + Red/Green check + Rehearsal boot cô lập trên bản sao suckhoe (:18798).
set -Eeuo pipefail
umask 077
export TZ=Asia/Ho_Chi_Minh
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

NODE_VER="24.22.1"
NODE_TAR="node-v${NODE_VER}-linux-x64.tar.xz"
NODE_URL="https://nodejs.org/dist/v${NODE_VER}/${NODE_TAR}"
NODE_SHA256="6c172a9ab6718f7b801fb5a7bd486af2ee5e32758086a04b84fcce2aa77095e6"

STAGE_ROOT="/home/hung/openclaw-node-${NODE_VER}"
NEW_NODE="${STAGE_ROOT}/node/bin/node"
NEW_NPM="${STAGE_ROOT}/node/bin/npm"
OLD_NODE="/home/hung/openclaw-upgrade-20261003/node/bin/node"
LOADER_HOOK="/home/hung/openclaw-upgrade-20261003/live-gates/patch-binding-loader-hook.mjs"
RT_933="/home/hung/openclaw-upgrade-20261018-933/runtime/node_modules/openclaw"

LIVE_D="/home/hung/.openclaw-suckhoe"
RH_ROOT="/tmp/rh-node24221-suckhoe"
RH_HOME="/tmp/rh-node24221-suckhoe-home"
RH_PORT=18798
RH_TOKEN="rh-isolated-node24221-token"
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

echo "== [0] Kiểm tra điều kiện tiên quyết & Red-Loop trên Node cũ ($(date '+%F %T')) =="
[ "$(hostname)" = "srv1367812" ] || { echo "ABORT: sai host"; exit 1; }
[ ! -e "$RH_ROOT" ] && [ ! -e "$RH_HOME" ] || { echo "ABORT: $RH_ROOT đã tồn tại"; exit 1; }
AVAIL_MB=$(free -m | awk '/^Mem:/{print $7}')
FREE_GB=$(df -BG --output=avail /home/hung | tail -1 | tr -dc 0-9)
echo "  RAM available=${AVAIL_MB} MiB, disk free=${FREE_GB} GiB"
[ "$AVAIL_MB" -ge 1500 ] || { echo "ABORT: RAM available ${AVAIL_MB} MiB < 1500 MiB"; exit 1; }
[ "$FREE_GB" -ge 5 ] || { echo "ABORT: disk free ${FREE_GB}G < 5G"; exit 1; }
if ss -ltn "sport = :$RH_PORT" | grep -q LISTEN; then
  echo "ABORT: cổng $RH_PORT đang bận"; exit 1
fi

echo "  -- Kiểm tra Red-Loop: Node hiện tại ($($OLD_NODE -v)) trước khi nâng:"
if "$OLD_NODE" -e '
const [maj, min, pat] = process.versions.node.split(".").map(Number);
const okNode = maj === 24 && (min > 22 || (min === 22 && pat >= 1));
const [sMaj, sMin, sPat] = process.versions.openssl.split(/[^0-9]+/).slice(0, 3).map(Number);
const okSsl = sMaj > 3 || (sMaj === 3 && (sMin > 5 || (sMin === 5 && sPat >= 9)));
console.log("  [OLD_NODE]", { node: process.versions.node, openssl: process.versions.openssl, okNode, okSsl });
process.exit(okNode && okSsl ? 0 : 1);
'; then
  echo "  WARN: OLD_NODE đã >= 24.22.1?"
else
  echo "  RED_LOOP_CONFIRMED: OLD_NODE (v24.21.0) FAIL cổng bảo mật Node >=24.22.1 & OpenSSL >=3.5.9 (CVE-2026-111497)"
fi

echo "== [1] Stage Node.js v${NODE_VER} vào ${STAGE_ROOT}/node =="
mkdir -p -m 755 "$STAGE_ROOT" "$STAGE_ROOT/ops"
if [ -x "$NEW_NODE" ] && [ "$("$NEW_NODE" -v 2>/dev/null || true)" = "v${NODE_VER}" ]; then
  echo "  Node v${NODE_VER} đã được stage sẵn tại $NEW_NODE"
else
  TMP_TAR="${STAGE_ROOT}/${NODE_TAR}.tmp.$$"
  curl -fsSL "$NODE_URL" -o "$TMP_TAR"
  ACTUAL_SHA=$(sha256sum "$TMP_TAR" | awk '{print $1}')
  echo "  tarball sha256=$ACTUAL_SHA"
  [ "$ACTUAL_SHA" = "$NODE_SHA256" ] || { rm -f "$TMP_TAR"; echo "ABORT: SHA256 mismatch ($ACTUAL_SHA != $NODE_SHA256)"; exit 1; }
  rm -rf "${STAGE_ROOT}/node.tmp"
  mkdir -p -m 755 "${STAGE_ROOT}/node.tmp"
  tar -xJf "$TMP_TAR" -C "${STAGE_ROOT}/node.tmp" --strip-components=1
  rm -rf "${STAGE_ROOT}/node"
  mv "${STAGE_ROOT}/node.tmp" "${STAGE_ROOT}/node"
  rm -f "$TMP_TAR"
fi

echo "  -- Kiểm tra Green-Loop trên NEW_NODE ($NEW_NODE):"
"$NEW_NODE" -e '
const zlib = require("node:zlib");
const [maj, min, pat] = process.versions.node.split(".").map(Number);
const okNode = maj === 24 && (min > 22 || (min === 22 && pat >= 1));
const [sMaj, sMin, sPat] = process.versions.openssl.split(/[^0-9]+/).slice(0, 3).map(Number);
const okSsl = sMaj > 3 || (sMaj === 3 && (sMin > 5 || (sMin === 5 && sPat >= 9)));
const sample = Buffer.from("OpenClaw Node 24.22.1 Brotli check");
const roundtrip = zlib.brotliDecompressSync(zlib.brotliCompressSync(sample)).toString("utf8");
console.log("  [NEW_NODE]", { node: process.versions.node, openssl: process.versions.openssl, okNode, okSsl, brotliOk: roundtrip === sample.toString("utf8") });
if (!okNode || !okSsl || roundtrip !== sample.toString("utf8")) process.exit(1);
'
echo "  npm version trên NEW_NODE: $("$NEW_NODE" "$NEW_NPM" -v)"
echo "  GREEN_LOOP_NODE_BINARY_OK"

echo "== [2] Chạy Live-Gates với Node v${NODE_VER} trên runtime 2026.9.33 =="
"$NEW_NODE" --test /home/hung/openclaw-upgrade-20261003/live-gates/patch-openclaw-plugin-binding-decline-fallback.test.mjs >/dev/null
"$NEW_NODE" /home/hung/openclaw-upgrade-20261003/live-gates/verify-command-registry-98.mjs "$RT_933/dist"
echo "  LIVE_GATES_ON_NODE_24221_OK"

echo "== [3] Rehearsal cô lập: Boot gateway 2026.9.33 + LCM 1.2.0 bằng Node v${NODE_VER} trên bản sao suckhoe (:$RH_PORT) =="
LIVE_PID0=$(systemctl --user show openclaw-gateway-suckhoe.service -p MainPID --value)
LIVE_CFG_SHA0=$(sha256sum "$LIVE_D/openclaw.json" | cut -c1-16)

mkdir -p -m 700 "$RH_ROOT/state" "$RH_ROOT/agents/main/agent" "$RH_ROOT/workspace" "$RH_HOME"
cp -a "$LIVE_D/npm" "$RH_ROOT/npm"
cp -p "$LIVE_D/openclaw.json" "$RH_ROOT/openclaw.json"
[ ! -d "$LIVE_D/credentials" ] || cp -a "$LIVE_D/credentials" "$RH_ROOT/credentials"
for f in "$LIVE_D/agents/main/agent/"*.json; do
  [ ! -f "$f" ] || cp -p "$f" "$RH_ROOT/agents/main/agent/"
done

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
    cfg["plugins"]["allow"] = [x for x in cfg["plugins"]["allow"] if x not in ("telegram", "suckhoe-kb-weekly", "suckhoe-technical-handoff")]
entries = cfg["plugins"].setdefault("entries", {})
for k in ("telegram", "telegram-reply-footer", "suckhoe-kb-weekly", "suckhoe-technical-handoff"):
    if k in entries and isinstance(entries[k], dict):
        entries[k]["enabled"] = False
cfg_path.write_text(json.dumps(cfg, indent=2))

sdb = sqlite3.connect(str(dst / "state/openclaw.sqlite"))
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
print("  Clone & cô lập bản sao suckhoe hoàn tất")
PY

grep -vE '^(TELEGRAM_BOT_TOKEN|OPENCLAW_[A-Z0-9_]*)=' "$LIVE_D/gateway.systemd.env" > "$RH_ROOT/rh.env" || true
chmod 600 "$RH_ROOT/rh.env"

T_BOOT0=$(date +%s)
(
  for v in $(compgen -v OPENCLAW_ 2>/dev/null || true); do unset "$v"; done
  unset TELEGRAM_BOT_TOKEN
  set -a
  . "$RH_ROOT/rh.env"
  set +a
  export PATH="${STAGE_ROOT}/node/bin:/usr/bin:/bin"
  HOME="$RH_HOME" \
  OPENCLAW_STATE_DIR="$RH_ROOT" \
  OPENCLAW_CONFIG_PATH="$RH_ROOT/openclaw.json" \
  OPENCLAW_GATEWAY_PORT="$RH_PORT" \
  OPENCLAW_GATEWAY_TOKEN="$RH_TOKEN" \
  OPENCLAW_GATEWAY_REMOTE_TOKEN="$RH_TOKEN" \
  OPENCLAW_SERVICE_VERSION="2026.9.33" \
    exec "$NEW_NODE" --import "$LOADER_HOOK" "$RT_933/dist/index.js" gateway --port "$RH_PORT" > "$RH_ROOT/gateway.log" 2>&1
) &
GW_PID=$!

READY=0
for _ in $(seq 1 45); do
  kill -0 "$GW_PID" 2>/dev/null || { echo "ABORT: gateway rehearsal thoát sớm"; tail -20 "$RH_ROOT/gateway.log" | redact_stream || true; exit 1; }
  if [ "$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$RH_PORT/readyz" || true)" = "200" ]; then
    READY=1
    echo "  RH_NODE24221_BOOT_OK (pid=$GW_PID, exe=$(readlink -f "/proc/$GW_PID/exe"), readyz=200 sau $(( $(date +%s) - T_BOOT0 ))s)"
    break
  fi
  sleep 2
done
[ "$READY" = 1 ] || { echo "ABORT: gateway rehearsal không ready"; tail -25 "$RH_ROOT/gateway.log" | redact_stream || true; exit 1; }

[ "$(readlink -f "/proc/$GW_PID/exe")" = "$NEW_NODE" ] || { echo "ABORT: exe không phải $NEW_NODE"; exit 1; }
grep -q "PLUGIN_BINDING_DECLINE_FALLBACK_IN_MEMORY" "$RH_ROOT/gateway.log" || { echo "ABORT: thiếu loader hook marker"; exit 1; }
grep -q "lossless-claw" "$RH_ROOT/gateway.log" || { echo "ABORT: thiếu lossless-claw trong log"; exit 1; }
[ "$(grep -c 'readSessionTranscriptVisibleMessageDelta is required' "$RH_ROOT/gateway.log" || true)" = "0" ] || { echo "ABORT: capability_error > 0"; exit 1; }

stop_rh_gateway

[ "$(systemctl --user show openclaw-gateway-suckhoe.service -p MainPID --value)" = "$LIVE_PID0" ] || { echo "ABORT: live suckhoe PID bị đổi!"; exit 1; }
[ "$(sha256sum "$LIVE_D/openclaw.json" | cut -c1-16)" = "$LIVE_CFG_SHA0" ] || { echo "ABORT: live suckhoe config bị đổi!"; exit 1; }
echo "  Live suckhoe PID=$LIVE_PID0 & config nguyên vẹn 100%"
echo "OK 05_STAGE_AND_REHEARSAL_NODE_PASS"
