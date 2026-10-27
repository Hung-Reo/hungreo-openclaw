# Suckhoe KB — sửa đường duyệt + nhắc duyệt + Rotation V2 (soạn 27/10/2026, CHƯA chạy)

**GO soạn:** Hưng 27/10 "theo khuyến nghị của bạn, soạn cả 2". Chạy thật (10_apply) cần GO riêng.

## Vì sao (VERIFIED 26/10, xem `SESSION_HANDOVER.md` entry 26/10 21:40)
- 18/10 + 25/10: plugin `suckhoe-kb-weekly` nhập file và gửi yêu cầu duyệt đúng chat Hưng. Lệnh `/kb-review approve <token>` từ nút **rơi vào AI** thay vì handler plugin (openclaw#167982 OPEN) → `pending` → hết hạn. Gõ tay `/kb_review approve` từng chạy qua plugin (11/10, core 9.9); trên 9.34 **chưa kiểm** → UAT trước.
- Rotation V2 (17 chủ đề, `skin` đầu tiên ngày 08/11) phải có trên VPS trước **01:00 CN 08/11**. Code V2 cho kết quả y hệt V1 với mọi tuần ≤ 01/11 → deploy sớm an toàn.

## Thay đổi (chỉ plugin `~/.openclaw-suckhoe/extensions/suckhoe-kb-weekly/dist` + whitelist; không đổi `openclaw.json`/model/auth)
| File | Đổi |
|---|---|
| `dist/src/commands.js` | Tin duyệt + tin renew kèm dòng lệnh gõ tay `/kb_review approve <token>`; thêm `reminderNotification`, `expiredNotification` |
| `dist/src/poller.js` | `remindPending()` chạy đầu mỗi poll (trước Drive): pending ≥24h → nhắc 1 lần/mã; hết hạn → báo 1 lần/mã kèm `/kb_review renew <token>`; chỉ 07:00–21:00 VN; bỏ record hết hạn >7 ngày; gửi lỗi → tối đa 3 lần/mã, cách ≥1h (chống spam khi CLI giao tin nhưng vẫn báo lỗi); log lỗi chỉ in mã lỗi (không in dòng lệnh chứa chat ID/token) |
| `dist/index.js` | nối notifier `reminder`/`expired` |
| `dist/src/candidate.js` | Rotation V2 từ Mac (sha `e000941b…`), export tương thích (`validateCandidate`, `sha256`, `toApprovedMarkdown`) |
| whitelist (`kb/policies/medical-consumer-health-whitelist.txt`) | **MERGE**: giữ nguyên bản VPS + thêm `dalieu.vn`. Bản Mac bỏ 5 domain VPS đang có (api.fda.gov, open.fda.gov, dailymed.nlm.nih.gov, medlineplus.gov, dichvucong.dav.gov.vn) → không chép đè |

`src/*.ts` của plugin đã lệch `dist` từ trước (dist dùng `presentation`), nên chỉ vá `dist` (code đang chạy).

## Kiểm chứng đã làm (Mac, 27/10)
- `tests/test-approval-fix.mjs`: **20/20 PASS** trên bản vá (thêm sau review: giới hạn 3 lần, đọc lại sổ cái từ đĩa, biên 07:00/21:00 và 7 ngày, 2 entry cùng candidateId, tin renew mang mã mới); bản gốc FAIL (red loop).
- `v2/test-rotation-v2.mjs` với whitelist merge: **106/106 PASS**. `expectedTopic`: 01/11=`child-health` (V1), 08/11=`skin`.
- Mô phỏng 00/10/99 bằng stub systemctl/curl/journalctl (`tests/sim/run-sim.sh`, cần coreutils Homebrew): 6 kịch bản / 12 điểm kiểm PASS (happy path; 99 thủ công; tự rollback khi readyz không lên — có bật lại healthcheck timer; tự rollback khi plugin không nạp; ABORT khi plugin live bị sửa; ABORT khi gói bị sửa). Bắt và sửa 1 lỗi `wc -l` có khoảng trắng.
- Review fresh-context (opus) 27/10: RUN AFTER FIXES, 0 BLOCKER — đã vá: guard UAT (chỉ in lệnh approve khi record đã quyết), giới hạn gửi lại, 99 không còn `rm -rf dist` trước `mv` + trap bật lại timer, 10 bắt INT/TERM/HUP + chạy nền `setsid nohup`, 00 ABORT khi import index lỗi, SHA256SUMS gồm cả script, khớp entry theo driveFileId, 00 in dry-run danh sách tin sẽ gửi. Finding `renewedAt`: VERIFIED `store.js` VPS có ghi trường này.

## Các bước
| # | Ai | Lệnh | Kỳ vọng |
|---|---|---|---|
| 0 | Hưng | `ssh … 'mkdir -p -m 700 /home/hung/ops'` rồi `scp -r -i ~/.ssh/hostinger_kvm2 tools/openclaw-ops/suckhoe-kb-fix-20261027 hung@72.61.123.33:/home/hung/ops/` | Claude kiểm hash |
| UAT-0 | Hưng | `ssh … 'bash /home/hung/ops/suckhoe-kb-fix-20261027/30_verify.sh --uat'` → gõ 2 lệnh in ra trong chat Suckhoe | Plugin trả lời (không phải AI). **Nếu AI trả lời → dừng, báo Claude** (lệnh gõ tay cũng hỏng trên 9.34) |
| 00 | Claude | `ssh … 'bash /home/hung/ops/suckhoe-kb-fix-20261027/00_check.sh'` | `OK 00 — PRECHECK_PASS` |
| 10 | Hưng (**bấm 1 lần**) | `ssh … 'setsid nohup bash /home/hung/ops/suckhoe-kb-fix-20261027/10_apply.sh > /home/hung/ops/suckhoe-kb-fix-20261027/apply.log 2>&1 < /dev/null &'` (ngoài 04:10–07:15, 19:15–19:45, CN 00:30–09:00) | `OK 10` trong `apply.log`; lỗi → tự rollback |
| 30 | Claude (≥6 phút sau OK 10) | `ssh … 'bash …/30_verify.sh'` | live = bản vá, whitelist có `dalieu.vn` + 5 domain cũ, plugin loaded |
| UAT-1 | Hưng | Gõ lại 2 lệnh UAT | như UAT-0 |
| 99 | Hưng (nếu cần) | `ssh … 'bash …/99_rollback.sh <BACKUP_DIR>'` | `OK 99`. Chỉ an toàn trước 08/11 |

## Chưa làm / ngoài phạm vi
- Cowork: cập nhật prompt scheduled task theo `SKILL.md.v2` (phía Mac, cùng hạn 08/11) — Hưng/Cowork làm.
- Cảnh báo "12:00 CN chưa thấy candidate" (đề xuất của Cowork) — chưa làm.
- Nút bấm vẫn có thể rơi vào AI cho tới khi upstream sửa #167982; bản vá chỉ thêm đường gõ tay + nhắc.

## What could still be wrong
- Lệnh gõ tay `/kb_review` trên 9.34 chưa kiểm → UAT-0 quyết định.
- Restart Suckhoe ~1 phút downtime.
- Rollback sau 08/11 không an toàn (V1 reject tuần ≥16).
