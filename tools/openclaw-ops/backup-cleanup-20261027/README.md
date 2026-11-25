# Đợt 4 backup lịch sử — 27/10/2026

**COMPLETED27/10/2026 10:59:52 VNT — theo GO rõ của Hưng cho đúng4backup18/10. Thu hồi net739,143,680bytes theo df; verify PASS. Không chạy lại apply.** Xem [report](REPORT.md) và [result](result.json). Hướng dẫn bên dưới ghi lại quy trình đã dùng, không cấp quyền xóa thêm.

Scope duy nhất là 4 exact directories trong `targets.json`: hai pre933 và hai post933-cleanup ngày18/10. Tổng dự kiến740,741,120 bytes (0.690GiB), không bảo đảm df thu đúng số này. Không bỏ container, runtime, cache, model, LCM/Node/Nemo rollback hoặc đổi retention/cron/service.

## Cách dùng

- `00_precheck.sh`: audit ở ưu tiên CPU/I/O thấp; ghi audit.json private trong thư mục gói, không ghi/xóa backup. Kiểm health/runtime/config hashes, timer/job trạng thái, SHA mọi manifest member của10bộ giữ, fingerprint4target, script refs, mounts và root process metadata.
- `10_apply.sh <approved-targets-json-sha256>`: chỉ sau GO exact4paths, audit không quá15phút và mọi gate PASS. Đổi inode/content/runtime/config/checksum/mount hoặc thiếu quyền thì dừng. Chỉ xóa4target theo parent fd + rename và symlink-resistant rmtree. Không force-remove container; danh sách remove containers rỗng.
- `20_verify.sh`: chỉ verify sau execute, không lặp deletion.
- `test_guards.py`, `test_root_refs.cjs`: local synthetic guards, không dùng dữ liệu Production.

Gói này phát triển từ `../reclaim-10gb-20261018/`, đổi compiled allowlist, recovery sets, runtime9.34/10.5, fingerprint bổ sung nội dung file, pin engine/helper code và yêu cầu approved spec hash khi execute. **Không tái sử dụng authorization hoặc targets cũ.**

## Quyền đọc metadata

SSH user không có sudo non-interactive. Helper dùng image đã có và pin bằng imageID, không pull, `--network none`, read-only rootfs, `--pid host`, cap-dropALL rồi chỉ SYS_PTRACE/DAC_READ_SEARCH, no-new-privileges; giới hạn64MiB/0.2CPU/16PID. Hai file JS/spec được mount read-only từ gói này, không mount host root/backup/config. Helper chỉ đọc `/proc` maps/cwd/exe/root/fd/mountinfo/ns metadata, in tổng counts. Không đọc cmdline/environ, DB hoặc secrets.

Gate phải có0match,0mountmatch,0permissiondenial. Root scan xử lý cả tên pending và các mount namespaces quan sát được. Đây là container tạm tạo bởi audit, tự remove khi xong; không tác động container bot.

## Phạm vi an toàn và giới hạn

Lock gói là cooperative; không ngăn mọi agent/producer khác. Không cleanup khi có bảo trì/upgrade/backup/restore khác. Recheck service state và root refs trước từng delete, mounts trước/sau rename. Chưa bảo đảm chống một actor cố ý race mount/process giữa các phép kiểm. Nếu lỗi sau rename, giữ exact `*.cleanup-20261027-pending` để reconcile; không retry mù.

SHA audit/review không tự là quyền xóa. Xóa các snapshot lịch sử là mất snapshot18/10, không có undo trực tiếp; giữ core9.33 và pre934 để rollback gần nhất, không còn hứa giữ mọi hướng recovery9.9.

Audit source có thể đọc các filebackup để tínhhash nhưng chỉ xuất tên component/checksum/state metadata; không đưa raw config hoặc DB vào report/Git. Kết quả audit private trên VPS cần lọc trước khi đưa về repo public.
