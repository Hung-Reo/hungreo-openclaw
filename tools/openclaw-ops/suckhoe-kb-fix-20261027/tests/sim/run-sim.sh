#!/usr/bin/env bash
# Cần Mac có Homebrew coreutils (gdate, ginstall, gchmod, gmktemp). Chạy: bash tests/sim/run-sim.sh
# Mô phỏng 00/10/99 của suckhoe-kb-fix-20261027 trên Mac với stub systemctl/curl/journalctl/hostname/flock.
set -u
PKG_SRC=$(cd "$(dirname "$0")/../.." && pwd)
LIVE_DIST=$PKG_SRC/tests/sim/live-dist
VPS_WL=$PKG_SRC/tests/sim/vps-whitelist.txt

setup() {
  SIM=$(mktemp -d /tmp/kbsim.XXXXXX); H=$SIM/home/hung
  mkdir -p $H/ops $H/backups $H/.openclaw-suckhoe/extensions/suckhoe-kb-weekly $H/openclaw-shared/kb/policies \
           $H/openclaw-shared/kb/medical/review-state $H/openclaw-node-24.22.1/node/bin $SIM/stub $SIM/state
  cp -a "$LIVE_DIST" $H/.openclaw-suckhoe/extensions/suckhoe-kb-weekly/dist
  cp "$VPS_WL" $H/openclaw-shared/kb/policies/medical-consumer-health-whitelist.txt
  echo '{}' > $H/openclaw-shared/kb/medical/review-state/drive-files.json
  cat > $H/.openclaw-suckhoe/openclaw.json <<EOF
{"plugins":{"entries":{"suckhoe-kb-weekly":{"config":{"whitelistPath":"$H/openclaw-shared/kb/policies/medical-consumer-health-whitelist.txt","kbRoot":"$H/openclaw-shared/kb"}}}}}
EOF
  ln -s "$(command -v node)" $H/openclaw-node-24.22.1/node/bin/node
  cp -a "$PKG_SRC" $H/ops/suckhoe-kb-fix-20261027
  for f in $H/ops/suckhoe-kb-fix-20261027/*.sh; do LC_ALL=C perl -pi -e "s#/home/hung#$H#g" "$f"; done
  (cd $H/ops/suckhoe-kb-fix-20261027 && { find files base tests v2 -type f -not -path "tests/sim/*" | sort; ls *.sh; } | xargs sha256sum > SHA256SUMS)
  # stubs
  for c in date:gdate install:ginstall chmod:gchmod mktemp:gmktemp; do ln -s "$(command -v ${c##*:})" $SIM/stub/${c%%:*}; done
  printf '#!/bin/sh\necho srv1367812\n' > $SIM/stub/hostname
  printf '#!/bin/sh\nexit 0\n' > $SIM/stub/flock
  printf '#!/bin/sh\nexit 0\n' > $SIM/stub/sleep
  cat > $SIM/stub/systemctl <<EOF
#!/bin/sh
echo "\$*" >> $SIM/state/systemctl.log
case "\$*" in *is-active*) echo active;; *MainPID*) echo 4242;; *NRestarts*) echo 0;; *ActiveEnterTimestamp*) echo "Tue 2026-10-27 10:00:00 +07";; esac
exit 0
EOF
  cat > $SIM/stub/curl <<EOF
#!/bin/sh
cat $SIM/state/readyz 2>/dev/null || printf 200
EOF
  cat > $SIM/stub/journalctl <<EOF
#!/bin/sh
cat $SIM/state/journal 2>/dev/null || echo "[gateway] http server listening (9 plugins: brave, codex, suckhoe-kb-weekly)"
EOF
  chmod +x $SIM/stub/*
  export PATH=$SIM/stub:$PATH
  P=$H/.openclaw-suckhoe/extensions/suckhoe-kb-weekly; W=$H/openclaw-shared/kb/policies/medical-consumer-health-whitelist.txt
  BASE_SHA=$(cd $P && find dist -type f | sort | xargs sha256sum | sha256sum | cut -c1-12); WL_SHA=$(sha256sum < $W | cut -c1-12)
}
tree_sha() { (cd $P && find dist -type f | sort | xargs sha256sum | sha256sum | cut -c1-12); }
res() { printf '%-55s %s\n' "$1" "$2"; }

echo "### A: 00 PASS + 10 happy path (giờ cho phép 10:00 thứ Ba)"
setup
out=$(bash $H/ops/suckhoe-kb-fix-20261027/10_apply.sh 2>&1); rc=$?
echo "$out" | grep -E "OK 00|OK 10|ABORT|LỖI|PASS" | sed 's/^/   /'
res "A rc=0" "$([ $rc = 0 ] && echo PASS || echo FAIL rc=$rc)"
res "A dist đã thay (khác base)" "$([ "$(tree_sha)" != "$BASE_SHA" ] && echo PASS || echo FAIL)"
res "A whitelist có dalieu.vn, giữ medlineplus" "$(grep -qxF dalieu.vn $W && grep -qxF medlineplus.gov $W && echo PASS || echo FAIL)"
res "A timer start lại" "$(grep -q 'start openclaw-healthcheck.timer' $SIM/state/systemctl.log && echo PASS || echo FAIL)"
B=$(ls -d $H/backups/suckhoe-kb-fix-* | head -1)
echo "### C: 99 thủ công sau A"
bash $H/ops/suckhoe-kb-fix-20261027/99_rollback.sh "$B" 2>&1 | grep -E "OK 99|!!" | sed 's/^/   /'
res "C dist về base" "$([ "$(tree_sha)" = "$BASE_SHA" ] && echo PASS || echo FAIL)"
res "C whitelist về cũ" "$([ "$(sha256sum < $W | cut -c1-12)" = "$WL_SHA" ] && echo PASS || echo FAIL)"
rm -rf $SIM

echo "### B: readyz không lên sau restart → trap → rollback tự động"
setup; printf 000 > $SIM/state/readyz
out=$(bash $H/ops/suckhoe-kb-fix-20261027/10_apply.sh 2>&1); rc=$?
echo "$out" | grep -E "LỖI|OK 99|readyz|ROLLBACK" | sed 's/^/   /'
res "B rc≠0" "$([ $rc != 0 ] && echo PASS || echo FAIL)"
res "B dist về base" "$([ "$(tree_sha)" = "$BASE_SHA" ] && echo PASS || echo FAIL)"
res "B timer được bật lại" "$(grep -q 'start openclaw-healthcheck.timer' $SIM/state/systemctl.log && echo PASS || echo FAIL)"
res "B whitelist về cũ" "$([ "$(sha256sum < $W | cut -c1-12)" = "$WL_SHA" ] && echo PASS || echo FAIL)"
rm -rf $SIM

echo "### D: plugin không có trong log sau restart → rollback"
setup; echo "[gateway] http server listening (8 plugins: brave, codex)" > $SIM/state/journal
bash $H/ops/suckhoe-kb-fix-20261027/10_apply.sh >/dev/null 2>&1; rc=$?
res "D rc≠0 + dist về base" "$([ $rc != 0 ] && [ "$(tree_sha)" = "$BASE_SHA" ] && echo PASS || echo FAIL)"
rm -rf $SIM

echo "### E: plugin live bị sửa trước → 00 ABORT, không ghi gì"
setup; echo "// tamper" >> $P/dist/src/poller.js; T0=$(tree_sha)
out=$(bash $H/ops/suckhoe-kb-fix-20261027/10_apply.sh 2>&1); rc=$?
res "E rc≠0 + ABORT + không backup/không ghi" "$([ $rc != 0 ] && echo "$out" | grep -q 'ABORT: dist/src/poller.js' && [ "$(tree_sha)" = "$T0" ] && [ -z "$(ls $H/backups)" ] && echo PASS || echo "FAIL rc=$rc")"
rm -rf $SIM

echo "### F: gói bị đổi sau khi soạn → ABORT"
setup; echo x >> $H/ops/suckhoe-kb-fix-20261027/files/dist/src/commands.js
out=$(bash $H/ops/suckhoe-kb-fix-20261027/00_check.sh 2>&1); rc=$?
res "F rc≠0 + ABORT gói" "$([ $rc != 0 ] && echo "$out" | grep -q 'ABORT: gói' && echo PASS || echo FAIL)"
rm -rf $SIM
