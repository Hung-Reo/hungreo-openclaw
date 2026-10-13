# 11/10/2026 — Suckhoe: lệnh duyệt KB `/kb-review approve` rơi xuống AI, AI báo sai "chưa tìm thấy yêu cầu"

Loại: plugin-command, telegram, openclaw-9.x, fail-open-to-llm, hallucinated-status, misdiagnosis

VERIFIED (journal + `workspace/logs/medical-orchestration.jsonl` + review-state):

- Lệnh text `/kb-review approve <mã>` (từ nút "Duyệt" hoặc gõ) đi đường tin nhắn thường ("Inbound message … 35 chars") rồi
  **thành lượt AI** ở 3/3 lần: 27/09 05:56, 11/10 06:56, 11/10 15:07:27. Cả hai lần 11/10 cùng session `5935c375…` và cùng log
  `context-engine … transcript range is session-rebound` ngay trước lượt AI. Candidate vẫn `pending`.
- Cùng đường text nhưng `show` (13:43, gõ tay) và `renew` (15:07:19, nút) → plugin xử lý trong 2–3 giây.
- Lệnh native `/kb_review approve <mã>` (gạch dưới — Telegram đổi `-`→`_` khi đăng ký lệnh) → plugin xử lý 2/2 lần.
- AI trả lời "chưa tìm thấy yêu cầu tương ứng" dù bản ghi tồn tại → khẳng định sai trạng thái.

Đính chính: handover 04/10 ghi viêm gan B 27/09 "chưa ai duyệt" — sai; Hưng đã bấm, cùng lỗi này.
Giả thuyết bị loại: "đường text của 9.x luôn hỏng" (show/renew text vẫn chạy). Cơ chế chính xác vì sao `approve` rơi: UNVERIFIED
(không khớp regex `/approve` exec-approval, không khớp regex APPROVE của plugin technical-handoff — plugin này chỉ hook
`before_agent_reply`, tức sau khi tin đã rơi). Liên quan upstream openclaw#167982 (registry theo lượt thiếu lệnh plugin).

Lesson: lệnh có side-effect qua plugin phải có kênh xác nhận không phụ thuộc AI — kiểm `review-state` chứ không tin câu trả lời
chat. Khi lệnh plugin rơi xuống AI, AI phải nói "lỗi hệ thống", không suy diễn trạng thái. Thu hẹp bằng phép thử rẻ, an toàn
(`show`, bấm lại nút trên candidate đã duyệt) trước khi kết luận; đính chính ngay khi phép thử lật giả thuyết.

Cách dùng hiện tại: gõ `/kb_review approve <mã>`. Việc mở: sửa tin duyệt (ghi sẵn lệnh gõ tay), luật AGENTS Suckhoe cho lệnh
plugin rơi xuống AI, tìm cơ chế `approve` (hoặc chờ fix upstream 2026.10.x).
