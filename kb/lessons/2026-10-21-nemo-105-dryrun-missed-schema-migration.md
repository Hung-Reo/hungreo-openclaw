# 21/10/2026 — Nemo 10.4 → 10.5: dry-run PASS nhưng gateway không lên vì phải migrate schema DB agent

Loại: upgrade, nemo, docker, dry-run-gap, sqlite-schema, doctor, rollback-ok

VERIFIED (`tools/openclaw-ops/nemo-upgrade-10.5-20261021/`, backup `~/backups/nemo-10.5-20261021-125528`):

- Dry-run lần 1 FAIL cả 4 lệnh vì bản sao config mang theo lease `state_leases(gateway-owner)` có heartbeat còn mới. CLI 10.5 chạy ở PID namespace khác từ chối khi heartbeat < 90s; 10.4 chưa có kiểm tra này. Sửa: chỉ đọc DB, chờ lease cũ ≥100s. Sau khi sửa, dry-run PASS.
- Cutover 12:55: stop, backup, codex 10.5, config/SQLite gate đều PASS. Container 10.5 thoát với mã 78 (lặp 16 lần), báo `openclaw-agent.sqlite uses schema version 24; stop active agents and run openclaw doctor --fix to migrate session identities`. ERR trap gọi `99_rollback` → 10.4 ready 13:00:59 (gián đoạn ~5,5 phút), codex 10.4, LCM 1.1.1, quick_check ok, H/S/Hermes không bị đụng.

Lesson:

- `config validate` + `plugins inspect/update --dry-run` không kiểm schema DB của bản mới. Dry-run nâng core phải gồm cả `doctor --lint` (read-only) trên bản sao, cộng một lần **khởi động gateway thử trên bản sao** (transport/cron OFF, không cổng host). Lý do: gateway mới có thể bắt migrate DB trước khi chạy, như 10.4→10.5.
- Rollback tự động (ERR trap → 99) đã được mô phỏng trước bằng docker giả, nên lần này chạy thật đúng. Phải giữ bước mô phỏng này cho mọi script cutover.
- Với 10.5, migrate (`doctor --fix`/`--repair`) đổi schema DB một chiều → rollback chỉ an toàn nếu khôi phục được từ tar backup chụp lúc stop. Không chạy migrate trên live khi chưa thử trên bản sao.

Cập nhật 21/10 20:56 — kết thúc: DEPLOYED + UAT PASS.

- `doctor --non-interactive` (safe migrations) bị refuse ở bước `session-entry-state` ("required") → chỉ `doctor --fix` mới migrate được, và kéo theo repair khác (bật plugin openai/perplexity, nâng plugin, tắt skill không dùng được). Gate theo allowlist khoá config + GO riêng cho từng thay đổi ngoài phạm vi.
- `readyz` 200 ≠ bot trả lời được: agent còn "startup inspection" ~25–40s (integrity gate do lease doctor để lại). UAT phải chờ sau readyz.
- Rehearsal phải chạy với đúng giới hạn RAM của live; 1,5 GiB gây OOM giả. Đo bằng cgroup `memory.peak`.
- Image node slim không có `ps` → `ps | grep -c` luôn 0 mà không báo lỗi; đếm process qua `/proc/*/cmdline`. Kiểm công cụ đo trước khi tin số 0.
- Lệnh nền (`setsid nohup … &`) dễ bị chạy 2 lần từ terminal; script phải tự chặn chạy chồng (kiểm thư mục làm việc/trạng thái trước khi ghi) — đã chặn đúng 2 lần.
