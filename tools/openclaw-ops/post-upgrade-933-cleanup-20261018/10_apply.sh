#!/bin/bash
# 10_apply.sh — Chạy TỪNG BOT MỘT (suckhoe trước, verify xong mới tới hungreo):
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s suckhoe' < 10_apply.sh
# Nâng các plugin official còn ở 2026.9.8 lên 2026.9.33 + làm sạch 3 cảnh báo systemd (KillMode=mixed, PATH minimal, .service.bak).
set -euo pipefail
umask 077
export TZ=Asia/Ho_Chi_Minh

P=${1:-}
case "$P" in
  suckhoe)
    PORT=18795
    PLUGINS=("brave:@openclaw/brave-plugin@2026.9.33" "deepseek:@openclaw/deepseek-provider@2026.9.33")
    ;;
  hungreo)
    PORT=18789
    PLUGINS=("brave:@openclaw/brave-plugin@2026.9.33" "deepseek:@openclaw/deepseek-provider@2026.9.33" "parallel:@openclaw/parallel-plugin@2026.9.33" "typesafe:@openclaw/typesafe@2026.9.33")
    ;;
  *)
    echo "ABORT: dùng 'bash -s suckhoe' hoặc 'bash -s hungreo'"
    exit 1
    ;;
esac

OC=/home/hung/bin/openclaw
RT=/home/hung/openclaw-upgrade-20261018-933/runtime
D=$HOME/.openclaw-$P
U=openclaw-gateway-$P.service
UNIT_FILE=$HOME/.config/systemd/user/$U
UNIT_DIR=$HOME/.config/systemd/user/$U.d
B=$HOME/backups/post933-cleanup-$P-$(date +%Y%m%d-%H%M%S)
PHASE=precheck

on_err() {
  echo "FAILED ở dòng $1 (phase=$PHASE)"
  if [ "$PHASE" = precheck ]; then
    echo "Chưa đổi gì, gateway $P vẫn chạy bình thường."
  elif [ "$PHASE" = stop ] || [ "$PHASE" = backup ]; then
    echo "Chưa sửa plugin/systemd -> bật lại $P + healthcheck timer như cũ."
    systemctl --user start "$U" || true
    [ "${HC_WAS:-active}" = active ] && systemctl --user start openclaw-healthcheck.timer || true
    echo "  $P=$(systemctl --user is-active "$U" || true) timer=$(systemctl --user is-active openclaw-healthcheck.timer || true)"
  else
    echo "Gateway $P đang dừng hoặc chưa hoàn tất sau khi sửa. Chạy rollback ngay:"
    echo "  ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s $P $B' < 99_rollback.sh"
  fi
}
trap 'on_err $LINENO' ERR

oc() {
  (
    for v in $(compgen -v OPENCLAW_ 2>/dev/null || true); do unset "$v"; done
    unset TELEGRAM_BOT_TOKEN
    set -a
    [ -f "$D/gateway.systemd.env" ] && . "$D/gateway.systemd.env"
    set +a
    OPENCLAW_PROFILE="$P" OPENCLAW_STATE_DIR="$D" OPENCLAW_CONFIG_PATH="$D/openclaw.json" \
      OPENCLAW_GATEWAY_PORT="$PORT" OPENCLAW_SYSTEMD_UNIT="$U" \
      timeout 300 "$OC" --profile "$P" "$@" < /dev/null
  )
}

check_sqlite_ro() {
  python3 - "$D/state/openclaw.sqlite" "$D/lcm.db" <<'PY'
import sqlite3, sys
for db in sys.argv[1:]:
    con = sqlite3.connect("file:" + db + "?mode=ro", uri=True)
    try:
        qc = con.execute("pragma quick_check").fetchone()[0]
        if qc != "ok":
            print(f"ABORT: {db} quick_check={qc}")
            sys.exit(1)
    finally:
        con.close()
PY
}

