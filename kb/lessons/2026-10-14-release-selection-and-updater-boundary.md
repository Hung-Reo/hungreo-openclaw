# 14/10/2026 — Chọn release theo lỗi thực tế và giới hạn updater

Loại: release-research, version-pinning, updater, canary, memory, evidence-freshness

VERIFIED upstream: npm stable 10.3 mới phát hành tối 13/10; 10.1/10.2/10.3 published 11/12/13 tháng 10. Có fix catalog native plugin giữ graph trùng (#169272), nhưng không cam kết chữa mọi memory growth. Issues #171096 (Linux/NAS SQLite update rollback) và #171311 (--no-restart vẫn restart trên macOS) open khi kiểm 14/10; chưa tái hiện ở VPS Hưng. SSH hôm nay bị publickey refusal, nên VPS 13/10 là PRIOR-EVIDENCE.

Rules:

- Đọc trực tiếp npm dist-tags/time + release tag + notes + report regression; search index/“minutes ago” không đủ chốt latest/ngày phát hành. Beta mới hơn stable không có nghĩa nên chọn beta.
- Tách fix trong target package khỏi khả năng updater cũ đưa máy vào target: một số fixes cần updater đã chứa fix. Không tin --no-restart thay stop-first/isolation của runtime/state.
- Match triệu chứng với phạm vi patch: fix một path ESM retention không chứng minh toàn bộ cảnh báo RSS là cùng lỗi. Canary reset baseline khi đổi candidate.
- Stable là kênh phát hành, không là chứng nhận cho DB/plugin/custom workload của mình. Trailing extended-stable không cho phép downgrade DB live tuỳ ý.
- Khi live auth bị từ chối, báo UNVERIFIED; tiếp tục research public và tracking, không sửa access hoặc tô snapshot cũ thành current.

Chi tiết và nguồn: SESSION_HANDOVER.md entry 2026-10-14.
