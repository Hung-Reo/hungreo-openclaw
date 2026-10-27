# Nâng Nemo (`nemo-sandbox`) 2026.10.3 → 2026.10.4 (`latest`) (2026-10-18)

## Phạm vi

- **Mục tiêu:** Nâng `nemo-sandbox` từ `openclaw@2026.10.3` lên `openclaw@2026.10.4` (`latest`, integrity `sha512-+FH0StZF1tlTazM7JJGY6JePeJmhFNSRByi2Q3jXPRiLO7o4dJh2xa9Vy4Dk8Cd2ic8B7Zkf5NfEaCCWUkgqnQ==`), đồng bộ `@openclaw/codex@2026.10.4`, giữ nguyên `@martian-engineering/lossless-claw@1.1.1`.
- **Runtime:** `/home/hung/sandbox-nemo/runtime-10.4`.

## Scripts

- `20_cutover_10_4.sh`: Stop `nemo-sandbox` → Backup `config.tar` + `workspace.tar` → Update `@openclaw/codex@2026.10.4` → Đổi mount sang `runtime-10.4` → Verify `/readyz` (`:18796`) & SQLite `quick_check`.
- `99_rollback.sh [backup_dir]`: Khôi phục container và state về `2026.10.3`.