echo "== [0] precheck + dry-run ($P, $(date '+%F %T'))"
[ "$(systemctl --user is-active "$U")" = active ] || { echo "ABORT: $U không active"; exit 1; }
FREE=$(df -BG --output=avail / | tail -1 | tr -dc 0-9)
[ "$FREE" -ge 3 ] || { echo "ABORT: disk trống ${FREE}G < 3G"; exit 1; }
[ ! -e "$B" ] || { echo "ABORT: $B đã tồn tại"; exit 1; }
check_sqlite_ro

for entry in "${PLUGINS[@]}"; do
  ID=${entry%%:*}
  SPEC=${entry#*:}
  DRY=$(oc plugins update "$SPEC" --dry-run 2>&1 | grep -vE 'sk-|eyJ' || true)
  echo "  dry-run $ID: $(grep -i 'would update' <<<"$DRY" | head -1 || true)"
  grep -q "2026.9.8 -> 2026.9.33" <<<"$DRY" || { echo "ABORT: dry-run $SPEC không ra 2026.9.8 -> 2026.9.33"; echo "$DRY" | tail -15; exit 1; }
done
CFG_HASH0=$(sha256sum "$D/openclaw.json" | cut -c1-8)
echo "  config=$CFG_HASH0 disk_free=${FREE}G"

PHASE=stop
echo "== [1] tắt healthcheck timer + stop $P"
HC_WAS=$(systemctl --user is-active openclaw-healthcheck.timer || true)
systemctl --user stop openclaw-healthcheck.timer openclaw-healthcheck.service || true
systemctl --user stop "$U"
sleep 5
[ "$(systemctl --user show "$U" -p MainPID --value)" = 0 ] || { echo "ABORT: $P chưa dừng (MainPID != 0)"; false; }
if ss -ltn "sport = :$PORT" | grep -q LISTEN; then echo "ABORT: cổng $PORT vẫn mở"; false; fi
echo "  $P stopped (healthcheck.timer trước đó: $HC_WAS)"

PHASE=backup
echo "== [2] backup -> $B"
check_sqlite_ro
mkdir -p "$B/state" "$B/systemd/service.d"
cp -p "$D/openclaw.json" "$B/"
for f in "$D/state/openclaw.sqlite" "$D/state/openclaw.sqlite-wal"; do
  [ ! -e "$f" ] || cp -p "$f" "$B/state/"
done
cp -p "$UNIT_FILE" "$B/systemd/$U"
if [ -e "${UNIT_FILE}.bak" ]; then
  cp -p "${UNIT_FILE}.bak" "$B/systemd/${U}.bak"
  chmod 600 "$B/systemd/${U}.bak"
fi
cp -a "$UNIT_DIR/." "$B/systemd/service.d/"
tar czf "$B/npm-projects-pre.tgz" -C "$D/npm" projects
echo "$HC_WAS" > "$B/healthcheck_timer_state"
(cd "$B" && find . -type f ! -name SHA256SUMS -exec sha256sum {} \; | sort -k2 > SHA256SUMS)
(cd "$B" && sha256sum -c --quiet SHA256SUMS) || { echo "ABORT: checksum backup sai"; false; }
du -sh "$B"

PHASE=update
echo "== [3] plugins update 2026.9.8 -> 2026.9.33 + relink peers + systemd cleanup"
for entry in "${PLUGINS[@]}"; do
  ID=${entry%%:*}
  SPEC=${entry#*:}
  echo "  -> updating $ID ($SPEC)..."
  UPD=$(oc plugins update "$SPEC" 2>&1) || { echo "$UPD" | grep -vE 'sk-|eyJ' | tail -15; echo "ABORT: plugins update $SPEC lỗi"; false; }
  grep -vE 'sk-|eyJ' <<<"$UPD" | tail -5 || true
done

# Relink peerDependency node_modules/openclaw cho mọi project trong npm/projects
for proj in "$D/npm/projects"/*; do
  [ -d "$proj/node_modules" ] || continue
  ln -sfn "$RT/node_modules/openclaw" "$proj/node_modules/openclaw"
done

# Verify installedIndex trong config_machine_state
python3 - "$D/state/openclaw.sqlite" "${PLUGINS[@]}" <<'PY'
import sqlite3, sys, json, os
db = sys.argv[1]
targets = {}
for item in sys.argv[2:]:
    k, spec = item.split(":", 1)
    targets[k] = spec

con = sqlite3.connect("file:" + db + "?mode=ro", uri=True)
found = {}
try:
    def walk(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if k in targets and isinstance(v, dict) and "spec" in v and "installPath" in v:
                    found[k] = v
                else:
                    walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)
    for (v,) in con.execute("select value_json from config_machine_state"):
        try:
            walk(json.loads(v))
        except Exception:
            pass
finally:
    con.close()

for k, expected_spec in targets.items():
    info = found.get(k)
    if not info:
        sys.exit(f"ABORT: không tìm thấy {k} trong config_machine_state")
    if info.get("spec") != expected_spec:
        sys.exit(f"ABORT: {k} spec={info.get('spec')} != {expected_spec}")
    pkg_json = os.path.join(info["installPath"], "package.json")
    ver = json.load(open(pkg_json))["version"]
    if ver != "2026.9.33":
        sys.exit(f"ABORT: {k} package.json version={ver} != 2026.9.33")
    print(f"  verified {k}: spec={info['spec']} pkg_ver={ver}")
PY

[ "$(systemctl --user show "$U" -p MainPID --value)" = 0 ] || { echo "ABORT: gateway tự chạy lại sau plugins update"; false; }

# Diff phẳng openclaw.json chặn đổi khoá cấm
python3 - "$D/openclaw.json" "$B/openclaw.json" <<'PY'
import json, sys
def flat(d, p=""):
    o = {}
    if isinstance(d, dict):
        for k, v in d.items():
            o.update(flat(v, p + "." + k))
    else:
        o[p] = d
    return o
a = flat(json.load(open(sys.argv[1])))
b = flat(json.load(open(sys.argv[2])))
ks = [k for k in sorted(set(a) | set(b)) if a.get(k) != b.get(k)]
sens = lambda k: any(x in k.lower() for x in ("token", "key", "secret", "password"))
print("  config changed keys:", len(ks))
for k in ks:
    print("   ", k, "| old=", "<R>" if sens(k) else b.get(k), "| new=", "<R>" if sens(k) else a.get(k))
bad = [k for k in ks if any(x in k for x in (".model", ".auth", "fallback", ".slots"))]
if bad:
    print("ABORT: đổi khoá cấm:", bad)
    sys.exit(1)
PY

# Systemd cleanup:
# 1. Gỡ file .service.bak ở thư mục systemd (đã cất an toàn mode 0600 trong $B/systemd/)
rm -f "${UNIT_FILE}.bak"

# 2. Cập nhật base unit + drop-ins: bỏ version managers khỏi PATH, đặt KillMode=mixed, chuẩn hoá quyền 0600
python3 - "$UNIT_FILE" "$UNIT_DIR" "$P" "$PORT" "$RT" <<'PY'
import os, sys, pathlib

unit_file = pathlib.Path(sys.argv[1])
unit_dir = pathlib.Path(sys.argv[2])
profile = sys.argv[3]
port = sys.argv[4]
rt = sys.argv[5]

vm_segments = {
    "/home/hung/.volta/bin",
    "/home/hung/.asdf/shims",
    "/home/hung/.nvm/current/bin",
    "/home/hung/.fnm/current/bin",
}

def clean_path_line(line: str) -> str:
    if not line.startswith("Environment=PATH="):
        return line
    prefix = "Environment=PATH="
    parts = [p for p in line[len(prefix):].strip().split(":") if p and p not in vm_segments]
    return prefix + ":".join(parts)

# Update base unit file: clean PATH and set KillMode=mixed
base_lines = unit_file.read_text().splitlines()
new_base = []
for line in base_lines:
    if line.strip().startswith("KillMode="):
        new_base.append("KillMode=mixed")
    else:
        new_base.append(clean_path_line(line))
unit_file.write_text("\n".join(new_base) + "\n")
unit_file.chmod(0o600)

# Clean PATH in zz-upgrade-98.conf if present
zz98 = unit_dir / "zz-upgrade-98.conf"
if zz98.exists():
    lines98 = [clean_path_line(l) for l in zz98.read_text().splitlines()]
    zz98.write_text("\n".join(lines98) + "\n")

# Write clean zzzzz-upgrade-99.conf with minimal PATH, KillMode=mixed, TimeoutStopSec=340
min_path = f"{rt}/bin:/home/hung/openclaw-upgrade-20261003/node/bin:{rt}/node_modules/.bin:/usr/bin:/home/hung/.local/bin:/home/hung/.npm-global/bin:/home/hung/bin:/home/hung/.bun/bin:/home/hung/.local/share/pnpm:/usr/local/bin:/bin"
dropin99 = unit_dir / "zzzzz-upgrade-99.conf"
dropin99.write_text(f"""# Managed 2026.9.33 runtime drop-in for {profile}. Retain all existing EnvironmentFile/OOM/other drop-ins.
[Unit]
Description=OpenClaw Gateway (profile: {profile}, v2026.9.33)

[Service]
KillMode=mixed
TimeoutStopSec=340
ExecStartPre=
ExecStartPre=/home/hung/openclaw-upgrade-20261003/node/bin/node --test /home/hung/openclaw-upgrade-20261003/live-gates/patch-openclaw-plugin-binding-decline-fallback.test.mjs
ExecStartPre=/home/hung/openclaw-upgrade-20261003/node/bin/node /home/hung/openclaw-upgrade-20261003/live-gates/verify-command-registry-98.mjs {rt}/node_modules/openclaw/dist
ExecStart=
ExecStart=/home/hung/openclaw-upgrade-20261003/node/bin/node --import /home/hung/openclaw-upgrade-20261003/live-gates/patch-binding-loader-hook.mjs {rt}/node_modules/openclaw/dist/index.js gateway --port {port}
Environment=OPENCLAW_SERVICE_VERSION=2026.9.33
Environment=PATH={min_path}
""")

unit_dir.chmod(0o700)
for child in unit_dir.iterdir():
    if child.is_file() and not child.is_symlink():
        try:
            child.chmod(0o600)
        except PermissionError:
            pass
PY

systemctl --user daemon-reload

PHASE=start
echo "== [4] start $P"
SINCE=$(date '+%F %T')
systemctl --user start "$U"
OK=""
for i in $(seq 1 48); do
  J=$(journalctl --user -u "$U" --since "$SINCE" --no-pager || true)
  if grep -q "\[gateway\] ready" <<<"$J"; then
    OK=1
    echo "  ready sau ~$((i*5))s"
    break
  fi
  [ "$(systemctl --user is-active "$U")" != failed ] || break
  sleep 5
done
[ -n "$OK" ] || { echo "ABORT: $P không ready sau 240s"; grep -iE 'error|fail' <<<"$J" | tail -15 || true; false; }

HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/readyz")
echo "  readyz: $HTTP_CODE"
[ "$HTTP_CODE" = "200" ] || { echo "ABORT: readyz=$HTTP_CODE != 200"; false; }

LOG=$(journalctl --user -u "$U" --since "$SINCE" --no-pager)
grep -q 'lossless-claw' <<<"$LOG" || { echo "ABORT: không thấy lossless-claw trong log khởi động"; false; }
check_sqlite_ro

GW_DEEP=$(oc gateway status --deep 2>&1 | grep -vE 'sk-|eyJ' || true)
if grep -qE "Plugin version drift:|Service config issue:" <<<"$GW_DEEP"; then
  echo "  WARNING: vẫn còn cảnh báo trong gateway status --deep:"
  grep -E "Plugin version drift:|Service config issue:" <<<"$GW_DEEP" || true
else
  echo "  gateway status --deep: 0 plugin drift, 0 service config issues"
fi

PHASE=done
[ "$HC_WAS" = active ] && systemctl --user start openclaw-healthcheck.timer
echo "  healthcheck.timer: $(systemctl --user is-active openclaw-healthcheck.timer || true)"
echo "  $P $(systemctl --user is-active "$U") pid=$(systemctl --user show "$U" -p MainPID --value)"
echo "BACKUP=$B"
echo "OK 10 $P"
