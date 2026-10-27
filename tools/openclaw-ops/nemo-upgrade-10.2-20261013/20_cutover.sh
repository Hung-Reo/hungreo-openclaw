#!/bin/bash
# 20 — Nâng Nemo 2026.10.1 → 2026.10.2 (Hưng GO 13/10/2026, canary trước Suckhoe/Hungreo). Mẫu: nemo-upgrade-10.1-20261012/20_cutover.sh.
# KHÔNG đổi config/model. Chỉ: runtime-10.2 + plugins update codex (khớp version host).
# Stop-first. Giữ container cũ (đổi tên nemo-sandbox-10.1, restart=no) + tar config/workspace để rollback (99_rollback.sh).
# Lesson 12/10: mọi lệnh ghi đều --dry-run trước; plugin đã có → `update`, không `install`.
# DRY_RUN mặc định. APPLY=1 để chạy thật.
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 20_cutover.sh
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'APPLY=1 bash -s' < 20_cutover.sh
set -u
S=/home/hung/sandbox-nemo; VER=2026.10.2; CUR=2026.10.1; R=$S/runtime-10.2; OLD=nemo-sandbox-10.1
IMG=node:24.21.0-bookworm-slim; CA=/etc/ssl/certs/ca-certificates.crt
TS=$(date +%Y%m%d-%H%M%S); B=/home/hung/backups/nemo-upgrade-10.2-$TS; APPLY=${APPLY:-0}
log(){ echo "[$(date +%T)] $*"; }
oc(){ docker run --rm --user 1001:1001 --memory 1200m --env-file "$S/nemo.env" \
  -e SSL_CERT_FILE=$CA -v $CA:$CA:ro \
  -v "$S/.npm:/sandbox/.npm" -v "$R:/sandbox/runtime:ro" -v "$S/config:/sandbox/config" \
  -v "$S/workspace:/sandbox/workspace" -v "$S/.cache:/sandbox/.cache" \
  $IMG node /sandbox/runtime/node_modules/openclaw/dist/entry.js "$@" < /dev/null; }
restore_old(){ # dùng khi dừng TRƯỚC bước đổi tên: container cũ vẫn tên nemo-sandbox
  log "RESTORE — $1"; cd $S && mv config config.failed-10.2-$(date +%H%M%S) && tar -xpf "$B/sandbox-nemo-config.tar" && docker start nemo-sandbox >/dev/null
  log "  $(docker ps --format '{{.Names}} {{.Status}}' | grep nemo | tr '\n' ';')"; exit 1; }

# ---- điều kiện
v=$(python3 -c "import json;print(json.load(open('$R/node_modules/openclaw/package.json'))['version'])" 2>/dev/null)
cur=$(docker exec nemo-sandbox node -e 'console.log(require("/sandbox/runtime/node_modules/openclaw/package.json").version)' 2>/dev/null)
avail=$(free -m | awk '/^Mem:/{print $7}'); disk=$(df -BG --output=avail / | tail -1 | tr -dc 0-9)
log "runtime-10.2=$v | Nemo đang chạy=$cur | RAM available=${avail}MB | disk=${disk}G | backup sẽ ở $B"
[ "$v" = "$VER" ] || { log "STOP — chưa stage runtime $VER."; exit 2; }
[ -e $R/node_modules/openclaw/.openclaw-lifecycle-pending ] && { log "STOP — lifecycle marker còn (chạy 10_stage_verify.sh)."; exit 2; }
[ "$cur" = "$CUR" ] || { log "STOP — Nemo không ở $CUR như dự kiến."; exit 2; }
docker ps -a --format '{{.Names}}' | grep -qx $OLD && { log "STOP — container $OLD đã tồn tại."; exit 2; }
[ -f $CA ] || { log "STOP — thiếu $CA"; exit 2; }
[ "$avail" -ge 1200 ] || { log "STOP — RAM thấp."; exit 2; }
[ "$disk" -ge 5 ] || { log "STOP — thiếu disk."; exit 2; }
h=$(TZ=Asia/Ho_Chi_Minh date +%H%M); [ "$h" -ge 0620 ] && [ "$h" -le 0700 ] && { log "STOP — khung Morning Brief 06:20–07:00."; exit 2; }
log "config hiện tại: $(jq -c '{primary:.agents.defaults.model.primary,fb:.agents.defaults.model.fallbacks,stream:.channels.telegram.streaming.mode}' $S/config/openclaw.json)"
if [ "$APPLY" != 1 ]; then
  log "DRY-RUN — sẽ: stop → tar config+workspace → doctor --lint (10.2) → plugins update codex --dry-run → update"
  log "  → đổi tên cũ $OLD (restart=no) → container mới runtime-10.2 (1 CPU, 2560m/4608m, CA, SSL_CERT_FILE) → readyz ≤300s"
  exit 0
fi

