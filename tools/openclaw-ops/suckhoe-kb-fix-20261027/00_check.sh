#!/usr/bin/env bash
# 00 — READ-ONLY: kiểm gói + test bản vá nhắc duyệt và Rotation V2 trên BẢN SAO tạm. Không ghi vào plugin/whitelist live.
# Chạy (Claude hoặc Hưng):  ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash /home/hung/ops/suckhoe-kb-fix-20261027/00_check.sh'
set -euo pipefail
export TZ=Asia/Ho_Chi_Minh
PKG=$(cd "$(dirname "$0")" && pwd)
NODE=/home/hung/openclaw-node-24.22.1/node/bin/node
P=/home/hung/.openclaw-suckhoe/extensions/suckhoe-kb-weekly
CFG=/home/hung/.openclaw-suckhoe/openclaw.json
[ "$(hostname)" = srv1367812 ] || { echo "ABORT: sai host"; exit 1; }
[ -x "$NODE" ] || { echo "ABORT: không thấy $NODE"; exit 1; }
W=$(jq -r '.plugins.entries["suckhoe-kb-weekly"].config.whitelistPath' "$CFG")
KB=$(jq -r '.plugins.entries["suckhoe-kb-weekly"].config.kbRoot' "$CFG")
[ -f "$W" ] && [ -d "$KB/medical/review-state" ] || { echo "ABORT: không thấy whitelist/kbRoot"; exit 1; }
[ ! -L "$W" ] || { echo "ABORT: whitelist là symlink — báo Claude"; exit 1; }
echo "== 00 $(date '+%F %T')  node=$($NODE --version)"

# 1) Gói còn nguyên (SHA256SUMS tạo trên Mac)
(cd "$PKG" && sha256sum -c --quiet SHA256SUMS) || { echo "ABORT: gói bị đổi sau khi Claude soạn"; exit 1; }
echo "  PKG_SHA_OK"

