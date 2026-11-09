# Bot Claude Telegram: chép voice bằng whisper local (ROOM-CHANGE-VOICE-20261109-01, 09/11/2026)

## Kết quả

- Plugin telegram 0.0.7 (cache + hub) có thêm `voice-{route,job,wav,pipeline,stt}.ts`; `server.ts` sha `69962a96…4f16` (Hermes V3/3 ĐẠT). Cờ `~/.claude/channels/telegram-collab/voice-transcribe.on` BẬT từ 11:17.
- whisper.cpp 1.9.5 (brew) + `ggml-large-v3-turbo-q5_0.bin` ở `~/.claude/channels/telegram-collab/voice/models/`. `-l vi`, không `--prompt`.
- UAT: Hưng xác nhận "UAT voice đạt" (group 493). Voice 479 "Hello, Cloud…" → wake `name_match:cloud`, notify sau ~4,5s, bot trả lời ~12s. Voice không gọi ai → chỉ room context.
- Backup: `~/.claude/channels/telegram-collab/voice-backup-20261109-pre-2b/`, `server.ts.bak-20261109-pre-voice` cạnh file. Rollback: xem `~/collab-bot/work/ROOM-CHANGE-VOICE-20261109-01-pha2b-result.md`.

## Bài học

1. **Đo trên giọng thật trước khi chốt luật.** TTS `say` ra "Wowde/Crude"; giọng Hưng ra "Cloud" ở cả `-l auto`/`-l vi`, `--prompt` không cứu. Luật v1c (tên đầu mệnh đề, phủ định, uncertain) làm voice gọi Claude không bao giờ tới. Hưng chọn luật đơn giản v1d: thấy tên/từ gần giống ở bất kỳ đâu là wake, Claude tự hiểu ngữ cảnh; giá là thêm lượt model.
2. **Mọi I/O mạng phải nằm trong đường huỷ.** v1 gọi `getFile` ngoài signal → treo là kẹt hàng đợi (Hermes V1). grammY 1.41.1 nhận `getFile(file_id, signal)`; kiểu khai bằng shim nên cần cast, nhưng runtime huỷ thật (đã test với server chậm). Thêm backstop `graceMs` để nhả lượt.
3. **Test handler thật, không chỉ hàm thuần.** Nạp `server.ts` thật trong bun test, `mock.module` cho grammy/MCP/sttVoice, đếm gate qua dòng stderr `collab_inbound_gate`, spy `RoomContext.prototype.prepare`. Chạy mutation (4 bản hỏng 1 dòng) để chứng minh bộ đếm không đếm suông.
4. **`mock.module` của bun là toàn tiến trình.** Chạy chung làm lây sang file test khác (88 test, 1 fail) → `run-tests.sh` chạy test handler ở tiến trình riêng.
5. **Handler voice không được await job dài.** grammY xử lý update tuần tự; await 10–90s sẽ chặn tin chữ.
6. **stderr của plugin không được lưu.** `~/Library/Caches/claude-cli-nodejs/<proj>/mcp-logs-plugin-telegram-telegram/*.jsonl` là log debug MCP của CLI (notification cắt ngắn, tool call), không có `collab_voice`. Đã nói nhầm với bot rồi đính chính.
7. **GO do bot chuyển không tính.** Pha 2a và 2b đều chờ Hưng gõ trực tiếp trên phiên PC; bước bật cờ nằm trong scope GO 2b (tin 443 mục 6).

## Follow-up (chưa làm, cần GO riêng)

- Lưu stderr `collab_voice` ra file log.
- Giữ hay gỡ gói brew cài kèm (`llama.cpp`, `ggml`, `libomp`, `openssl@4`) — Hưng quyết.
- Plugin telegram cập nhật sẽ mất patch (như patch format 07/11).
