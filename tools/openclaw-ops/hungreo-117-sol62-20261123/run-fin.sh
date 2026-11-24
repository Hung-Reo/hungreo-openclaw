#!/usr/bin/env bash
set -Eeuo pipefail; umask 077
P=/home/hung/.openclaw-hungreo; U=/home/hung/openclaw-upgrade-hungreo-20261123-117
R=/home/hung/claude-finance-117; C=$R/profile; O=$R/out
[[ ! -e "$C" ]]; mkdir -p -m 700 "$O" "$R/chome" "$R/ctmp"
E=$P/extensions/hungreo-finance; J=$R/finance-js
cp -a "$E" "$J"; rm -rf --one-file-system -- "$J/node_modules"
"$U/runtime/node_modules/.bin/esbuild" "$E/index.ts" --bundle --platform=node --format=esm --target=node24 \
  --external:openclaw --external:'openclaw/*' --outfile="$J/dist/index.js" --log-level=warning
python3 -I - "$J/package.json" <<'PY'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["openclaw"]["extensions"]=["./dist/index.js"]; json.dump(d,open(p,"w"),indent=2)
PY
echo "bundle $(du -sh "$J/dist/index.js" | cut -f1) files=$(find "$J" -type f | wc -l)"
nice -n 10 ionice -c3 rsync -aHAX --numeric-ids --exclude=/tmp/ --exclude=/cache/ --exclude='*-shm' --exclude='*-wal' "$P/" "$C/" >"$O/copy.log" 2>&1 || [[ $? == 24 ]]
nice -n 10 python3 -I /home/hung/claude-dryrun-117-20261124/ops/snapdb.py "$P" "$C" > "$O/snapdb.log"
! grep -v 'quick_check=ok' "$O/snapdb.log"
python3 -I -c "import sqlite3;db=sqlite3.connect('$C/state/openclaw.sqlite');db.execute('delete from state_leases');db.execute('delete from agent_database_leases');db.commit()"
docker run --rm --network none --user 1001:1001 --memory 3g --cpus 1.5 --pids-limit 768 \
  -v $R/chome:/home/hung -v $R/ctmp:/tmp -v $C:/home/hung/.openclaw-hungreo -v $J:/home/hung/finance-js:ro \
  -v $U/runtime:$U/runtime:ro -v $U/ops:$U/ops:ro -v /home/hung/openclaw-node-24.22.1:/home/hung/openclaw-node-24.22.1:ro \
  -v $R/ops:/home/hung/ops:ro -v $O:/home/hung/out -e HOME=/home/hung -e TZ=Asia/Ho_Chi_Minh --name claude-fin-117 \
  node:24.21.0-bookworm-slim bash /home/hung/ops/inner-fin.sh
echo FIN_TEST_DONE
