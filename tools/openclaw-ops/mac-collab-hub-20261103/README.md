# Mac Collaboration Hub (`Hưng · Rùa · Hermes · Claude · Codex`)

> **Hiện trạng 07/11/2026:** bot Claude group chạy auto mode + sandbox trên `~/.local/bin/claude`, duyệt qua DM đã test. Không còn read-only; các mô tả stage cũ bên dưới là lịch sử. Xem `kb/lessons/2026-11-07-telegram-bot-auto-mode-dm-approval.md`.

> **Mac apply04/11 11:22:** room context/quote + protocol đã apply sau GO, cùng session resume với một poller và read-only guards; **UAT còn chờ Hưng**. Exporter mới local, chưa tự chuyển file/wake app PC. Mặc định đề xuất app PC Claude coder, bot Claude group read-only, Hermes reviewer; từng task do Hưng chốt. Xem [implementation report](../collab-setup-20261104/IMPLEMENTATION-REPORT.md), [apply result](../collab-setup-20261104/APPLIED-RESULT.json), [UAT](../collab-setup-20261104/UAT-SIMPLE.md). Không dùng mô tả stage cũ bên dưới để suy current runtime.

> **Current catch-up (03/11 20:29 VNT):** Native Hermes ↔ Claude canary PASS. Proven blocker: actual Hermes sender absent from current group allowFrom; fixed after owner GO. Shared issue `VPS-20261103-001` is monitoring. Read [verified report](REVIEW-FIX-20261103.md) and [lesson](../../../kb/lessons/2026-11-03-telegram-bot-to-bot-allowlist-and-message-ids.md) before using the historical stage/test descriptions below. Runtime has the reviewed 17-test patch; local replyPointerMeta follow-up has 18 tests and is not installed. Attachments are blocked in runtime. Real-task handoff and auth cleanup remain open.

