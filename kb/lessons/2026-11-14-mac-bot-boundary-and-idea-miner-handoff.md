# 14/11/2026 — Bot Mac: đọc `settings` trước lệnh shell, giữ ranh giới module khi bridge bị khóa ghi

Loại: gemini-bot, mac-collab-hub, permissions, idea-miner, alignment, handoff

## Catch-up nhanh

- Sau commit `3df4972a64` (`fix(mac-collab-hub): siết quyền bot Gemini (5.1–5.4)`), `gemini-collab-settings.json` khóa ghi (`deny`) toàn bộ file lõi của `gemini-telegram-bridge/` (`server.ts`, `commands.ts`, `permissions.ts`, `handover.ts`, …) và `allow` chỉ mở `git status|log|diff|show` + một số `read_file`.
- Trong phiên triển khai `idea-miner-mac` cho `@hungreo_gemini_bot`:
  1. Bot dùng `rg -n "x_brief|XBrief|..."` có dấu `|` bên trong regex → làm bật popup xin quyền trên DM Telegram và bị từ chối.
  2. Bot gọi `bun test` không báo trước lý do xin quyền → DM bật nút duyệt; người dùng trả lời text `"Yes, proceed"` thay vì bấm nút inline nên lệnh bị tính là denied.
  3. Khi nhận ra `server.ts`/`commands.ts` nằm trong `deny`, bot chuyển sang hướng đúng: xây trọn module độc lập `idea-miner-mac/` + `DESIGN-BA-TECH-SPEC.md` + `ISSUE-LOG.md` để Agent PC review và nối dây.

## Bài học

1. **Đọc `gemini-collab-settings.json` trước khi gọi `run_command` mới.** Biết trước lệnh nào nằm ngoài `allow` để chọn `read_file` thay vì làm bật popup duyệt quyền lắt nhắt cho người dùng.
2. **Tránh `|` trong tham số tìm kiếm `rg` ở môi trường có filter shell.** Muốn tìm vị trí hàm trong một file cụ thể, dùng `read_file` theo dải dòng nhanh và sạch hơn.
3. **Khi file lõi bridge bị khóa ghi (`deny`), tách module độc lập + tài liệu nối dây + issue-log.** Không cố lách quyền; đóng gói sạch logic, unit test, spec kỹ thuật để Agent PC review và gắn vào `server.ts`/`commands.ts` trong một lượt.
4. **Tách `collector` (TypeScript) khỏi `synthesizer` (`agy` ở `mode: 'plan'`).** Code TypeScript lo đọc log, redact token/ID; LLM chỉ nhận digest JSON đã làm sạch trong prompt nên không cần nới quyền đọc `~/.gemini/channels`.
5. **Cấm bắc cầu / suy đoán trạng thái runtime & mốc restart.** Mọi nhận định kiểu "bridge đã/chưa restart, đang chạy bản mới/cũ" bắt buộc phải dựa trên nhãn `[Bridge started: HH:mm DD/MM/YYYY (VNT)]` (hoặc `/status`, file/log đọc trực tiếp) hay xác nhận rõ của anh Hưng; thiếu bằng chứng thì nói thẳng "em chưa kiểm được", tuyệt đối không dùng "có thể / chắc là" để điền khuyết.

## Trạng thái hoàn tất (VERIFIED)

- Agent PC đã chạy `bun test` (`106 pass`), nối dây `/idea_miner` vào `commands.ts` + `server.ts`, vá `editor-readonly-settings.json` cho phép ghi `plan.md` ở `--mode plan`, lọc phiên tự nuốt/canary trong `collector.ts`, và bổ sung nhãn `Bridge started` vào `/status` + prompt `agy` + `buildTelegramInitialPrompt`.
