#!/bin/bash
# 40 — Dọn container Nemo cũ (Hưng GO 12/10 sau khi Nemo 10.1 OK). MẶC ĐỊNH DRY-RUN; APPLY=1 để xoá.
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 40_cleanup_old.sh
#   ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'APPLY=1 bash -s' < 40_cleanup_old.sh
# Xoá: container pre-ca, 9.6, 9.1 + runtime-9.6 và runtime (9.1) — chỉ 2 container đó dùng.
# GIỮ: nemo-sandbox-9.8 + runtime-9.8 (rollback vài ngày), nemo-sandbox (10.1 đang chạy), runtime-10.1. Image node dùng chung — không đụng.
set -u
S=/home/hung/sandbox-nemo; APPLY=${APPLY:-0}
CONTAINERS=(nemo-sandbox-pre-ca nemo-sandbox-9.6 nemo-sandbox-9.1)
DIRS=("$S/runtime-9.6" "$S/runtime")
log(){ echo "[$(date +%T)] $*"; }
[ "$(docker inspect -f '{{.State.Running}}' nemo-sandbox 2>/dev/null)" = true ] || { log "STOP — nemo-sandbox (10.1) không chạy; không dọn lúc này."; exit 2; }
v=$(docker exec nemo-sandbox node -e 'console.log(require("/sandbox/runtime/node_modules/openclaw/package.json").version)')
[ "$v" = 2026.10.1 ] || { log "STOP — Nemo không ở 10.1 (đang $v)."; exit 2; }
docker ps -a --format '{{.Names}}' | grep -qx nemo-sandbox-9.8 || log "CẢNH BÁO — không thấy nemo-sandbox-9.8 (rollback)."
bad=0
for c in "${CONTAINERS[@]}"; do
  st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null) || { log "  – $c không còn"; continue; }
  [ "$st" = exited ] || { log "  ✗ $c đang $st — bỏ qua"; bad=1; continue; }
  log "  ✔ container $c ($st) $(docker ps -a --size --filter name=^/$c$ --format '{{.Size}}')"
done
INUSE=$(docker ps -a --format '{{.Names}}' | grep -vxF -f <(printf '%s\n' "${CONTAINERS[@]}") | while read n; do
  docker inspect -f '{{range .Mounts}}{{.Source}} {{end}}' "$n"; done | tr ' ' '\n' | sort -u)
for d in "${DIRS[@]}"; do
  [ -d "$d" ] || { log "  – $d không còn"; continue; }
  if echo "$INUSE" | grep -qx "$d"; then log "  ✗ $d còn container khác mount — bỏ qua"; bad=1; continue; fi
  log "  ✔ thư mục ${d#$S/} $(du -sh "$d" | cut -f1)"
done
log "giữ lại: nemo-sandbox (10.1), nemo-sandbox-9.8 + runtime-9.8, runtime-10.1"
if [ "$APPLY" != 1 ]; then log "DRY-RUN — không xoá. APPLY=1 để xoá."; exit 0; fi
[ $bad = 0 ] || { log "STOP — có mục bị chặn."; exit 2; }
for c in "${CONTAINERS[@]}"; do docker inspect "$c" >/dev/null 2>&1 && docker rm "$c" >/dev/null && log "  đã xoá container $c"; done
for d in "${DIRS[@]}"; do [ -d "$d" ] && rm -rf -- "$d" && log "  đã xoá ${d#$S/}"; done
log "còn lại: $(docker ps -a --format '{{.Names}} {{.Status}}' | grep nemo | tr '\n' ';')"
log "df: $(df -h / | tail -1 | awk '{print $4" trống ("$5")"}')"
