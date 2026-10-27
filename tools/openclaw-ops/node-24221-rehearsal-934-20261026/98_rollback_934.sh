#!/usr/bin/env bash
# 98_rollback_934.sh — Rollback suckhoe hoặc hungreo từ OpenClaw 2026.9.34 về 2026.9.33 (trên nền Node v24.22.1).
set -Eeuo pipefail
umask 077
export TZ=Asia/Ho_Chi_Minh
export PATH="/home/hung/openclaw-node-24.22.1/node/bin:/usr/bin:/bin"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

P=${1:?Usage: 98_rollback_934.sh <suckhoe|hungreo> [backup_dir]}
B=${2:-}
case "$P" in
  suckhoe) PORT=18795 ;;
  hungreo) PORT=18789 ;;
  *) echo "ABORT: invalid profile $P"; exit 1 ;;
esac

if [ -z "$B" ]; then
  B=$(ls -1dt /home/hung/backups/openclaw-${P}-pre934-* 2>/dev/null | head -1 || true)
fi
[ -n "$B" ] && [ -d "$B" ] || { echo "ABORT: không tìm thấy thư mục backup cho $P ($B)"; exit 1; }
[ -f "$B/SHA256SUMS" ] || { echo "ABORT: thiếu $B/SHA256SUMS"; exit 1; }
(cd "$B" && sha256sum -c --quiet SHA256SUMS) || { echo "ABORT: checksum backup $B sai"; exit 1; }
[ -f "$B/npm-projects-before.tgz" ] || { echo "ABORT: thiếu $B/npm-projects-before.tgz"; exit 1; }

D="/home/hung/.openclaw-$P"
U="openclaw-gateway-$P.service"
UNITS="/home/hung/.config/systemd/user"
OC_933="/home/hung/openclaw-upgrade-20261018-933/runtime/node_modules/openclaw"

echo "== [Rollback 9.34 -> 9.33] Stop healthcheck & $U (từ $B) =="
systemctl --user stop openclaw-healthcheck.timer openclaw-healthcheck.service || true
systemctl --user stop "$U" || true
for _ in $(seq 1 20); do
  if [ "$(systemctl --user show "$U" -p MainPID --value)" = "0" ]; then
    if ! ss -ltn "sport = :$PORT" | grep -q LISTEN; then
      break
    fi
  fi
  sleep 1
done
[ "$(systemctl --user show "$U" -p MainPID --value)" = "0" ] || { echo "ABORT: $U vẫn đang chạy"; exit 1; }
if ss -ltn "sport = :$PORT" | grep -q LISTEN; then
  echo "ABORT: cổng $PORT vẫn đang LISTEN"
  exit 1
fi

echo "== [Rollback 2] Khôi phục npm/projects, plugins.installedIndex, openclaw.json & Relink 2 tầng về 2026.9.33 =="
mv "$D/npm/projects" "$B/failed-934-npm-projects-$(date +%s)" 2>/dev/null || true
tar -xzf "$B/npm-projects-before.tgz" -C "$D/npm"

python3 - "$D" "$B" "$OC_933" <<'PY'
from contextlib import closing
import json, os, pathlib, shutil, sqlite3, sys, time

d, b = map(pathlib.Path, sys.argv[1:3])
target_rt = sys.argv[3]

with closing(sqlite3.connect(d / "state/openclaw.sqlite")) as cur:
    with closing(sqlite3.connect(f"file:{b}/canonical-before.sqlite?mode=ro", uri=True)) as src:
        row = src.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()
        assert row
    with closing(sqlite3.connect(b / f"failed-934-state-{int(time.time())}.sqlite")) as failed:
        cur.backup(failed)
    with cur:
        cur.execute("update config_machine_state set value_json=?, updated_at_ms=? where state_key='plugins.installedIndex'", (row[0], int(time.time() * 1000)))
shutil.copy2(b / "openclaw.json", d / "openclaw.json")

records = json.loads(row[0])["index"]["installRecords"]
def force_link(peer: pathlib.Path):
    assert str(peer).startswith(str(d) + "/npm/projects/"), f"Unsafe peer path: {peer}"
    peer.parent.mkdir(parents=True, exist_ok=True)
    if peer.is_symlink() or peer.is_file():
        peer.unlink()
    elif peer.is_dir():
        shutil.rmtree(peer)
    os.symlink(target_rt, str(peer))

for p in (d / "npm/projects").rglob("openclaw"):
    if p.is_symlink():
        force_link(p)

for pid, rec in records.items():
    ipath = rec.get("installPath") or ""
    if not ipath.startswith(str(d)) or "/npm/projects/" not in ipath:
        continue
    pkg_dir = pathlib.Path(ipath)
    assert (pkg_dir / "package.json").is_file(), f"Missing package.json in {pkg_dir}"
    nm = pkg_dir.parent
    if nm.name.startswith("@"):
        nm = nm.parent
    force_link(nm / "openclaw")
    force_link(pkg_dir / "node_modules/openclaw")
print("  Restored npm/projects, installedIndex & relinked 2-tier peers ->", target_rt)
PY

echo "== [Rollback 3] Khôi phục systemd drop-in & CLI =="
cp -p "$B/zzzzz-upgrade-99.conf" "$UNITS/$U.d/zzzzz-upgrade-99.conf.rb"
mv "$UNITS/$U.d/zzzzz-upgrade-99.conf.rb" "$UNITS/$U.d/zzzzz-upgrade-99.conf"
if [ "$P" = "hungreo" ] && [ -f "$B/zz-upgrade-99.conf" ]; then
  cp -p "$B/zz-upgrade-99.conf" "$UNITS/hungreo-finance-backup.service.d/zz-upgrade-99.conf.rb"
  mv "$UNITS/hungreo-finance-backup.service.d/zz-upgrade-99.conf.rb" "$UNITS/hungreo-finance-backup.service.d/zz-upgrade-99.conf"
fi
cp -p "$B/openclaw-cli" /home/hung/bin/openclaw.rb-tmp && mv /home/hung/bin/openclaw.rb-tmp /home/hung/bin/openclaw
cp -p "$B/openclaw-healthcheck.sh" /home/hung/bin/openclaw-healthcheck.sh.rb-tmp && mv /home/hung/bin/openclaw-healthcheck.sh.rb-tmp /home/hung/bin/openclaw-healthcheck.sh

systemctl --user daemon-reload
systemctl --user start "$U"

READY_OK=0
for _ in $(seq 1 60); do
  if [ "$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/readyz" || true)" = "200" ]; then
    READY_OK=1
    break
  fi
  sleep 2
done
[ "$READY_OK" = "1" ] || { echo "ABORT: rollback $U không ready"; exit 1; }

if [ -f "$B/healthcheck_timer_state" ] && [ "$(cat "$B/healthcheck_timer_state")" = "active" ]; then
  systemctl --user start openclaw-healthcheck.timer || true
fi
echo "ROLLBACK_934_TO_933_OK profile=$P backup=$B"
