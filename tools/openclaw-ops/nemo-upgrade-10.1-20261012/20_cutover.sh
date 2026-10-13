#!/bin/bash
# 20 — Nâng Nemo 2026.9.8 → 2026.10.1 + fallback openai/gpt-6.1-sol (Hưng GO 12/10/2026). Mẫu: cutover-9.8.sh + 13_recreate_with_ca.sh.
# Stop-first. Giữ container cũ (đổi tên nemo-sandbox-9.8, restart=no) + tar config/workspace để rollback (99_rollback.sh).
# DRY_RUN mặc định. APPLY=1 để chạy thật.
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 20_cutover.sh
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'APPLY=1 bash -s' < 20_cutover.sh
set -u
S=/home/hung/sandbox-nemo; VER=2026.10.1; R=$S/runtime-10.1; OLD=nemo-sandbox-9.8
IMG=node:24.21.0-bookworm-slim; CA=/etc/ssl/certs/ca-certificates.crt
TS=$(date +%Y%m%d-%H%M%S); B=/home/hung/backups/nemo-upgrade-10.1-$TS; APPLY=${APPLY:-0}
log(){ echo "[$(date +%T)] $*"; }
oc(){ docker run --rm --user 1001:1001 --memory 1200m --env-file "$S/nemo.env" \
  -e SSL_CERT_FILE=$CA -v $CA:$CA:ro \
  -v "$S/.npm:/sandbox/.npm" -v "$R:/sandbox/runtime:ro" -v "$S/config:/sandbox/config" \
  -v "$S/workspace:/sandbox/workspace" -v "$S/.cache:/sandbox/.cache" -v "$B:/sandbox/batch" \
  $IMG node /sandbox/runtime/node_modules/openclaw/dist/entry.js "$@" < /dev/null; }

# ---- điều kiện
v=$(python3 -c "import json;print(json.load(open('$R/node_modules/openclaw/package.json'))['version'])" 2>/dev/null)
cur=$(docker exec nemo-sandbox node -e 'console.log(require("/sandbox/runtime/node_modules/openclaw/package.json").version)' 2>/dev/null)
avail=$(free -m | awk '/^Mem:/{print $7}')
log "runtime-10.1=$v | Nemo đang chạy=$cur | RAM available=${avail}MB | backup sẽ ở $B"
[ "$v" = "$VER" ] || { log "STOP — chưa stage runtime $VER (chạy 10_stage.sh APPLY=1)."; exit 2; }
[ "$cur" = 2026.9.8 ] || { log "STOP — Nemo không ở 2026.9.8 như dự kiến."; exit 2; }
docker ps -a --format '{{.Names}}' | grep -qx $OLD && { log "STOP — container $OLD đã tồn tại."; exit 2; }
[ -f $CA ] || { log "STOP — thiếu $CA"; exit 2; }
[ "$avail" -ge 1200 ] || { log "STOP — RAM thấp."; exit 2; }
log "config hiện tại: $(jq -c '{primary:.agents.defaults.model.primary,fb:.agents.defaults.model.fallbacks,stream:.channels.telegram.streaming.mode}' $S/config/openclaw.json)"
if [ "$APPLY" != 1 ]; then
  log "DRY-RUN — các bước sẽ chạy: stop nemo-sandbox → tar config+workspace → doctor --lint (10.1) → plugin @openclaw/codex@$VER --pin"
  log "  → config set: models.openai/gpt-6.1-sol.agentRuntime.id=codex; fallbacks=[openai/gpt-6.1-sol] (dry-run rồi áp) → diff"
  log "  → đổi tên cũ $OLD (restart=no) → container mới runtime-10.1 (2560m/4608m, CA, SSL_CERT_FILE) → readyz ≤300s"
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

# ---- 2. lint + plugin + config bằng runtime 10.1 (container cũ đang dừng)
log "[2] doctor --lint (10.1)"; oc doctor --lint --json > "$B/doctor-lint.json" 2> "$B/doctor-lint.err"; log "  rc=$? (xem $B/doctor-lint.*)"
log "[3] plugin @openclaw/codex@$VER --pin"
oc plugins install @openclaw/codex@$VER --pin > "$B/plugin-codex.log" 2>&1 || { log "STOP — cài plugin codex lỗi (xem $B/plugin-codex.log). Chạy 99_rollback.sh $B"; exit 1; }
cat > "$B/batch.json" <<'JSON'
[
 {"path":"agents.defaults.models.openai/gpt-6.1-sol.agentRuntime.id","value":"codex"},
 {"path":"agents.defaults.model.fallbacks","value":["openai/gpt-6.1-sol"]}
]
JSON
log "[4] config set dry-run → apply"
oc config set --batch-file /sandbox/batch/batch.json --dry-run > "$B/config-dryrun.log" 2>&1 || { log "STOP — dry-run config lỗi; chạy 99_rollback.sh $B"; exit 1; }
oc config set --batch-file /sandbox/batch/batch.json > "$B/config-apply.log" 2>&1 || { log "STOP — áp config lỗi; chạy 99_rollback.sh $B"; exit 1; }
log "[5] DIFF config (khoá nhạy cảm che <R>)"
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
log "  primary/fallback sau: $(jq -c '{primary:.agents.defaults.model.primary,fb:.agents.defaults.model.fallbacks}' $S/config/openclaw.json)"

# ---- 3. container mới
log "[6] đổi tên cũ → $OLD, tạo container mới runtime-10.1"
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
log "[7] chờ readyz ≤300s"
ok=0; for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1:18796/readyz)" = 200 ] && { log "  READY ~$((i*5))s"; ok=1; break; }
  [ "$(docker inspect -f '{{.State.Running}}' nemo-sandbox)" = true ] || { log "  container đã thoát"; break; }
  sleep 5
done
docker logs --since "$SINCE" nemo-sandbox 2>&1 | grep -E "agent model|http server listening|Cannot find module|Invalid|ERROR|error" \
  | grep -viE "token|secret|key=" | cut -c1-220 | head -12
log "trạng thái: $(docker ps -a --format '{{.Names}} {{.Status}}' | grep nemo | tr '\n' ';')"
docker stats --no-stream --format '{{.Name}} {{.MemUsage}}' nemo-sandbox
[ $ok = 1 ] || { log "CHƯA READY — báo Claude Code; rollback: 99_rollback.sh $B"; exit 1; }
log "CUTOVER_OK — Hưng nhắn Nemo 1 câu + /status; báo Claude Code verify (config, model, chi phí, fallback Sol 6.1). Rollback: 99_rollback.sh $B"
