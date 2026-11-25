#!/bin/bash
# 21 — Chạy tiếp cutover từ bước 3 sau lỗi "plugin already exists" (20_cutover.sh dùng sai `plugins install`).
# Dùng lại backup đã tạo khi Nemo dừng. 12/10: path model có dấu chấm phải dùng models["openai/gpt-6.1-sol"] (dạng a.b.c bị tách ở "6.1"). DRY_RUN mặc định (chỉ `plugins update --dry-run`). APPLY=1 để chạy thật.
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s -- /home/hung/backups/nemo-upgrade-10.1-<TS>' < 21_resume.sh
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'APPLY=1 bash -s -- /home/hung/backups/nemo-upgrade-10.1-<TS>' < 21_resume.sh
# Rollback: 99_rollback.sh không dùng được nếu chưa có nemo-sandbox-9.8 → xem RESTORE ở cuối file.
set -u
B=${1:?thiếu thư mục backup}; S=/home/hung/sandbox-nemo; VER=2026.10.1; R=$S/runtime-10.1; OLD=nemo-sandbox-9.8
IMG=node:24.21.0-bookworm-slim; CA=/etc/ssl/certs/ca-certificates.crt; APPLY=${APPLY:-0}
log(){ echo "[$(date +%T)] $*"; }
oc(){ docker run --rm --user 1001:1001 --memory 1200m --env-file "$S/nemo.env" \
  -e SSL_CERT_FILE=$CA -v $CA:$CA:ro \
  -v "$S/.npm:/sandbox/.npm" -v "$R:/sandbox/runtime:ro" -v "$S/config:/sandbox/config" \
  -v "$S/workspace:/sandbox/workspace" -v "$S/.cache:/sandbox/.cache" -v "$B:/sandbox/batch" \
  $IMG node /sandbox/runtime/node_modules/openclaw/dist/entry.js "$@" < /dev/null; }

( cd "$B" && sha256sum -c --quiet SHA256SUMS ) || { log "STOP — backup sai checksum"; exit 2; }
st=$(docker inspect -f '{{.State.Running}}' nemo-sandbox 2>/dev/null)
[ "$st" = false ] || { log "STOP — nemo-sandbox không ở trạng thái đã dừng (state=$st)"; exit 2; }
docker ps -a --format '{{.Names}}' | grep -qx $OLD && { log "STOP — $OLD đã tồn tại"; exit 2; }
cmp -s $S/config/openclaw.json $B/openclaw.json.before || { log "STOP — openclaw.json đã khác backup; báo Claude Code"; exit 2; }
log "điều kiện OK (Nemo dừng, backup đúng, config chưa đổi). Backup: $B"

log "[3] plugins update @openclaw/codex@$VER --dry-run"
oc plugins update "@openclaw/codex@$VER" --dry-run 2>&1 | grep -viE "token|secret|key=" | tail -8
if [ "$APPLY" != 1 ]; then log "DRY-RUN — dừng. Nemo vẫn đang TẮT."; exit 0; fi
oc plugins update "@openclaw/codex@$VER" > "$B/plugin-codex-update.log" 2>&1 || { log "STOP — update plugin lỗi (xem $B/plugin-codex-update.log). RESTORE ở cuối file."; exit 1; }
tail -4 "$B/plugin-codex-update.log" | grep -viE "token|secret|key="

cat > "$B/batch.json" <<'JSON'
[
 {"path":"agents.defaults.models[\"openai/gpt-6.1-sol\"].agentRuntime.id","value":"codex"},
 {"path":"agents.defaults.model.fallbacks","value":["openai/gpt-6.1-sol"]}
]
JSON
log "[4] config set dry-run → apply"
oc config set --batch-file /sandbox/batch/batch.json --dry-run > "$B/config-dryrun.log" 2>&1 || { log "STOP — dry-run config lỗi"; exit 1; }
oc config set --batch-file /sandbox/batch/batch.json > "$B/config-apply.log" 2>&1 || { log "STOP — áp config lỗi"; exit 1; }
log "[5] DIFF config"
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

log "[6] đổi tên cũ → $OLD, tạo container mới runtime-10.1"
docker rename nemo-sandbox $OLD && docker update --restart=no $OLD >/dev/null || { log "STOP — rename lỗi"; exit 1; }
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
log "CUTOVER_OK — chạy 30_uat.sh rồi báo Claude Code. Rollback: 99_rollback.sh $B"

# RESTORE (khi dừng TRƯỚC bước [6], container cũ vẫn tên nemo-sandbox):
#   cd ~/sandbox-nemo && mv config config.failed-10.1-$(date +%H%M%S) && tar -xpf <B>/sandbox-nemo-config.tar && docker start nemo-sandbox
