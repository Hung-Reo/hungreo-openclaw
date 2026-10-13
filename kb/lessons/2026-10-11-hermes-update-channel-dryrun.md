# 11/10/2026 — Hermes upgrade v0.21.6: dry-run không thử kênh, gateway tắt vô ích

Loại: upgrade, hermes, dry-run-gap, release-channel, stop-first

VERIFIED: script `tools/openclaw-ops/hermes-upgrade-v0216-20261011/10_upgrade.sh` dừng gateway 13:50:37 rồi chạy
`hermes update --channel stable --backup --yes --no-gateway-restart`. Updater bản 819cc3c (2026.9.24) tra kênh qua
`releases/channels/stable.json` trên kho phát hành Nous và **không có fallback GitHub** (`hermes_cli/source_releases.py`);
file đó không tồn tại → `ChannelNotFound`, exit 1, không áp gì. Code/config giữ nguyên (commit, hash khớp), Hưng start lại
13:52:00 — Hermes offline ~80 giây. Release note v0.21.6 có thật (08/10), nhưng tính năng "source install mặc định theo stable"
chỉ có SAU v0.21.6 (chính báo cáo cron của Hermes đã cảnh báo).

Lesson: dry-run phải chạy đúng bước có thể hỏng, không chỉ `--plan`. Với Hermes: `hermes update --check --channel <x>` (đọc,
không tắt gateway) trước khi stop. Cảnh báo trong báo cáo của chính agent ("updater cũ, channel chưa chắc") là tín hiệu phải
thử bằng lệnh đọc trước. Upgrade agent tự nâng chính nó: không để agent tự chạy (restart cắt lượt đang làm) — Claude soạn, Hưng chạy.

Quyết định: Hưng hoãn tới v0.22.0 (bản vá bảo mật v0.21.6 không chạm máy này: Dashboard không mở cổng ngoài, Email gateway tắt).
Backup 4.1G tạo cho lần này đã xoá 12/10 (`storage-cleanup-20261011`) vì không có thay đổi nào cần rollback.
