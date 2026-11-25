#!/bin/bash
# 00 — CLAUDE CHẠY (read-only). Kiểm trước khi nâng lossless-claw 1.1.0 → 1.1.1.
# Gồm dry-run THẬT của lệnh ghi (`plugins update … --dry-run`) cho cả 2 profile — lesson 11/10 + 12/10.
# Không stop/restart, không ghi config/state. In hash/đếm, không in secret.
set -u
export TZ=Asia/Ho_Chi_Minh
OC=/home/hung/bin/openclaw
SPEC=@martian-engineering/lossless-claw@1.1.1
echo "== now $(date '+%F %T')"
free -m | sed -n 2,3p
for p in ${PROFILES:-suckhoe hungreo}; do
  D=$HOME/.openclaw-$p
  U=openclaw-gateway-$p.service
  echo; echo "################ $p"
  echo "gateway=$(systemctl --user is-active $U) pid=$(systemctl --user show $U -p MainPID --value) since=$(systemctl --user show $U -p ActiveEnterTimestamp --value)"
  echo "-- config LCM"
  jq -c '{slot:.plugins.slots.contextEngine, lcm:.plugins.entries["lossless-claw"], allow:(.plugins.allow // null | if .==null then null else map(select(test("lossless"))) end)}' $D/openclaw.json
  echo "-- package"
  PKG=$(find $D/npm/projects -maxdepth 4 -path "*node_modules/@martian-engineering/lossless-claw/package.json" 2>/dev/null)
  for f in $PKG; do echo "  $(jq -r .version $f)  $f"; done
  echo "-- installed index (sqlite ro)"
  python3 - "$D/state/openclaw.sqlite" <<'PY'
import sqlite3,sys,json
c=sqlite3.connect("file:"+sys.argv[1]+"?mode=ro",uri=True)
tabs=["config_machine_state"]  # chỉ bản ghi install; bảng khác chứa nội dung chat cá nhân (repo PUBLIC)
hit=False
for t in tabs:
    cols=[r[1] for r in c.execute(f'pragma table_info("{t}")')]
    for col in cols:
        try:
            rows=c.execute(f'select "{col}" from "{t}" where cast("{col}" as text) like ?',('%lossless-claw%',)).fetchall()
        except Exception: continue
        for (v,) in rows[:3]:
            s=str(v)
            i=s.find("lossless-claw")
            print(f"  {t}.{col}: …{s[max(0,i-120):i+260]}…".replace("\n"," "))
            hit=True
if not hit: print("  (không thấy bản ghi lossless-claw trong state sqlite)")
PY
  echo "-- lcm.db"
  DB=$(jq -r '.plugins.entries["lossless-claw"].config.dbPath // empty' $D/openclaw.json); DB=${DB/#\~/$HOME}
  [ -z "$DB" ] && DB=$D/lcm.db
  ls -la --time-style=+%F_%T "$DB"* 2>/dev/null
  python3 - "$DB" <<'PY'
import sqlite3,sys
c=sqlite3.connect("file:"+sys.argv[1]+"?mode=ro",uri=True)
print("  quick_check:",c.execute("pragma quick_check").fetchone()[0])
for t in ("conversations","messages","summaries","pending_summary_nodes"):
    try: print(f"  {t}: {c.execute(f'select count(*) from {t}').fetchone()[0]}")
    except Exception as e: print(f"  {t}: {e}")
try: print("  pending_summary_nodes cols:",[r[1] for r in c.execute("pragma table_info(pending_summary_nodes)") if 'ordinal' in r[1]])
except Exception as e: print(e)
PY
  echo "-- cron/automations (để chọn giờ restart)"
  OPENCLAW_STATE_DIR=$D OPENCLAW_CONFIG_PATH=$D/openclaw.json timeout 90 $OC --profile $p cron list 2>&1 | grep -vE 'sk-|eyJ' | sed 's/[0-9]\{8,\}/<ID>/g' | head -30
  systemctl --user list-timers --all --no-pager 2>/dev/null | grep -iE "$p|devotional|medic|kb" | head
  echo "-- DRY-RUN plugins update $SPEC"
  ( set -a; . $D/gateway.systemd.env; set +a
    OPENCLAW_STATE_DIR=$D OPENCLAW_CONFIG_PATH=$D/openclaw.json timeout 300 $OC --profile $p plugins update "$SPEC" --dry-run < /dev/null 2>&1 ) | grep -vE 'sk-|eyJ' | tail -30
  echo "dry-run rc=${PIPESTATUS[0]}"
  echo "-- config hash sau dry-run (phải trùng trước): $(sha256sum $D/openclaw.json | cut -c1-8)"
  echo "-- package sau dry-run: $(for f in $PKG; do jq -r .version $f; done | tr '\n' ' ')"
done
echo; echo "== backup dir dự kiến"; ls -d $HOME/backups/lcm-111-* 2>/dev/null || echo "  (chưa có)"
df -h / | tail -1
echo "OK 00"