# 2) Plugin live đúng bản gốc mà bản vá dựa vào (nếu ai đó đã sửa plugin, dừng lại)
for pair in "dist/index.js:index.js" "dist/src/commands.js:commands.js" "dist/src/poller.js:poller.js" "dist/src/candidate.js:candidate.js"; do
  live=${pair%%:*}; base=${pair##*:}
  a=$(sha256sum "$P/$live" | cut -c1-64); b=$(sha256sum "$PKG/base/$base" | cut -c1-64)
  if [ "$a" = "$b" ]; then echo "  base khớp: $live"
  else
    c=$(sha256sum "$PKG/files/$live" | cut -c1-64)
    [ "$a" = "$c" ] && echo "  ĐÃ ÁP từ trước: $live" || { echo "ABORT: $live live khác cả bản gốc lẫn bản vá — báo Claude"; exit 1; }
  fi
done

# 3) Whitelist merge: live + dalieu.vn (KHÔNG bỏ domain nào đang có)
ST=$(mktemp -d /tmp/kbfix-00.XXXXXX); trap 'rm -rf "$ST"' EXIT
cp "$W" "$ST/whitelist.merged.txt"
grep -qxF 'dalieu.vn' "$ST/whitelist.merged.txt" || printf '%s\n' 'dalieu.vn' >> "$ST/whitelist.merged.txt"
echo "  whitelist diff live → merged:"; diff "$W" "$ST/whitelist.merged.txt" | sed 's/^/    /' || true
removed=$(comm -23 <(grep -vE '^\s*(#|$)' "$W" | sort -u) <(grep -vE '^\s*(#|$)' "$ST/whitelist.merged.txt" | sort -u) | wc -l | tr -d ' ')
[ "$removed" = 0 ] || { echo "ABORT: merge làm mất domain"; exit 1; }

# 4) Dựng bản sao plugin = live + bản vá, rồi test
mkdir -p "$ST/plugin"; cp -a "$P/dist" "$ST/plugin/dist"
cp "$PKG/files/dist/index.js" "$ST/plugin/dist/index.js"
cp "$PKG/files/dist/src/commands.js" "$PKG/files/dist/src/poller.js" "$PKG/files/dist/src/candidate.js" "$ST/plugin/dist/src/"
for f in "$ST"/plugin/dist/index.js "$ST"/plugin/dist/src/*.js; do "$NODE" --check "$f"; done
"$NODE" --input-type=module -e "const m=await import('file://$ST/plugin/dist/index.js'); if(typeof m.default!=='function') throw new Error('no register');" || { echo "ABORT: dist/index.js bản vá import lỗi"; exit 1; }
echo "  IMPORT_INDEX_OK"
"$NODE" "$PKG/tests/test-approval-fix.mjs" "$ST/plugin" | tail -1
cp -a "$PKG/v2" "$ST/v2"; cp "$ST/whitelist.merged.txt" "$ST/v2/medical-consumer-health-whitelist.txt"
(cd "$ST/v2" && "$NODE" test-rotation-v2.mjs | tail -1)

# 5) Candidate còn PENDING (file stage còn trong review/) phải qua validator mới + whitelist merge — vì approve/renew
#    re-validate bằng code mới. Candidate đã duyệt/từ chối: file stage đã dọn → chỉ đếm. V2 = V1 cho mọi tuần ≤ 01/11.
"$NODE" --input-type=module - "$ST/plugin/dist/src/candidate.js" "$ST/whitelist.merged.txt" "$KB/medical/review-state" <<'JS'
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
const [cand, wl, dir] = process.argv.slice(2);
const { loadWhitelist, validateCandidate, rotationVersionOf, expectedTopic } = await import("file://" + cand);
const whitelist = await loadWhitelist(wl);
let ok = 0, bad = 0, decided = 0;
for (const name of (await readdir(dir)).filter((n) => n.startsWith("suckhoe-") && n.endsWith(".json"))) {
  const rec = JSON.parse(await readFile(path.join(dir, name), "utf8"));
  if (rec.status !== "pending") { decided++; continue; }
  let raw; try { raw = await readFile(rec.candidatePath, "utf8"); } catch { bad++; console.log(`  PENDING ${rec.candidateId}: không đọc được file stage`); continue; }
  const v = validateCandidate(raw, whitelist);
  if (v.ok) ok++; else { bad++; console.log(`  INVALID pending ${rec.candidateId} v${rotationVersionOf(rec.weekOf)}: ${v.errors.join(",")}`); }
}
console.log(`  REVALIDATE pending ok=${ok} invalid=${bad} · đã quyết=${decided}`);
console.log(`  expectedTopic 2026-11-01=${expectedTopic("2026-11-01")} (V1) · 2026-11-08=${expectedTopic("2026-11-08")} (V2)`);
if (bad || expectedTopic("2026-11-08") !== "skin") process.exit(1);
JS
# 6) Dry-run: lượt poll ban ngày đầu tiên sau deploy sẽ gửi những tin nhắc/hết hạn nào (đọc bản sao sổ cái, không gửi gì)
cp "$KB/medical/review-state/drive-files.json" "$ST/ledger.json"
"$NODE" --input-type=module - "$ST/plugin/dist/src/poller.js" "$KB/medical/review-state" "$ST/ledger.json" <<'JS'
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
const [pollerPath, dir, ledger] = process.argv.slice(2);
const { CandidatePoller } = await import("file://" + pollerPath);
const records = [];
for (const n of (await readdir(dir)).filter((x) => x.startsWith("suckhoe-") && x.endsWith(".json"))) records.push(JSON.parse(await readFile(path.join(dir, n), "utf8")));
const sent = [];
const poller = new CandidatePoller({ kbRoot: "/nonexistent" }, [], { initialize: async () => {}, listRecords: async () => records }, {},
  { reminder: async (r) => sent.push(`nhắc ${r.candidateId}`), expired: async (r) => sent.push(`hết hạn ${r.candidateId}`) });
poller.writeIndex = async () => {};
const now = Date.now();
const vn = new Date(now + 7 * 3600e3); vn.setUTCHours(10, 0, 0, 0);
let at = vn.getTime() - 7 * 3600e3; if (at < now) at += 86400e3; // 10:00 giờ VN kế tiếp
await poller.remindPending(JSON.parse(await readFile(ledger, "utf8")), at);
console.log(`  DRY-RUN tin sẽ gửi ở lượt poll ban ngày đầu: ${sent.length ? sent.join("; ") : "(không có)"}`);
JS
echo "OK 00 — PRECHECK_PASS (chưa ghi gì lên live)"
