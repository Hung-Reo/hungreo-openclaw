# 18/10/2026 — Cleanup sau upgrade phải rebase baseline, pin đủ checksum và normalize mounts

Loại: storage-cleanup, post-upgrade, checksum-coverage, docker-inspect-order, process-reference

- User GO10GB vẫn có hiệu lực sau chờ upgrade, nhưng allowlist/baseline phải đọc lại runtime/backup mới. Không dùng version/PID từ audit trước nâng cấp làm trạng thái hiện tại.
- Checksum manifest có vài dòng PASS chưa đủ: required state/sqlite/config artifacts phải có entry được hash; pin manifest SHA và coverage. Giữ mọi bộ rollback mới khi nâng cấp vừa xong.
- Docker inspect Mounts là collection không có thứ tự ổn định. So sánh normalized sorted sources, vẫn bắt source/identity/started changes. Regression test đảo order PASS, đổi source phải khác.
- Kiểm host/Docker mounts sát mỗi delete trước và sau rename; root process metadata0matches/0denials. Rename+pin inode+symlink-resistant rmtree giữ pending nếu failure, không retry mù.
- Exact14dir+2stopped containers đã thu hồi10.138669056GB theo df, dịch vụ/config/timers nguyên. Estimate st_blocks có thể overcount hardlinks; lấy df net làm kết quả.
- One-shot cleanup không tự đổi retention producer hoặc chứng minh Telegram/full restore UAT; không hứa an toàn tuyệt đối và không xóa thêm để gom mọi candidate.

Evidence: tools/openclaw-ops/reclaim-10gb-20261018/REPORT.md.
