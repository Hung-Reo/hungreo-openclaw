# CUTOVER B5 — chuyển bot thật @hungreo_claude_bot từ Mac lên VPS — **DONE 25/11 15:16 VNT**

> Kết quả: DM, group và Hermes `/collab` đều PASS (15:17–15:19). Token test @hungreo_bot đã shred khỏi /home/hung/.secrets. Bot Mac khoá bằng `~/collab-bot/MOVED-TO-VPS`.

## Tiền đề đã đạt (VERIFIED 25/11)
- Bot test @hungreo_bot chạy trên VPS bằng user `claudebot`, systemd `claude-collab.service` (enabled, tự restart khi bị kill), đăng nhập claude.ai Claude Pro.
- Sandbox: không đọc được `/home/hung`, không docker, không systemctl của hung. Duyệt Deny/Allow qua DM đạt.
- Mac hiện tại: bot thật = phiên `claude` trong tab Terminal + plugin `bun` PID 16891 (`~/.claude/channels/telegram-collab/bot.pid`). **Không có LaunchAgent tự bật** (`com.hungreo.claude-collab.plist` chưa cài).

## Nguyên tắc
- Mỗi lúc chỉ 1 nơi poll token thật. Thứ tự là **tắt Mac → kiểm hết → bật VPS**. Rollback làm ngược lại.
- Token thật không đi qua chat hay qua agent. Hưng tự copy từ BotFather (`/mybots` → @hungreo_claude_bot → API Token, **không** bấm Revoke) rồi dán bằng `read -rs`.

## Các bước
| # | Ở đâu | Ai | Việc |
|---|---|---|---|
| 1 | Mac | Claude PC | Đồng bộ lại `~/collab-bot` (memory, handoff, skills) lên VPS, vì Mac có thể đã ghi thêm từ lần chép trước |
| 2 | Mac | Claude PC | Vá `start-claude-collab.sh` của Mac: có file `~/collab-bot/MOVED-TO-VPS` thì dừng, không mở bot (chống lỡ tay bật lại) |
| 3 | Mac | Claude PC | SIGTERM PID `claude` của bot và PID plugin trong `bot.pid`, tạo marker `MOVED-TO-VPS`. Kiểm `pgrep -af "telegram/0.0.7/server.ts"` = rỗng |
| 4 | VPS | Claude PC | `systemctl --user stop claude-collab` (đang chạy token test) |
| 5 | VPS | **Hưng** | `sudo -iu claudebot`, dán token thật bằng `read -rs` vào `~/.claude/channels/telegram-collab/.env` (600). Kiểm `getMe` = `hungreo_claude_bot` |
| 6 | VPS | Claude PC | Trả `access.json` bản Mac (có 2 group của phòng họp) để bot nhận lại group với Hermes |
| 7 | VPS | Claude PC | `systemctl --user start claude-collab`. Kiểm: 1 poller, không có `409 Conflict`, header `Claude Pro` |
| 8 | Telegram | **Hưng** | DM bot thật 1 câu. Trong group, gọi `@hungreo_claude_bot`. Nhờ Hermes gọi `/collab@hungreo_claude_bot` 1 lần |
| 9 | VPS | Claude PC | Xoá token test của @hungreo_bot (`/home/hung/.secrets/claude-collab-test`, bản của claudebot đã bị thay ở bước 5) |

Thời gian bot thật im lặng: khoảng 5 phút (bước 3 đến bước 7).

## Rollback (khoảng 1 phút)
1. VPS: `systemctl --user stop claude-collab && systemctl --user disable claude-collab` (user claudebot). Kiểm không còn `bun`.
2. Mac: `rm ~/collab-bot/MOVED-TO-VPS`, chạy lại `start-claude-collab.sh` trong Terminal như cũ (không cần `--resume`).
3. Telegram DM bot 1 câu để kiểm.

## Rủi ro còn lại
- **Đăng nhập claude.ai hết hạn khoảng 24/12/2026.** Bot sẽ ngừng trả lời. Cần nhắc Hưng `claude auth login` lại trước ngày đó.
- **Channels đang research preview.** Bot chết lúc có tin đến thì tin bị mất. systemd restart chỉ giảm thiểu.
- **Phiên mới, không `--resume`.** Bot VPS không nhớ hội thoại Telegram cũ, chỉ nhớ qua `~/collab-bot/memory`.
- **Voice tắt trên VPS** (chưa có whisper cho claudebot). Voice gửi tới bot sẽ không được chép. Làm ở B6.
- **Việc cần Mac** (SSH, deploy, Xcode) bot phải ghi handoff. Pha C (git `collab-bot`) chưa làm, nên tạm thời chuyền việc qua Hưng.
- Trong file protocol bản VPS vẫn còn nhắc tới `osascript` và đường dẫn Mac (không hại, chỉ thừa).
