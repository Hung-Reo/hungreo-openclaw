# [2026-11-25] Bot Claude Telegram từ Mac lên VPS 24/7: setup-token không đủ cho Channels

**Loại:** claude-code, telegram, channels, vps, auth, sandbox, apparmor, cutover, cost-safety
**Làm bởi:** Claude Code (app PC), Hưng GO từng pha (A1, B, B5)
**Kết quả:** @hungreo_claude_bot chạy trên VPS bằng user `claudebot`, systemd `claude-collab.service`, đăng nhập claude.ai (Claude Pro). DM, group, Hermes `/collab` PASS 25/11 15:17–15:19.

## Kiến trúc hiện tại
- User Linux riêng `claudebot` (không sudo, không docker, không đọc `/home/hung`). Mọi service production vẫn ở user `hung`.
- `~/collab-hub/` = launcher + `collab-settings.json` (bản Linux) + `COLLAB_PROTOCOL.md` (có mục "Bản VPS") + `owner-gate.mjs`.
- `~/.config/systemd/user/claude-collab.service`: `ExecStart=/usr/bin/script -qfec <launcher> /dev/null`, `Restart=on-failure`, `MemoryMax=1536M`, enabled + linger.
- Plugin `telegram@claude-plugins-official` 0.0.7 + bản vá từ Mac (format, owner-gate, room-context, voice). Bản gốc ở `*.orig-upstream`.
- Mac: bot tắt, `~/collab-bot/MOVED-TO-VPS` chặn launcher Mac.
- Bundle, script, plan: `tools/openclaw-ops/claude-bot-vps-20261125/`.

## Bài học
1. **`claude setup-token` chỉ gọi được model.** Với `--channels`, phiên kẹt ở "waiting for your organization's policy… Messages are dropped" (đã chờ hơn 2 phút). Phải `claude auth login` (claude.ai, vẫn là subscription). Đăng nhập hết hạn khoảng 1 tháng (lần này khoảng 24/12/2026), cần đăng nhập lại.
2. **Copy token bị mất đầu lần thứ 2** (giống 17/11): file thiếu `sk-ant-oat01-`. Cách kiểm không lộ token: in prefix 12 ký tự + độ dài, rồi chạy 1 lệnh `claude -p` nhỏ (401 hay ok).
3. **Ubuntu 24.04 chặn bwrap** (`apparmor_restrict_unprivileged_userns=1`). Fix theo docs Claude Code: profile `/etc/apparmor.d/bwrap` có `userns,`. Không tắt sysctl toàn máy.
4. **`tmux new-session -d` trả về ngay**, systemd không thấy bot chết. Dùng `script -qfec` (cấp pty, thoát cùng `claude`). Test `kill -TERM` và `kill -9` đều tự restart, 1 poller.
5. **Lần chạy đầu có màn hình tương tác** (theme, security notes, trust folder). Phải qua 1 lần trong tmux trước khi giao cho systemd.
6. **Duyệt qua DM hoạt động trên VPS.** Bot được phép xin mở thêm quyền (ví dụ domain mạng) qua nút duyệt. Hưng Allow = GO cho lệnh đó. Đừng bật `sandbox.network.strictAllowlist`: mình đã bật, Hưng bảo là siết quá tay, đã gỡ.
7. **Cutover chống 2 poller:** tắt Mac + marker → kiểm không còn tiến trình → dừng bot test → thay token → bật VPS. Token thật Hưng tự dán bằng `read -rs`, agent không đọc.
8. Bot test = bot Telegram cũ của Nemo (@hungreo_bot). Revoke token cũ trước khi dùng, nên Nemo lỡ bật lại cũng không giành tin được.

## Vận hành nhanh (user claudebot)
```bash
# Hưng: sudo -iu claudebot   |   agent: ssh -i ~/.ssh/hostinger_kvm2 claudebot@<VPS_IP>
systemctl --user status claude-collab          # trạng thái
systemctl --user restart claude-collab         # restart = phiên MỚI (đọc lại protocol)
journalctl --user -u claude-collab -n 30       # log (TUI escape, khó đọc)
ls -t ~/.claude/projects/*/*.jsonl | head -1   # transcript (jq để đọc tool call)
~/.local/bin/claude auth status --text         # hạn đăng nhập
```

## Rollback
VPS `systemctl --user stop claude-collab && systemctl --user disable claude-collab` → Mac `rm ~/collab-bot/MOVED-TO-VPS` → chạy `mac-collab-hub-20261103/start-claude-collab.sh`.
Gỡ hẳn: `sudo bash ~/claude-bot-vps-20261125/99_b1_rollback_root.sh`.

## Còn mở
- Login hết khoảng 24/12/2026 → `sudo -iu claudebot` + `claude auth login`.
- Token setup-token thừa ở `~claudebot/.config/claude-collab/oauth`: thu hồi trên claude.ai rồi xoá file.
- Voice trên VPS (B6), git chung `collab-bot` + hộp thư `handoff/` (C1/C2) chưa làm.
- Bản vá plugin sẽ mất khi plugin tự cập nhật.
