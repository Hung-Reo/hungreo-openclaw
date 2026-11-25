#!/usr/bin/env bash
# 30 — READ-ONLY sau 10_apply (chạy ≥ 6 phút sau OK 10 để qua lượt poll đầu). Claude chạy:  ssh … 'bash /home/hung/ops/suckhoe-kb-fix-20261027/30_verify.sh'
# Hưng chạy thêm  … 30_verify.sh --uat  để in lệnh UAT (có mã của candidate ĐÃ duyệt 25/10 — mã này không duyệt/từ chối được gì nữa).
set -uo pipefail
export TZ=Asia/Ho_Chi_Minh XDG_RUNTIME_DIR="/run/user/$(id -u)"
PKG=$(cd "$(dirname "$0")" && pwd)
P=/home/hung/.openclaw-suckhoe/extensions/suckhoe-kb-weekly
CFG=/home/hung/.openclaw-suckhoe/openclaw.json
U=openclaw-gateway-suckhoe.service
W=$(jq -r '.plugins.entries["suckhoe-kb-weekly"].config.whitelistPath' "$CFG")
KB=$(jq -r '.plugins.entries["suckhoe-kb-weekly"].config.kbRoot' "$CFG")
echo "== 30 $(date '+%F %T')"
echo "  $U $(systemctl --user is-active $U) pid=$(systemctl --user show $U -p MainPID --value) NRestarts=$(systemctl --user show $U -p NRestarts --value) since=$(systemctl --user show $U -p ActiveEnterTimestamp --value) readyz=$(curl -s -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:18795/readyz)"
echo "  healthcheck.timer $(systemctl --user is-active openclaw-healthcheck.timer)"
for f in dist/index.js dist/src/commands.js dist/src/poller.js dist/src/candidate.js; do
  [ "$(sha256sum "$P/$f" | cut -c1-64)" = "$(sha256sum "$PKG/files/$f" | cut -c1-64)" ] && echo "  live=bản vá: $f" || echo "  !! live KHÁC bản vá: $f"
done
echo "  whitelist: dòng=$(grep -cvE '^\s*(#|$)' "$W") dalieu.vn=$(grep -cxF dalieu.vn "$W") medlineplus=$(grep -cxF medlineplus.gov "$W") dailymed=$(grep -cxF dailymed.nlm.nih.gov "$W")"
SINCE=$(systemctl --user show $U -p ActiveEnterTimestamp --value | cut -d' ' -f2-3)
J=$(journalctl --user -u $U --since "$SINCE" --no-pager)
echo "  log từ start: plugin_loaded=$(grep -c 'http server listening.*suckhoe-kb-' <<<"$J") drive_poll=$(grep -c 'Drive poll' <<<"$J") drive_poll_failed=$(grep -c 'Drive poll failed' <<<"$J") kb_err=$(grep -iE 'suckhoe-kb|kb-review' <<<"$J" | grep -ciE 'error|fail')"
python3 -c "import json;d=json.load(open('$KB/medical/review-state/drive-files.json'));print('  ledger OK, entries=',len(d),' reminderFor=',sum(1 for v in d.values() if v.get('reminderFor')),' expiredNotice=',sum(1 for v in d.values() if v.get('expiredNoticeFor')))"
pend=$(grep -l '"status": *"pending"' "$KB"/medical/review-state/suckhoe-*.json 2>/dev/null | wc -l); echo "  candidate pending hiện tại: $pend"
if [ "${1:-}" = "--uat" ]; then
  R=$KB/medical/review-state/suckhoe-2026-10-25-stroke-and-heart.json
  ST=$(python3 -c "import json;print(json.load(open('$R'))['status'])")
  TOK=$(python3 -c "import json;print(json.load(open('$R'))['token'])")
  echo; echo "UAT (Hưng gõ trong chat Suckhoe, từng lệnh) — record 25/10 status=$ST:"
  echo "  1) /kb_review show $TOK      → mong đợi tin của PLUGIN bắt đầu '🩺 Suckhoe KB Weekly Candidate'"
  if [ "$ST" = approved ] || [ "$ST" = rejected ]; then
    echo "  2) /kb_review approve $TOK   → mong đợi 'Candidate này đã được xử lý trước đó.' (plugin chặn, KHÔNG phải AI trả lời)"
  else
    echo "  (bỏ lệnh 2: record chưa quyết — gõ approve sẽ duyệt THẬT)"
  fi
  echo "  Nếu thấy AI trả lời dài/khác → lệnh gõ tay cũng rơi vào AI trên 9.34 → báo Claude."
fi
echo "OK 30"
