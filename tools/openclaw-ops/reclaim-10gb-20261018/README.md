> **COMPLETED17:11 VNT:** thu hồi10.138669056GB theo df; xem REPORT.md và result.json.

# GO thu hồi khoảng10GB — 18/10/2026

User đã GO cleanup10GB, tạm chờ agent nâng cấp, sau đó xác nhận Antigravity hoàn tất và yêu cầu double-check rồi proceed. Không cần GO lại cho đúng scope này.

## Scope mới sau nâng cấp

Live trước cleanup: H/S9.33 (PIDs329781/327653), Nemo10.4 (PID310335); các readyz200, không có backup/restore job đang chạy.
Chỉ chọn14 exact directories trong targets.json: backup lịch sử và hai runtime Nemo9.8/10.1. Ước tính10.0069GB file allocated, thêm hai stopped container writable0.132GB.
Không dùng candidate13.43GB toàn bộ. Không đụng failed-state/rehearsal, plugin captures, Hermes, finance/VNStock, shared dependency/cache, runtime Node/loader đang dùng hoặc backup mới18/10.
Giữ Nemo runtime10.4 serving,10.3 rollback mới và cả10.2 rollback trước; giữ container tương ứng, backup-paths/scripts.

## Kiểm trước chạy

- Script audit là mặc định; execute cần audit cùng targets SHA không quá15phút.
- Giữ lại8bộ backup: H/S daily18/10 split state+SQLite, Nemo14/10 +18/10, H/S pre933 và post933-cleanup18/10. Kiểm SHA của mọi manifest member, không xuất data/config.
- Backup/restore jobs inactive; gateway PIDs/restarts/config hashes/version/mounts/timers/readiness phải nguyên.
- Bảo vệ symlink/parent/path/inode/metadata, đặc biệt rename dưới parent fd rồi dùng symlink-resistant rmtree. Không wildcard.
- Hai containers cần xóa phải stopped, ID khớp audit; docker rm không force.
- Fresh root process check trước từng delete: helper image đã có, networknone, read-only rootfs,64MiB/0.2CPU, chỉ hostproc metadata với SYS_PTRACE/DAC_READ_SEARCH, không mount hostroot, không đọc cmdline/environ/DB/config. Require0matches/0permissiondenials.
- Docker mounts cả stopped containers phải không phủ target sau khi bỏ đúng2container; hostmounts và activeunit/script references cũng chặn.
- Không chạy blanket prune, rm state/home, upgrade, service restart, model/auth/cron/send.
- Không đổi retention producer (hiện giữ2daily); chỉ thực hiện one-shot cleanup được GO. Các backup mới sau nâng cấp giữ nguyên để rollback chưa qua soak.

## Files / run

- 00_precheck.sh → cleanup.py audit, ghi audit.json private.
- 10_apply.sh → cleanup.py execute, ghi progress.json từng mục và result.json khi verify xong.
- 20_verify.sh → xác minh lại; không lặp delete.
- targets.json là exact allowlist.
- root_refs.js chỉ process metadata.
- test_guards.py: symlink target/parent, inode replacement, target content change, symlink escape và pending collision.
- Fresh-context independent reviewer APPROVE sau khi sửa2P1: mounts recheck trước/sau rename từng mục và pin required checksum artifacts cho8bộ.12local/VPS guardtests PASS; syntax Python/Node/Bash PASS.
- Lock là cooperative. Không có bảo đảm chống một actor khác cố ý mount sau lần kiểm cuối; operator đã xác nhận phiên upgrade hoàn tất. Chỉ chạy khi không có upgrade/backup/restore/mount song song.

## Failure / rollback boundary

Nếu lỗi trước rename: dừng, chưa xóa target đó.
Nếu lỗi sau rename: giữ \*.cleanup-20261018-pending để reconcile; không retry mù. Có thể đổi lại tên cũ sau khi kiểm inode/refs nếu chưa rmtree.
Nếu đã delete: snapshot lịch sử bị loại không có undo trực tiếp; latest retained backups/runtime vẫn còn để khôi phục dịch vụ hiện hành. Không giả vờ99rollback có thể tái tạo mọi snapshot đã xóa.
Không cần rollback live service vì cleanup không đổi config/runtime đang chạy. Không tự restore/restart nếu verify fail; báo exact phase và journal.

Report cuối phân biệtallocatedước tính/df net thực tế, thời điểm và giới hạn UAT.
