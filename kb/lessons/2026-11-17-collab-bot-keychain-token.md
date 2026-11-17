# Bot Claude trên Mac không lên: Keychain chưa có token, rồi lưu token hỏng 3 lần (17/11/2026)

Loại: auth | claude-code | telegram | keychain | launcher | cost-safety

## Kết quả

- 17/11 khoảng 15:15, `start-claude-collab.sh` dừng với dòng "Không có token subscription (Keychain claude-collab-oauth hoặc Claude Desktop)". Guard có sẵn làm đúng việc: không chạy bằng API key.
- 17:26 Hưng lưu được token đúng (108 ký tự, `sk-ant-oat01-…`). 17:27:40 bot lên PID 57463, `--resume` giữ phiên `85ae33cb-…`, có `CLAUDE_CODE_OAUTH_TOKEN`, không có `ANTHROPIC_API_KEY`, đúng 1 poller Telegram (VERIFIED). Ngữ cảnh còn nguyên: bot nhắc lại lịch hẹn cũ.
- Guardrail mới trong launcher: token trong Keychain phải khớp `^sk-ant-oat01-[A-Za-z0-9_-]{80,}$`, sai thì dừng hẳn (không rơi sang fallback Desktop). Backup: `tools/openclaw-ops/mac-collab-hub-20261103/start-claude-collab.sh.bak-20261117-pre-token-guard`.

## Chuỗi nguyên nhân (VERIFIED)

1. Mục Keychain `claude-collab-oauth` chưa từng được tạo. Launcher sống nhờ fallback mượn `CLAUDE_CODE_OAUTH_TOKEN` từ tiến trình `claude-code/<ver>/.../MacOS/claude` của Desktop. Tiến trình đó chỉ có khi đang mở một phiên Code tab; lúc 15:15 chưa có (phiên Desktop bắt đầu 15:17:14).
2. `claude setup-token` báo `command not found`: `claude` không nằm trong PATH, phải gõ `~/.local/bin/claude`.
3. Ba lần lưu token hỏng:
   - Lần 1: `security add-generic-password ... -w` khi chưa có token → lưu chuỗi 13 ký tự. Launcher chấp nhận và chạy bot với token này (chỉ kiểm "khác rỗng").
   - Lần 2: dán mã xác nhận trên trình duyệt (220 ký tự) thay vì token in ra ở Terminal.
   - Lần 3: token bị Terminal ngắt 2 dòng, copy chỉ lấy dòng sau → 95 ký tự, đúng đuôi, thiếu `sk-ant-oat01-`.
4. Hai lần lệnh không ghi gì: `add-generic-password` không có `-U` thì không ghi đè mục cũ; lệnh chạy ở ô `!` của app Claude không có TTY nên hộp thoại `osascript` và `read -rs` không nhận được dữ liệu dán.
5. Tiến trình cũ PID 8581 (token 13 ký tự) đứng ở màn hình hỏi tin thư mục, chưa mở poller. Chọn "Yes" ở đó sẽ ra poller thứ hai.

## Bài học

1. **Guard "khác rỗng" chưa đủ cho secret.** Kiểm cả dạng (tiền tố, độ dài) và dừng hẳn khi sai, đừng để giá trị hỏng chạy tiếp hay rơi sang đường khác.
2. **Lưu token trong app Terminal của macOS**, không ở ô `!` của app Claude. Dùng lệnh có kiểm dạng và `-U`:
   ```bash
   read -rs "T?Token: "; echo; case "$T" in sk-ant-oat01-*) security add-generic-password -U -s claude-collab-oauth -a "$USER" -w "$T" && echo "OK len=${#T}";; *) echo "SAI: không bắt đầu bằng sk-ant-oat01- (len=${#T})";; esac; unset T
   ```
   Kết quả đúng: `OK len=108`. Kéo cửa sổ Terminal rộng để token nằm trên một dòng trước khi copy.
3. **Kiểm token không in giá trị:** chỉ in độ dài, kiểm tiền tố, và so vài ký tự đầu/cuối với bản Hưng đã che. Không nhờ ai dán token vào chat.
4. **`claude auth status` với `CLAUDE_CODE_OAUTH_TOKEN` chỉ đọc biến**, `loggedIn: true` không chứng minh token dùng được. Không thử gọi model thật để kiểm khi máy còn khoá API (`apiKeySource: /login managed key`): chưa rõ token hỏng có làm CLI rơi sang khoá đó không (UNVERIFIED).
5. **Sau khi bot lên:** `sessionId` trong `~/.claude/sessions/<pid>.json` đúng phiên cũ; đúng 1 tiến trình `claude-plugins-official/telegram/*/server.ts`; tên biến có OAuth, không có API key; đóng tiến trình cũ còn kẹt ở màn hình hỏi.
6. **Token `setup-token` có hạn 1 năm**, khoảng 17/11/2027. Thu hồi tại claude.ai/settings/claude-code.

## Cách kiểm nhanh khi gặp lại (read-only)

```bash
security find-generic-password -s claude-collab-oauth -a "$USER" -w | python3 -c 'import sys;v=sys.stdin.read().strip();print(len(v), v.startswith("sk-ant-oat01-"))'
pgrep -af 'claude.*-n telegram-collab-claude' | awk '{print $1}'
pgrep -f 'claude-plugins-official/telegram/.*/server.ts' | wc -l
```
