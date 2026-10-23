# 22/10/2026 — Hungreo: cài plugin local `edu-review` — dry-run không giống lượt thật, và nút "command" rơi xuống AI

Loại: plugin-install, config-validation, dry-run-fidelity, telegram-buttons, fail-open-to-llm

## 1. Lần cài đầu FAILED sau khi đã stop gateway (18:48 VNT, ~2 phút downtime)

VERIFIED (log `10_apply.sh`, backup `edu-review-hungreo-20261022-184759`):

- Script set `plugins.allow` và `plugins.entries["edu-review"]` bằng 2 lệnh `config set` riêng. Khi thư mục plugin đã ở
  `extensions/`, lệnh đầu bị validator chặn: `plugins.entries.edu-review.config.kbRoot: must have required property 'kbRoot'`.
- Dry-run lúc precheck PASS vì khi đó extension **chưa** được copy → dry-run không cùng điều kiện với lượt thật.
  Reviewer fresh-context đã nêu đúng rủi ro này (mục 7) nhưng bị đánh giá thấp.
- `99_rollback.sh` chạy ngay: config sha trả đúng bản gốc, `readyz` 200 sau ~55s.

Lesson:

- Dry-run phải dựng **đúng điều kiện** của lượt thật (file/extension có mặt) — nếu việc đó an toàn khi gateway đang chạy
  (ở đây: extension chưa nằm trong `plugins.allow` nên không nạp), làm nó trong precheck và dọn lại khi dry/lỗi.
- Thay đổi config nhiều khoá phụ thuộc nhau: dùng **một** `openclaw config patch --file` (một lần ghi có validate),
  không chuỗi nhiều `config set`.
- `--expect-current-*` không đi chung `--dry-run` (9.33); `config patch` không nhận patch rỗng; hàm `oc()` có `< /dev/null`
  nên `--stdin` không nhận dữ liệu.
- Diff guard dạng allowlist phải cho `meta.*` (OpenClaw tự đóng dấu khi ghi) — reviewer bắt trước khi chạy.

## 2. Nút `presentation` kiểu `command` → text thường → AI trả lời (19:04 VNT)

VERIFIED (journal `Inbound message … (direct, 29 chars)` đúng độ dài `/edu_review show <token>`; docs 9.33
`channels/telegram/rich-messages.md`; `dist/interactive-registry-*.mjs`):

- Nút `{action:{type:"command", command:"/edu_review …"}}` được đưa vào Rùa như tin nhắn thường → lượt AI, AI báo
  "chưa tìm thấy công cụ /edu_review". Lệnh vẫn có trong menu (`getMyCommands` 65 lệnh, có `edu_review`), và **gõ tay**
  `/edu_review status` thì plugin trả lời trong ~1s → lỗi chỉ ở đường nút.
- Cách đúng ở 9.33: nút `{type:"callback", value:"<ns>:<payload>"}` + `api.registerInteractiveHandler({channel:"telegram",
namespace, handler})`. Runtime tách `callback_data` ở dấu `:` đầu tiên; callback không có handler nhận thì chuyển cho
  agent dạng text. Có dedupe callback 5 phút.
- Plugin 0.1.2 (19:51): handler luôn trả `{handled:true}` cho namespace `edu` (kể cả sai quyền/sai payload) → không gì
  lọt xuống AI. Smoke 19:53: Xem phiếu + Duyệt qua nút, không có `Inbound message` nào, state `approved` + file
  `approved/` có `reviewed_sha256`.

Lesson: lệnh có side-effect của plugin **không** dùng nút `command`; dùng callback + interactive handler. Đây cũng là
hướng sửa cho Suckhoe `/kb-review` (lesson 2026-10-11) — chưa áp dụng, cần plan riêng.

Liên quan: `tools/openclaw-ops/edu-review-plugin-20261022/`, code `hungreo-super-app/tools/edu-review-plugin/`.
