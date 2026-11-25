#!/bin/bash
# 10 — Chuẩn bị runtime OpenClaw 2026.10.1 cho Nemo vào ~/sandbox-nemo/runtime-10.1. KHÔNG đụng container đang chạy.
# Cài trong container node tạm (giới hạn RAM 1500m) để không cài gì lên host. Tốn RAM/CPU ~2–4 phút.
# DRY_RUN=1 (mặc định) → chỉ kiểm điều kiện. APPLY=1 → cài thật.
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 10_stage.sh
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'APPLY=1 bash -s' < 10_stage.sh
set -u
S=/home/hung/sandbox-nemo; VER=2026.10.1; R=$S/runtime-10.1; IMG=node:24.21.0-bookworm-slim
APPLY=${APPLY:-0}
log(){ echo "[$(date +%T)] $*"; }
avail=$(free -m | awk '/^Mem:/{print $7}'); disk=$(df -BG --output=avail / | tail -1 | tr -dc 0-9)
log "RAM available=${avail}MB (cần ≥1500) | disk trống=${disk}G (cần ≥5) | runtime đích: $R"
[ "$avail" -ge 1500 ] || { log "STOP — RAM thấp, chờ lúc vắng hơn."; exit 2; }
[ "$disk" -ge 5 ] || { log "STOP — thiếu dung lượng."; exit 2; }
[ -e "$R" ] && { log "STOP — $R đã tồn tại (đã stage?). Kiểm rồi xoá tay nếu muốn stage lại."; exit 2; }
want=$(npm view openclaw@$VER dist.integrity 2>/dev/null); log "npm openclaw@$VER integrity: ${want:-<không đọc được>}"
[ -n "$want" ] || { log "STOP — không đọc được metadata npm."; exit 2; }
log "Nemo đang chạy: $(docker exec nemo-sandbox node -e 'console.log(require("/sandbox/runtime/node_modules/openclaw/package.json").version)' 2>/dev/null)"
if [ "$APPLY" != 1 ]; then log "DRY-RUN — sẽ: npm install openclaw@$VER vào $R trong container $IMG (--memory 1500m)."; exit 0; fi

mkdir -p "$R"
log "npm install openclaw@$VER …"
docker run --rm --user 1001:1001 --memory 1500m --cpus 1 -e HOME=/tmp -e npm_config_cache=/sandbox/.npm \
  -v $S/.npm:/sandbox/.npm -v $R:/sandbox/runtime $IMG \
  sh -c "cd /sandbox/runtime && npm init -y >/dev/null && npm install --no-audit --no-fund --omit=dev openclaw@$VER" \
  > $S/stage-10.1.log 2>&1; rc=$?
tail -3 $S/stage-10.1.log
[ $rc -eq 0 ] || { log "STOP — npm install lỗi rc=$rc (xem $S/stage-10.1.log). Runtime dở dang ở $R — xoá tay trước khi thử lại."; exit 1; }
got=$(python3 -c "import json;print(json.load(open('$R/package-lock.json'))['packages']['node_modules/openclaw']['integrity'])" 2>/dev/null)
ver=$(python3 -c "import json;print(json.load(open('$R/node_modules/openclaw/package.json'))['version'])")
log "đã cài version=$ver integrity_khớp=$([ "$got" = "$want" ] && echo YES || echo NO)"
[ "$ver" = "$VER" ] && [ "$got" = "$want" ] || { log "STOP — version/integrity không khớp."; exit 1; }
# npm 11.19 chặn install-scripts (cảnh báo "npm warn install-scripts") → chạy tay đúng postinstall của gói (12/10: rc=0).
docker run --rm --user 1001:1001 --memory 800m -e HOME=/tmp -v $R:/sandbox/runtime $IMG \
  sh -c "cd /sandbox/runtime/node_modules/openclaw && node scripts/postinstall-bundled-plugins.mjs" || { log "STOP — postinstall lỗi"; exit 1; }
[ -e $R/node_modules/openclaw/.openclaw-lifecycle-pending ] && { log "STOP — lifecycle marker còn"; exit 1; }
oc(){ docker run --rm --user 1001:1001 --memory 800m -v $R:/sandbox/runtime:ro $IMG node /sandbox/runtime/node_modules/openclaw/dist/entry.js "$@" < /dev/null 2>&1; }
log "--version: $(oc --version | head -1)"
log "--- help (để Claude Code soạn bước UAT Sol chính xác)"
oc agent --help | head -40 > $S/stage-10.1-help-agent.txt; oc models --help | head -40 > $S/stage-10.1-help-models.txt
oc plugins --help | head -30 > $S/stage-10.1-help-plugins.txt
wc -l $S/stage-10.1-help-*.txt
log "du runtime: $(du -sh $R | cut -f1)"
log "STAGE_OK — báo Claude Code đọc help và kiểm trước khi chạy 20_cutover.sh"
