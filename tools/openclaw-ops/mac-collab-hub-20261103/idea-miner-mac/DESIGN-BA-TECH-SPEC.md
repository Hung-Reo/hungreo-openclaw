# `idea-miner-mac` — BA Context, Architecture Plan & Technical Spec

> **Ngày lập:** 2026-11-14 (phiên Mac `@hungreo_gemini_bot`, nền commit `3df4972a64`)  
> **Đối tượng đọc:** Anh Hưng (Product/BA Owner) & Agent PC (Claude Code / Codex) để review, nối dây vào `gemini-telegram-bridge`, chạy test và tinh chỉnh.

---

## 1. Bối cảnh BA & Quyết định đã chốt

### Nguồn gốc yêu cầu
- Anh Hưng chia sẻ bài của Garry Tan về GBrain / `idea-miner` (*recursive self-improvement* cho personal agent) và hỏi tính ứng dụng cho hệ cộng tác hiện tại.
- Hai bên thống nhất **không dựng thêm Postgres/GBrain** và **không cho AI tự sửa rules/skills ngầm** (giữ nguyên Alignment Rule #3: *Agent đề xuất → Hưng GO → Mới ghi*).
- Anh Hưng chọn **Cách B** (tự động định kỳ + lệnh DM chạy thử giống `/x_brief`) với các tham số chốt ở phiên `2026-11-14`:
  1. **Lịch gửi tự động:** **Sáng Thứ 2 hàng tuần** — chọn khung **`07:30–07:59` (`Asia/Ho_Chi_Minh`)** để tránh đụng `06:30` (X Brief Mac) và `07:00` (Rùa X watch).
  2. **Tên lệnh DM chạy thử:** **`/idea_miner`** (chữ thường theo chuẩn Telegram `^[a-z0-9_]{1,32}$`).
  3. **Lưu trữ dài hạn cho liên-Agent:** Tài liệu BA, Plan, Spec kỹ thuật và Issue-Log nằm cùng module trong repo (`idea-miner-mac/` + `kb/lessons/`).

### Mục tiêu đầu ra (đọc ~30 giây trên Telegram)
1. **💡 Ý tưởng của anh ("What to build next" — tối đa 2 mục):** nhặt lại ý tưởng sản phẩm/quy trình anh từng nêu trong tuần, giữ nguyên *lý do gốc ("why")*, kèm 1 bước kiểm chứng nhỏ nhất (`< 1 ngày`) và nguồn phiên.
2. **🛠️ Đề xuất Skill / Rule cho Bot (tối đa 2 mục):** lọc các điểm anh phải nhắc/sửa hoặc lỗi lặp (`2+ lần`), soạn sẵn bản nháp cập nhật quy tắc/skill *(luôn ở trạng thái chờ anh GO)*.
3. **🩺 Điểm nghẽn tuần qua (1–2 dòng):** thống kê ma sát kỹ thuật (denial/error/dead-end) + gợi ý gọn.

---

## 2. Ranh giới bảo mật & lý do tách 2 pha (Mac tạo module, PC nối bridge)

Theo commit **`3df4972a64`** (`gemini-collab-settings.json`), bot Mac bị **hard-deny** ghi trực tiếp vào toàn bộ lõi `gemini-telegram-bridge/` (`server.ts`, `commands.ts`, `permissions.ts`, `handover.ts`, …) và `editor-readonly-settings.json`.

**Thiết kế 2 lớp để giữ nguyên tường bảo mật:**
1. **Trusted Collector (Bun/TypeScript trong `collector.ts`):** đọc giới hạn 7 ngày gần nhất từ:
   - `STATE_DIR/handovers/*.md`
   - `~/.gemini/antigravity-cli/brain/*/.system_generated/logs/transcript.jsonl`
   - `kb/lessons/*.md` (để tránh đề xuất trùng bài học đã ghi)
   Mọi chuỗi trích xuất đều đi qua `redactSensitiveOutput()` + mask số ID dài `8–13` chữ số (`[ID]`) trước khi đưa vào `digest.json`.
2. **Read-Only LLM Synthesis (`agy` ở `mode: 'plan'` + `x-brief-mac/editor-readonly-settings.json`):**
   - LLM **chỉ nhận JSON digest đã làm sạch trong prompt**; không cần quyền đọc `~/.gemini/channels` hay gọi shell.
   - Kiểm tra `hasPermissionDenial(agyRes)`; nếu có hoặc JSON lỗi → rơi về `buildDeterministicFallbackReport()` (gắn nhãn `fallback-summary`).

---

## 3. Cấu trúc module đã tạo (`idea-miner-mac/`)

| File | Trách nhiệm | Ghi chú |
|---|---|---|
| `types.ts` | Kiểu dữ liệu `WeeklyDigest`, `IdeaMinerReport`, `RunIdeaMinerResult` | Union type rõ ràng cho collect/skip/deliver |
| `collector.ts` | Quét giới hạn 7 ngày (`handovers`, `transcript.jsonl`, `kb/lessons`), redact & tính ISO week `YYYY-Www` | Bỏ qua `HANDOVER_AUTO` noise & dòng JSON lỗi |
| `prompt.ts` | `buildIdeaMinerPrompt`, `parseAndValidateIdeaMinerOutput`, `buildDeterministicFallbackReport` | Giới hạn cứng tối đa 2 ideas, 2 skill proposals |
| `formatter.ts` | `formatIdeaMinerTelegramMessage` | Giống phong cách `x-brief-mac`, ghi rõ `Mode: plan (chỉ đọc) · 0đ API` |
| `scheduler.ts` | `shouldTriggerWeeklyMiner`, `startIdeaMinerScheduler` | Thứ 2 `07:30–07:59 VNT`, chống bắn đúp theo `lastAttemptWeekKey` (`0600`) |
| `runner.ts` | `runIdeaMinerPipeline` | Lưu `digest.json`, `report.json`, `report.md` (`0600`) dưới `STATE_DIR/idea-miner/runs/` |
| `cli.ts` | CLI độc lập (`--dry-run`, `--test`, `--scheduled`, `--send`, `--no-agy`) | Dùng `mode: 'plan'`, `dangerouslySkipPermissions: false`, `editor-readonly-settings.json` |
| `idea-miner.test.ts` | Unit test lịch Thứ 2, collector/redaction, parser/fallback, runner idempotency, CLI security | Không chứa ID/token thật |

---

## 4. Hướng dẫn nối dây cho Agent PC (vì `server.ts` & `commands.ts` khóa ghi từ Mac)

> **Lưu ý:** `gemini-telegram-bridge/commands.test.ts` kiểm tra `GEMINI_BOT_COMMANDS` khớp 1-1 với các `bot.command(...)` trong `server.ts`. Cần sửa cả 2 file cùng lúc.

### Bước 1 — `gemini-telegram-bridge/commands.ts`
Thêm `{ command: 'idea_miner', description: 'Tổng hợp ý tưởng & retro tuần qua' }` vào `GEMINI_BOT_COMMANDS`.

### Bước 2 — `gemini-telegram-bridge/server.ts`
1. Import từ `../idea-miner-mac/runner.ts` và `../idea-miner-mac/scheduler.ts`:
   - `runIdeaMinerPipeline`
   - `startIdeaMinerScheduler`
2. Khai báo biến module cạnh `xBriefRunning` / `xBriefScheduler`:
   - `let ideaMinerRunning = false`
   - `let ideaMinerScheduler: { stop: () => void } | undefined`
   - `BRAIN_DIR = process.env.ANTIGRAVITY_BRAIN_DIR ?? join(homedir(), '.gemini', 'antigravity-cli', 'brain')`
   - `KB_LESSONS_DIR = process.env.KB_LESSONS_DIR ?? join(WORKSPACE_DIR, 'kb', 'lessons')`
3. Thêm helper `runAndDeliverIdeaMiner({ mode, targetChatIds, replyToMsgId })` theo đúng mẫu `runAndDeliverXBrief`:
   - Dùng `X_BRIEF_READONLY_SETTINGS_FILE`, `mode: 'plan'`, `dangerouslySkipPermissions: false`, kiểm `hasPermissionDenial(agyRes)`.
   - Khi `mode === 'scheduled'` mà `!res.ok`, ném lỗi để `scheduler.ts` ghi `lastStatus: 'error'`.
4. Thêm `bot.command('idea_miner', ...)` (allowlist human DM giống `bot.command('x_brief', ...)`, chạy `mode: 'test'`).
5. Trong `onStart`: khởi động `ideaMinerScheduler = startIdeaMinerScheduler({ statePath: join(STATE_DIR, 'idea-miner', 'schedule-state.json'), targetWeekday: 'Mon', targetHour: 7, targetMinute: 30, ... })`.
6. Trong `shutdown()`: gọi `ideaMinerScheduler?.stop()` ngay cạnh `xBriefScheduler?.stop()`.

### Bước 3 — Xác minh trên PC trước khi restart bridge
1. Chạy `bun test tools/openclaw-ops/mac-collab-hub-20261103` (bao gồm `idea-miner.test.ts`, `commands.test.ts`, `x-brief.test.ts`, `permissions.test.ts`).
2. Chạy dry-run không cần `agy`: `bun tools/openclaw-ops/mac-collab-hub-20261103/idea-miner-mac/cli.ts --dry-run`.
3. Chạy thử có `agy` (chưa gửi Telegram): `bun tools/openclaw-ops/mac-collab-hub-20261103/idea-miner-mac/cli.ts --test`.
4. Xin anh Hưng **GO** restart bridge; test `/idea_miner` trực tiếp trên Telegram DM.

### Rollback
- Gỡ phần nối trong `commands.ts` / `server.ts` (hoặc `git revert` commit nối dây); thư mục `idea-miner-mac/` hoàn toàn độc lập, không ảnh hưởng vòng lặp chat hay `x-brief-mac`.
