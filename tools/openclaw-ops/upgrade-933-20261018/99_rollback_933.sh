#!/usr/bin/env bash
# Rollback suckhoe or hungreo from OpenClaw 2026.9.33 back to 2026.9.9.
set -Eeuo pipefail
umask 077
export PATH=/home/hung/openclaw-upgrade-20261003/node/bin:/usr/bin:/bin
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

P=${1:?Usage: 99_rollback_933.sh <suckhoe|hungreo> <backup_dir>}
B=${2:?Usage: 99_rollback_933.sh <suckhoe|hungreo> <backup_dir>}
case "$P" in
  suckhoe) PORT=18795 ;;
  hungreo) PORT=18789 ;;
  *) echo "ABORT: invalid profile $P"; exit 1 ;;
esac

D="/home/hung/.openclaw-$P"
U="openclaw-gateway-$P.service"
UNITS="/home/hung/.config/systemd/user"

[ -d "$B" ] || { echo "ABORT: missing backup dir $B"; exit 1; }
(cd "$B" && sha256sum -c --quiet SHA256SUMS)

echo "== [Rollback 1] Stop healthcheck & $U =="
systemctl --user stop openclaw-healthcheck.timer openclaw-healthcheck.service || true
systemctl --user stop "$U" || true
sleep 3
[ "$(systemctl --user show "$U" -p MainPID --value)" = "0" ] || { echo "ABORT: $U still running"; exit 1; }

echo "== [Rollback 2] Relink plugin peers back to 2026.9.9 runtime =="
node --input-type=module - "$D" "$B/peer-records-before.json" <<'MJS'
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const [stateDir, recordsPath] = process.argv.slice(2);
const root99 = "/home/hung/openclaw-upgrade-20261008-99/runtime/node_modules/openclaw";
const { r: acquireLock } = await import(pathToFileURL(path.join(root99, "dist/gateway-lock-Yq4iN6WB.mjs")));
const { s: repair } = await import(pathToFileURL(path.join(root99, "dist/plugin-peer-link-C0gLWhQK.mjs")));
const records = JSON.parse(fs.readFileSync(recordsPath, "utf8"));
const env = { ...process.env, OPENCLAW_STATE_DIR: stateDir, OPENCLAW_CONFIG_PATH: path.join(stateDir, "openclaw.json") };
const lock = await acquireLock({ env, role: "sqlite-maintenance", timeoutMs: 5000, pollIntervalMs: 50, allowInTests: true });
try {
  await lock.run(async () => {
    for (const [id, r] of Object.entries(records)) {
      if (!r.installPath || !r.installPath.includes("/npm/projects/")) continue;
      const project = path.resolve(r.installPath, "../../..");
      if (fs.existsSync(project)) {
        await repair({ npmRoot: project, beforePersistentApply: () => lock.assertCurrent(), logger: { info() {}, warn() {} } });
      }
    }
  });
} finally {
  await lock.release();
}
MJS

echo "== [Rollback 3] Restore plugins.installedIndex & config & systemd drop-ins =="
python3 - "$D" "$B" <<'PY'
from contextlib import closing
import pathlib, shutil, sqlite3, sys, time

d, b = map(pathlib.Path, sys.argv[1:3])
with closing(sqlite3.connect(d / "state/openclaw.sqlite")) as cur:
    with closing(sqlite3.connect(f"file:{b}/canonical-before.sqlite?mode=ro", uri=True)) as src:
        row = src.execute("select value_json from config_machine_state where state_key='plugins.installedIndex'").fetchone()
        assert row
    with closing(sqlite3.connect(b / f"failed-933-state-{int(time.time())}.sqlite")) as failed:
        cur.backup(failed)
    with cur:
        cur.execute("update config_machine_state set value_json=?, updated_at_ms=? where state_key='plugins.installedIndex'", (row[0], int(time.time() * 1000)))
shutil.copy2(b / "openclaw.json", d / "openclaw.json")
PY

cp -p "$B/zzzzz-upgrade-99.conf" "$UNITS/$U.d/zzzzz-upgrade-99.conf"
if [ "$P" = "hungreo" ] && [ -f "$B/zz-upgrade-99.conf" ]; then
  cp -p "$B/zz-upgrade-99.conf" "$UNITS/hungreo-finance-backup.service.d/zz-upgrade-99.conf"
fi
cp -p "$B/openclaw-cli" /home/hung/bin/openclaw.rb-tmp && mv /home/hung/bin/openclaw.rb-tmp /home/hung/bin/openclaw
cp -p "$B/openclaw-healthcheck.sh" /home/hung/bin/openclaw-healthcheck.sh.rb-tmp && mv /home/hung/bin/openclaw-healthcheck.sh.rb-tmp /home/hung/bin/openclaw-healthcheck.sh
systemctl --user daemon-reload
systemctl --user start "$U"

for i in $(seq 1 60); do
  if [ "$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/readyz" || true)" = "200" ]; then
    break
  fi
  sleep 2
done
systemctl --user start openclaw-healthcheck.timer || true
echo "ROLLBACK_99_READY_OK profile=$P"
