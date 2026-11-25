# Post-Upgrade 2026.9.33 Cleanup — Plugin Drift & Systemd Warnings (2026-10-18)

Bộ script thực hiện **Phương án 1** (sau khi `suckhoe` và `hungreo` đã nâng core lên `2026.9.33` + `lossless-claw@1.1.1`):

1. **Đồng bộ các plugin official từ `2026.9.8 → 2026.9.33`:**
   - `suckhoe`: `@openclaw/brave-plugin@2026.9.33`, `@openclaw/deepseek-provider@2026.9.33`
   - `hungreo`: `@openclaw/brave-plugin@2026.9.33`, `@openclaw/deepseek-provider@2026.9.33`, `@openclaw/parallel-plugin@2026.9.33`, `@openclaw/typesafe@2026.9.33`
2. **Xử lý 3 cảnh báo `Service config issue` của `openclaw gateway status --deep`:**
   - Dời file `~/.config/systemd/user/openclaw-gateway-<p>.service.bak` (mode `0664`, chứa inline `OPENCLAW_GATEWAY_TOKEN` từ tháng 04/2026) vào thư mục backup bảo mật `$B/systemd/` (mode `0600`, có `SHA256SUMS`).
   - Loại bỏ 4 đường dẫn version manager (`.volta`, `.asdf`, `.nvm`, `.fnm`) khỏi `Environment=PATH=` trong unit file và drop-in.
   - Đặt `KillMode=mixed` và `TimeoutStopSec=340`, chuẩn hoá quyền `0600` cho toàn bộ unit file và drop-in.

## Thứ tự chạy chuẩn (Stop-First, từng bot một)

1. `00_precheck.sh` — Kiểm tra read-only + `--dry-run` cho cả 2 bot.
2. `10_apply.sh suckhoe` → `20_verify.sh suckhoe` — Áp dụng và xác minh trên `suckhoe` trước.
3. `10_apply.sh hungreo` → `20_verify.sh hungreo` — Áp dụng và xác minh trên `hungreo`.
4. `99_rollback.sh <bot> <BACKUP_DIR>` — Rollback toàn vẹn nếu cần.