# ---- 1. stop + backup
mkdir -p "$B" && chmod 700 "$B"
log "[1] stop nemo-sandbox (graceful 60s)"
docker stop -t 60 nemo-sandbox >/dev/null || { log "STOP — stop lỗi"; docker start nemo-sandbox; exit 1; }
tar -C $S -cpf "$B/sandbox-nemo-config.tar" config && tar -C $S -cpf "$B/sandbox-nemo-workspace.tar" workspace \
  || { log "STOP — tar lỗi → start lại cũ"; docker start nemo-sandbox; exit 1; }
cp -p $S/config/openclaw.json "$B/openclaw.json.before"; docker inspect nemo-sandbox > "$B/container-inspect.json"
( cd "$B" && sha256sum *.tar > SHA256SUMS && sha256sum -c --quiet SHA256SUMS ) || { log "STOP — checksum lỗi"; docker start nemo-sandbox; exit 1; }
log "  backup OK: $(du -sh $B | cut -f1)"

# ---- 2. lint + plugin bằng runtime 10.2 (container cũ đang dừng)
log "[2] doctor --lint (10.2)"; oc doctor --lint --json > "$B/doctor-lint.json" 2> "$B/doctor-lint.err"; log "  rc=$? (xem $B/doctor-lint.*)"
log "[3] plugins update codex --dry-run"
oc plugins update codex --dry-run > "$B/plugin-codex-dryrun.log" 2>&1 || restore_old "dry-run plugin codex lỗi (xem $B/plugin-codex-dryrun.log)"
log "  $(tail -1 $B/plugin-codex-dryrun.log)"
oc plugins update codex > "$B/plugin-codex-update.log" 2>&1 || restore_old "update plugin codex lỗi (xem $B/plugin-codex-update.log)"
log "  $(tail -1 $B/plugin-codex-update.log)"
log "[4] DIFF config (khoá nhạy cảm che <R>)"
python3 - "$S/config/openclaw.json" "$B/openclaw.json.before" <<'PY'
import json, sys
def flat(d, p=""):
    o = {}
    if isinstance(d, dict):
        for k, v in d.items(): o.update(flat(v, p + "." + k))
    else: o[p] = d
    return o
a, b = flat(json.load(open(sys.argv[1]))), flat(json.load(open(sys.argv[2])))
for k in sorted(set(a) | set(b)):
    if a.get(k) != b.get(k):
        s = any(x in k.lower() for x in ("token", "key", "secret", "password", "chatid", "allowfrom"))
        print("   ", k, "| old=", "<R>" if s else b.get(k), "| new=", "<R>" if s else a.get(k))
PY

# ---- 3. container mới (tham số y hệt container 10.1, verify docker inspect 13/10)
log "[5] đổi tên cũ → $OLD, tạo container mới runtime-10.2"
docker rename nemo-sandbox $OLD && docker update --restart=no $OLD >/dev/null || { log "STOP — rename lỗi; chạy 99_rollback.sh $B"; exit 1; }
SINCE=$(date +%s)
docker run -d --name nemo-sandbox --restart unless-stopped --user 1001:1001 \
  --cpus 1 --memory 2560m --memory-swap 4608m --log-opt max-size=10m --log-opt max-file=3 \
  -p 127.0.0.1:18796:18796 -p 127.0.0.1:8789:8789 --env-file $S/nemo.env \
  -e SSL_CERT_FILE=$CA -v $CA:$CA:ro \
  -v $S/.npm:/sandbox/.npm -v $R:/sandbox/runtime:ro -v $S/config:/sandbox/config \
  -v $S/config/openclaw.json:/sandbox/config/openclaw.json:ro -v $S/workspace:/sandbox/workspace -v $S/.cache:/sandbox/.cache \
  $IMG node /sandbox/runtime/node_modules/openclaw/dist/entry.js gateway run --bind lan --port 18796 >/dev/null \
  || { log "STOP — docker run lỗi; chạy 99_rollback.sh $B"; exit 1; }
log "[6] chờ readyz ≤300s"
ok=0; for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1:18796/readyz)" = 200 ] && { log "  READY ~$((i*5))s"; ok=1; break; }
  [ "$(docker inspect -f '{{.State.Running}}' nemo-sandbox)" = true ] || { log "  container đã thoát"; break; }
  sleep 5
done
docker logs --since "$SINCE" nemo-sandbox 2>&1 | grep -E "agent model|http server listening|Cannot find module|Invalid|ERROR|error" \
  | grep -viE "token|secret|key=" | cut -c1-220 | head -12
log "trạng thái: $(docker ps -a --format '{{.Names}} {{.Status}}' | grep nemo | tr '\n' ';')"
docker stats --no-stream --format '{{.Name}} {{.MemUsage}}' nemo-sandbox
[ $ok = 1 ] || { log "CHƯA READY — rollback: 99_rollback.sh $B"; exit 1; }
log "CUTOVER_OK — chạy 30_uat.sh. Rollback: 99_rollback.sh $B"
