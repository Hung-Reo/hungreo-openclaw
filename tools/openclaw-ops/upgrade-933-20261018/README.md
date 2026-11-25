# Nâng OpenClaw 2026.9.9 → 2026.9.33 (`extended-stable`) cho Suckhoe & Hungreo (2026-10-18)

## Phạm vi & Nguyên tắc

- **Mục tiêu:** Nâng `suckhoe` (Canary trước) và `hungreo` (sau) từ `openclaw@2026.9.9` lên `openclaw@2026.9.33` (`extended-stable` LTS), đồng bộ `@openclaw/codex@2026.9.33`, giữ nguyên `@martian-engineering/lossless-claw@1.1.1` và cấu hình model/auth/fallback/channel.
- **Bypass `#171446`:** Stage runtime độc lập tại `/home/hung/openclaw-upgrade-20261018-933/runtime` (integrity `sha512-gCwhh7Ej5/k4+/SzgHDi6HEHxw1ppDbIza3v6uSNa0JVB011m5YJ+AKmUbEFI0m4Au0pCRLK0ogL/GtUMDFMiw==`), không dùng `openclaw update` in-place từ driver `2026.9.9`.
- **Live-gates:** Giữ nguyên `patch-openclaw-plugin-binding-decline-fallback.test.mjs`, `verify-command-registry-98.mjs`, và `--import patch-binding-loader-hook.mjs`.

## Scripts

- `10_upgrade_933.sh <suckhoe|hungreo>`: Precheck → Stop gateway & healthcheck timer → Backup SQLite + config + drop-ins → Update `@openclaw/codex@2026.9.33` & relink peerDependencies → Cập nhật systemd drop-in + `/home/hung/bin/openclaw` + `/home/hung/bin/openclaw-healthcheck.sh` → Start & verify `/readyz` + `quick_check`.
- `99_rollback_933.sh <suckhoe|hungreo> <backup_dir>`: Khôi phục về `2026.9.9` nếu có sự cố.
