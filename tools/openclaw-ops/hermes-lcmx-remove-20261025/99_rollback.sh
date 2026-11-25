#!/usr/bin/env bash
# 99 — Trả lại hermes-lcm-x như trước 10_remove (config + plugin + metadata + lcm.db). KHÔNG restart gateway.
# ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s <BACKUP_DIR>' < 99_rollback.sh
set -euo pipefail
umask 077
H=/home/hung/.hermes; PN=hermes-lcm-x
B=${1:?cần BACKUP_DIR do 10_remove.sh in ra}
[ "$(hostname)" = srv1367812 ] || { echo "ABORT: sai host"; exit 1; }
case "$B" in "$H"/backups/lcmx-remove-[0-9]*) ;; *) echo "ABORT: $B không phải backup của việc này"; exit 1;; esac
(cd "$B" && sha256sum -c --quiet SHA256SUMS) || { echo "ABORT: SHA256 backup lệch"; exit 1; }
if [ -f "$B/post-apply.sha256" ]; then
  sha256sum -c --quiet "$B/post-apply.sha256" || { echo "ABORT: config/metadata đã đổi sau lúc gỡ (vd secrets refresh) — chép đè sẽ mất thay đổi đó. Báo Claude để merge riêng 3 khoá."; exit 1; }
fi
HAVE_DIR=0; [ -e "$H/plugins/$PN" ] && HAVE_DIR=1   # apply có thể fail trước bước remove
cp -p "$H/config.yaml" "$B/config.yaml.pre-rollback-$(date +%H%M%S)"
cp -p "$B/config.yaml" "$H/config.yaml.rb.tmp" && mv "$H/config.yaml.rb.tmp" "$H/config.yaml"
cp -p "$B/install-metadata.json" "$H/plugins/.install-metadata.json.rb.tmp" && mv "$H/plugins/.install-metadata.json.rb.tmp" "$H/plugins/.install-metadata.json"
[ $HAVE_DIR = 1 ] && echo "  thư mục plugin còn nguyên — không giải nén lại" || tar -C "$H/plugins" -xpf "$B/plugin-hermes-lcm-x.tar"
for f in lcm.db lcm.db-wal lcm.db-shm; do [ -e "$B/live-$f" ] && [ ! -e "$H/$f" ] && cp -p "$B/live-$f" "$H/$f"; done
grep -q hermes-lcm-x "$H/config.yaml" && [ -d "$H/plugins/$PN" ] || { echo "FAILED: khôi phục chưa đủ"; exit 1; }
echo "OK 99 — đã trả LCM-X về như trước gỡ (config/plugin/metadata). Gateway KHÔNG restart; plugin chỉ nạp khi gateway khởi động lại hoặc 'hermes plugins enable'."
