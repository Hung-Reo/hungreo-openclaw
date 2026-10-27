# GO cleanup khoảng10GB — VERIFIED 18/10/2026

## Kết quả

Hưng GO thu hồi10GB, yêu cầu chờ Antigravity upgrade xong; sau đó xác nhận đã hoàn tất và cho tiếp tục. Live core đã double-check H/S9.33, Nemo10.4. Không nâng cấp/restart hay đổi model/auth/cron trong cleanup này.

- Completed **17:11:30 VNT**, postcheck **17:12:33 VNT**.
- df used trước **85.362089984 GB**, sau **75.223420928 GB**.
- **Thu hồi net thực tế10.138669056 GB = khoảng9.44 GiB** theo df.
- Postcheck hệ thống tiếp tục ghi nhẹ: used75.225075712 GB, available **27.646242816 GB**, use **74%** (trước khoảng83%).
- Đã bỏ đúng **14directory allowlist +2stopped containers** nemo-sandbox-9.8 và nemo-sandbox-10.1.
- Không còn pending rename. Không chạy blanket prune.

## Đã bảo vệ và kiểm

- **8bộ backup giữ lại,104checksum manifest members PASS** sau cleanup; required artifacts được yêu cầu có checksum riêng và hash đúng, manifest SHA được pin.
- Giữ H/S daily18/10, pre933 + post933-cleanup mới18/10; Nemo backup14/10 và10.4 pre-cutover18/10.
- Giữ serving runtime9.33/10.4, Node/loader cũ đang được service dùng, Nemo rollback runtimes/containers10.3 và10.2.
- Giữ plugin captures, dữ liệu live, cache/model/dependencies, failed/rehearsal state, legacyNemotron, Hermes và các backup chưa đủ gate.
- PIDs giữ nguyên: Hungreo329781, Suckhoe327653, Hermes268895, Nemo310335. NRestarts H/S/Hermes0; protected Docker identities/started/mounts/restart counters nguyên.
- openclaw.json hashes H/S/Nemo không đổi. Cả3readyz200; timers backup/restore/healthcheck active nguyên.
- Log unit từ baseline đến postcheck: không match out-of-memory/oom-kill/secrets-degraded/uncaught-exception. Đây là unit logs trong cửa sổ này, không là xác nhận lịch sử toàn host hoặc Telegram UAT.

## Guard và review

- Exact allowlist trong targets.json; compiled allowlist chống thay manifest ngoài scope; reject overlapping parents.
- **12tests local +12tests VPS PASS**: symlink target/parent, inode replacement, content changes, symlink escape, pending collision, corrupted retained data, manifest escape, missing required checksum, unapproved target, mount-after-rename và Docker mount-order.
- Fresh-context reviewer gpt-6.1-sol/high: APPROVE sau khi sửa2P1 (mount recheck từng delete trước/sau rename, checksum required coverage) và normalize thứ tự mounts.
- Mỗi target được recheck mounts/identity; root process metadata scan qua network-none/read-only helper hiện hữu image, hạn mức64MiB/0.2CPU, **0matches/0permissiondenials** trước từng delete.
- Chỉ process maps/fd/cwd/exe/root metadata; không đọc cmdline/environ hoặc xuất Production DB/config values. Không mount hostroot.
- Cooperative lock và operator-confirmed no concurrent upgrade. Không tuyên bố loại bỏ race với một actor cố ý mount sau final check.

## Lần dừng bảo vệ trước thực thi

Lần apply đầu **dừng trước mọi xóa** vì Docker inspect trả cùng mounts theo thứ tự khác, gây false drift.
Đối chiếu cho thấy PID/config/version/checksums nguyên, progress chưa có. Sửa sort nguồn mounts, thêm regression test; review lại APPROVE, re-audit mới rồi thực thi.
audit-before-mount-sort.json và audit/progress/result private giữ trên VPS để truy vết, không đưa config hashes/raw backup vào Git.

## Giới hạn / việc chưa làm

- Storage targets dùng sum st_blocks để ước lượng có thể trùng hardlinks; báo cáo thu hồi lấy **df net**, không lấy estimate.
- Cleanup loại snapshot lịch sử; không có undo trực tiếp từng bản đã bỏ. Latest retained recovery material/runtime vẫn còn; không chạy restore boot/Telegram UAT trong lượt này.
- Chỉ one-shot cleanup; **retention producer daily vẫn2**, chưa thay cron/timer/script retention. Các backup mới trước/sau nâng cấp đang giữ để rollback; chưa gộp còn1bộ tự động giữa thời gian soak.
- Không đụng phần root-owned storage chưa audit, Hermes zip cũ hoặc các candidate còn điều kiện chỉ để đạt13.43GB.
- Không commit/push/branch switch/stash/reset, giữ WIP. Chỉ thêm script/report và tracking local.

Evidence public đã lọc: result.json, review.json. Private task: /home/hung/.openclaw-ops/reclaim-10gb-20261018.
