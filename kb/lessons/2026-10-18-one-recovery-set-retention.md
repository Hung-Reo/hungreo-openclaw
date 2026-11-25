# 18/10/2026 — Giữ một backup phải giữ một bộ khôi phục, không phải file mới nhất

Loại: retention, backup-coverage, runtime-reference, plugin-captures, approval-boundary

- Policy “giữ1” phải chọn latest completed verified recovery set; split state+SQLite, checksum và companion KB có thể cùng một bộ. File config mới nhất không thay full state.
- Chỉ prune sau khi bộ mới hoàn tất và kiểm chứng; backup mới fail phải giữ bộ cũ. Không đổi retention/cron trong task proposal “chưa delete”.
- Service core9.9 vẫn dùng Node/loader ở thư mục upgrade09/24 và10/03; tên cũ không đồng nghĩa orphan.
- Plugin captures có thể đang mở owner SQLite/native code. H/S/Nemo live đều có reference; tmp không tự là rác. Proc trong container dùng path /sandbox phải normalize theo mount.
- Read-only metadata không thấy refs chưa là chứng minh an toàn khi thiếu quyền root. Approval review chặn query cấu hình thì bỏ query và dùng evidence ít nhạy cảm hơn, không retry vòng.
- Estimate theo allowlist có điều kiện, không gọi là reclaim bảo đảm. Không cộng bind mount/Docker image nhiều lần, không tính khoản HOLD vào dung lượng hứa thu hồi.

Evidence: tools/openclaw-ops/retention-proposal-20261018/PLAN.md và manifest.json.