Triển khai theo đúng lộ trình 3 giai đoạn của Rùa (`hungreo`) + 3 chốt chặn bảo mật của Claude (PC) ngày `2026-11-03`:
- **Giai đoạn 1 (Mặc định):** Phiên cộng tác Read-Only trên Mac (`allowBots: "none"`, Claude chạy `--permission-mode plan --disallowedTools Bash --setting-sources user --settings collab-settings.json`, Codex chạy `-s read-only -c sandbox_mode="read-only"` cho cả `exec` lẫn `exec resume`). Hưng gọi riêng từng bot trong nhóm Telegram thử nghiệm.
- **Giai đoạn 2:** Bật trao đổi Bot-to-Bot có điều phối cho Claude (`allowBots: "mentions"`, `botsRequireMention: true`, `BotLoopGuard` tối đa 2 vòng = 4 tin nhắn bot / 120s). Codex chỉ nhận lệnh từ người thật trong `allowFrom` (bot không được gọi Codex kể cả ở Giai đoạn 2).
- **Chốt an toàn:**
  1. Quyền duyệt công cụ (`yes xxxxx`) bị khóa cứng chỉ nhận từ **Private DM của Hưng** (`chat.type === 'private'` + `!from.is_bot` + `access.allowFrom`), tuyệt đối không nhận từ Group hoặc từ Bot khác.
  2. Không nạp `.claude/settings.local.json` của repo (`--setting-sources user`), áp `permissions.deny` chặt qua [`collab-settings.json`](file:///Users/hungdinh/Development/hungreo-openclaw/tools/openclaw-ops/mac-collab-hub-20261103/collab-settings.json), và đặt `telegram@claude-plugins-official = false` trong `~/.claude/settings.json` để phiên Claude thường không bị chạy ngầm plugin Telegram.
  3. Redact tự động các mẫu nhạy cảm (`-----BEGIN`, `sk-`, `ghp_`, Telegram bot token `\d{8,10}:[A-Za-z0-9_-]{35}`) trước khi `codex-telegram-bridge` gửi tin lên Telegram.

---

## 1. Cấu trúc thư mục

| File | Vai trò |
|---|---|
| [`lib/collab-gate.ts`](file:///Users/hungdinh/Development/hungreo-openclaw/tools/openclaw-ops/mac-collab-hub-20261103/lib/collab-gate.ts) | Bộ lọc bảo mật dùng chung: tách DM/Group, chặn bot duyệt quyền, ép `@mention`, `BotLoopGuard`, `evaluateCodexInboundGate`, `buildCodexExecArgs`, `redactSensitiveOutput`. |
| [`collab-settings.json`](file:///Users/hungdinh/Development/hungreo-openclaw/tools/openclaw-ops/mac-collab-hub-20261103/collab-settings.json) | Bật `telegram@claude-plugins-official` riêng cho phiên collab và áp `permissions.deny` (`~/.ssh/**`, `**/.env*`, `~/.claude/channels/**`, `~/.codex/**`, `ssh`, `scp`, `git push`). |
| [`test_gates.ts`](file:///Users/hungdinh/Development/hungreo-openclaw/tools/openclaw-ops/mac-collab-hub-20261103/test_gates.ts) | 14/14 unit tests kiểm chứng toàn bộ Gate, Loop Guard, Permission Isolation, Codex Args & Output Redaction. |
| [`test_canary.sh`](file:///Users/hungdinh/Development/hungreo-openclaw/tools/openclaw-ops/mac-collab-hub-20261103/test_canary.sh) | Canary test thực tế với `claude -p` và `codex exec` / `codex exec resume` trên `/tmp/collab-canary` và `/tmp/codex-canary`. |
| [`claude-telegram-plugin/server.ts`](file:///Users/hungdinh/Development/hungreo-openclaw/tools/openclaw-ops/mac-collab-hub-20261103/claude-telegram-plugin/server.ts) | Bản vá cứng của `telegram@claude-plugins-official` (`0.0.7`) tích hợp `collab-gate.ts`. |
| [`codex-telegram-bridge/server.ts`](file:///Users/hungdinh/Development/hungreo-openclaw/tools/openclaw-ops/mac-collab-hub-20261103/codex-telegram-bridge/server.ts) | Cầu nối Telegram cho Codex CLI trên Mac (`-s read-only -c sandbox_mode="read-only"`). |
| [`COLLAB_PROTOCOL.md`](file:///Users/hungdinh/Development/hungreo-openclaw/tools/openclaw-ops/mac-collab-hub-20261103/COLLAB_PROTOCOL.md) | Quy ước phân vai 5 thành viên và 3 nguyên tắc vận hành của Rùa. |
| [`00_check_mac.sh`](file:///Users/hungdinh/Development/hungreo-openclaw/tools/openclaw-ops/mac-collab-hub-20261103/00_check_mac.sh) | Kiểm tra binaries, global settings isolation, dry-run build, 14 unit tests và trạng thái cấu hình. |
| [`10_setup_access.sh`](file:///Users/hungdinh/Development/hungreo-openclaw/tools/openclaw-ops/mac-collab-hub-20261103/10_setup_access.sh) | Thiết lập `.env` & `access.json` (`0600`) ngoài git repo, hỗ trợ `--set-stage 1|2`. |
| [`start-claude-collab.sh`](file:///Users/hungdinh/Development/hungreo-openclaw/tools/openclaw-ops/mac-collab-hub-20261103/start-claude-collab.sh) | Mở phiên Claude Code cộng tác (`--setting-sources user --settings collab-settings.json --disallowedTools Bash`). |
| [`start-codex-collab.sh`](file:///Users/hungdinh/Development/hungreo-openclaw/tools/openclaw-ops/mac-collab-hub-20261103/start-codex-collab.sh) | Mở phiên Codex cộng tác (`read-only`). |
| [`start-gemini-collab.sh`](file:///Users/hungdinh/Development/hungreo-openclaw/tools/openclaw-ops/mac-collab-hub-20261103/start-gemini-collab.sh) | Mở cầu nối Telegram cho Antigravity CLI / Gemini (`@hungreo_gemini_bot`) trên Mac. |
| [`gemini-telegram-bridge/server.ts`](file:///Users/hungdinh/Development/hungreo-openclaw/tools/openclaw-ops/mac-collab-hub-20261103/gemini-telegram-bridge/server.ts) | Bridge Telegram ↔ `agy`: `/model`, `/status`, `/handover`, `/reset_thread`, duyệt quyền qua DM (`Allow 1 lần` vs `Luôn cho phép`) và cảnh báo/tự động handover theo ngưỡng token (`150K/225K/300K`). |
| [`99_rollback_mac.sh`](file:///Users/hungdinh/Development/hungreo-openclaw/tools/openclaw-ops/mac-collab-hub-20261103/99_rollback_mac.sh) | Khôi phục nguyên trạng `~/.claude/plugins/...` và `~/.claude/settings.json` từ các file backup `.bak-20261103`. |

---

## 2. Quy trình Handover theo tầng & theo dõi Context (`@hungreo_gemini_bot`)

- **Kiểm tra trực tiếp trên Telegram:**
  - Gõ `/status` để xem model hiện tại, số lượt, mức token so với ngưỡng auto (`300K` tokens · tiết kiệm quota) và trạng thái sức khoẻ phiên.
  - Bridge theo dõi ngưỡng token tuyệt đối (lưu watermark tại `~/.gemini/channels/telegram-collab/thread-stats.json` mode `0600`, tuỳ chỉnh qua `GEMINI_WARN_TOKENS` / `GEMINI_AUTO_HANDOVER_TOKENS`):
    - **Mốc `150K` & `225K` tokens:** gửi cảnh báo kèm nút bấm 1-chạm **`[🔄 Auto-Handover & Reset]`** (hoặc gõ `/handover`) để chủ động dọn phiên lúc rảnh.
    - **Mốc `≥ 300K` tokens:** tự động chạy quy trình handover 3 bước (tóm tắt phiên cũ → lưu backup `0600` tại `~/.gemini/channels/telegram-collab/handovers/<chatId>.md` & reset → nạp sang phiên mới) để tiết kiệm quota đọc lại ngữ cảnh.
- **Chốt fail-safe:**
  - Chỉ xoá phiên cũ sau khi bước tóm tắt thành công và đã ghi xong file backup `0600`; nếu bước tóm tắt lỗi, phiên cũ được giữ nguyên để không mất ngữ cảnh.
  - Duyệt quyền qua DM tách rõ **`✅ Allow (1 lần)`** (chạy 1 lượt bằng bản settings tạm `0600` rồi xoá ngay) và **`🔓 Luôn cho phép`** (mới ghi vào `gemini-collab-settings.json`).
