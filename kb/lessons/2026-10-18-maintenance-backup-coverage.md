# 18/10/2026 — Backup maintenance không tự thay full-state backup

Loại: backup-coverage, rollback-version, canonical-state, lcm, transcript, retention

Recheck21:04VNT: H/S serving9.33, rollbackruntime+script9.9, không phải9.3. Daily full gần nhất02:15 trước upgrade; pre933/post933-cleanup chỉ có canonical/config/plugin/systemd recovery, không cóLCM+transcript/fullstate archive.
Rule: version liền trước còn trên đĩa và SHA PASS chưa đủ gọi là fullrollback được chứng nhận. Trước khi consolidate backup, phân biệt runtimeversion, dailydata snapshot, maintenance backup và restore recipe; chọn đủ thành phần thay thế.
Backupfull sau upgrade + verify là bước ưu tiên trước cleanup hồi phục thêm. Không suy “backup mới nhất” = “đầy đủ nhất”.

Evidence: tools/openclaw-ops/retention-proposal-20261018/RECHECK-2104.md.
