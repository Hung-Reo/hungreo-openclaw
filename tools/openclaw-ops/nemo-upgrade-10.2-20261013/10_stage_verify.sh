#!/bin/bash
# 10 — Hoàn tất + kiểm runtime OpenClaw 2026.10.2 đã npm install vào ~/sandbox-nemo/runtime-10.2. KHÔNG đụng container đang chạy.
# Theo lesson 12/10: kiểm integrity với npm, chạy tay postinstall (npm 11.19 chặn install-scripts), kiểm lifecycle marker.
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 10_stage_verify.sh
set -u
S=/home/hung/sandbox-nemo; VER=2026.10.2; R=$S/runtime-10.2; IMG=node:24.21.0-bookworm-slim
log(){ echo "[$(date +%T)] $*"; }
[ -f "$R/node_modules/openclaw/package.json" ] || { log "STOP — chưa có $R/node_modules/openclaw"; exit 2; }
want=$(npm view openclaw@$VER dist.integrity --userconfig "$(mktemp)" 2>/dev/null)
got=$(python3 -c "import json;print(json.load(open('$R/package-lock.json'))['packages']['node_modules/openclaw']['integrity'])" 2>/dev/null)
ver=$(python3 -c "import json;print(json.load(open('$R/node_modules/openclaw/package.json'))['version'])")
log "version=$ver integrity_khớp=$([ -n "$want" ] && [ "$got" = "$want" ] && echo YES || echo NO)"
[ "$ver" = "$VER" ] && [ -n "$want" ] && [ "$got" = "$want" ] || { log "STOP — version/integrity không khớp"; exit 1; }
if grep -q "install-scripts" $S/stage-10.2.log 2>/dev/null || [ -e $R/node_modules/openclaw/.openclaw-lifecycle-pending ]; then
  log "install-scripts bị chặn → chạy tay postinstall-bundled-plugins.mjs"
  docker run --rm --user 1001:1001 --memory 800m -e HOME=/tmp -v $R:/sandbox/runtime $IMG \
    sh -c "cd /sandbox/runtime/node_modules/openclaw && node scripts/postinstall-bundled-plugins.mjs" > $S/stage-10.2-postinstall.log 2>&1
  log "postinstall rc=$? ($(tail -1 $S/stage-10.2-postinstall.log))"
fi
[ -e $R/node_modules/openclaw/.openclaw-lifecycle-pending ] && { log "STOP — lifecycle marker còn"; exit 1; }
oc(){ docker run --rm --user 1001:1001 --memory 800m -v $R:/sandbox/runtime:ro $IMG node /sandbox/runtime/node_modules/openclaw/dist/entry.js "$@" < /dev/null 2>&1; }
log "--version: $(oc --version | head -1)"
oc plugins update --help | head -30 > $S/stage-10.2-help-plugins-update.txt
log "plugins update flags: $(grep -oE -- '--[a-z-]+' $S/stage-10.2-help-plugins-update.txt | sort -u | tr '\n' ' ')"
log "du runtime: $(du -sh $R | cut -f1)"
log "STAGE_VERIFY_OK"
