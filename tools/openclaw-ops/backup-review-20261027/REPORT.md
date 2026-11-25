# Backup review — 27/10/2026

> Bổ sung10:59:52: điểm thiếu quyền process đã được giải quyết; gói cleanup đã review/audit và **xóa đúng4backup18/10 theoGOHưng, verifyPASS**, netdf739,143,680bytes. Xem [report kết quả](../backup-cleanup-20261027/REPORT.md). Các đoạn CANDIDATE/HOLD bên dưới ghi lại bằng chứng trước khi đượcGO, không là trạng thái hiện tại hoặc quyền xóa thêm.

Scope: chỉ `/home/hung/backups`, xác minh recovery và soạn danh sách cleanup. Không xóa/rename backup, không thay retention/cron/config/service, không boot bot hoặc gọi model. Có ghi/xóa scratch riêng do verifier tạo, ưu tiên CPU/I/O thấp. Không xuất nội dung config/DB/secrets vào report.

## Kết quả

- Host `srv1367812`; backup root allocated **trong phạm vi du đọc được** `11,387,891,712` bytes = **10.606 GiB**. Đối soát sau cleanup xác nhận2thư mục finance ngoài scope không có quyền đọc, nên không coi đây là tổng coverage đầy đủ của root; net reclaim dùngdf.
- Daily job 27/10 02:15:28–02:18:49 VNT: Result success, exit 0.
- Daily H/S hiện giữ hai generation `20261026-021528`, `20261027-021528`. Default trong mã producer là `RETENTION_KEEP=2`; effective environment override chưa audit.
- Weekly restore-check gần nhất 25/10 03:00:28–03:02:51: success. Đây là evidence cũ, không chứng minh bộ 27/10.
- Kiểm mới bộ 27/10: 4/4 archive SHA256 PASS; full archive-member iteration trước đó không lỗi; JSON 2/2 hợp lệ. Trích riêng 3 DB/profile vào private scratch, quick_check 6/6 PASS, scratch_removed=true cả hai.
- Hai bộ pre934: manifest SHA256 H 14/14, S 13/13 PASS (lượt read-only trước, cùng ngày). Coverage có canonical, agent transcript, LCM, config, npm plugin archive, wrappers và drop-in liên quan.
- **Chưa chứng nhận isolated full-state restore/boot hoặc Telegram UAT từ backup.** Kiểm lần này không restore workspace, plugin native modules hay mọi DB phụ. Không chạy nguyên script weekly vì script đó còn cleanup scratch lịch sử của nó.

| Profile | LCM DB bytes | Agent DB bytes | Canonical DB bytes | quick_check |
| ------- | -----------: | -------------: | -----------------: | ----------- |
| Suckhoe |   96,645,120 |     48,693,248 |         20,717,568 | 3/3 ok      |
| Hungreo |  710,057,984 |    572,276,736 |         42,491,904 | 3/3 ok      |

## Exact proposal đợt 1 — chưa GO delete

Các path tương đối với `/home/hung/backups`:

| Path                                      | Allocated bytes | Vai trò cũ                                                 |
| ----------------------------------------- | --------------: | ---------------------------------------------------------- |
| `openclaw-hungreo-pre933-20261018-154744` |      41,005,056 | Maintenance trước core 9.33, phục vụ hướng rollback 9.9    |
| `openclaw-suckhoe-pre933-20261018-154622` |      19,668,992 | Maintenance trước core 9.33, phục vụ hướng rollback 9.9    |
| `post933-cleanup-hungreo-20261018-164201` |     350,892,032 | Config/canonical/plugin/systemd trước cleanup plugin 18/10 |
| `post933-cleanup-suckhoe-20261018-163847` |     329,175,040 | Config/canonical/plugin/systemd trước cleanup plugin 18/10 |
| **Tổng**                                  | **740,741,120** | **0.690 GiB / 0.741 GB, chưa phải reclaim thực tế**        |

Lý do chọn: H/S đã có hướng rollback core gần nhất về 9.33 bằng hai bộ pre934 và runtime 9.33; daily mới có config/state/transcript/LCM. Nếu Hưng chọn chỉ giữ hướng core rollback gần nhất, có thể đề xuất retire các maintenance recovery cũ này. **Không khẳng định các file lịch sử trùng byte hoặc mọi dữ liệu lịch sử đều tái tạo được.** Xóa là mất các snapshot thời điểm 18/10; không có undo trực tiếp.

Evidence tham chiếu:

- 4 target không là symlink khi kiểm; đã ghi inode trong output audit (không pin làm approval lâu dài).
- Direct-string scan `~/bin` và user systemd: 0 reference tới 4 exact paths. Chưa là phân tích mọi dynamic/glob consumer.
- Docker mount sources của cả running/stopped containers: 0 overlap.
- Process cùng uid: 0 match đọc được, **52 permission denials**. Không có root-wide clearance, chưa kiểm đầy đủ maps/root/cwd/fd mọi PID và host mount bên trong namespace.
- Backup/restore units inactive khi bắt đầu kiểm. Tình trạng phải được kiểm lại sát lúc thực thi.

**Trạng thái: CANDIDATE/HOLD.** Chưa đủ gate để xóa. Trước thực thi cần GO exact 4 paths; review độc lập gói cleanup dựa trên cơ chế guard sẵn có, consumer/host mount/process đủ quyền, kiểm giữ lại recovery sets và fingerprint mới. Không mở rộng sang LCM/Nemo/Node/finance/n8n/embeddings/edu-memory.

## Kiểm verifier

`verify_daily.py` đã review fresh-context bởi subagent role reviewer (`gpt-6.1-sol`, high): APPROVE, có giới hạn. Syntax PASS; synthetic checks PASS: valid archive + scratch cleanup; nonempty WAL rejected; duplicate critical DB rejected; checksum path escape rejected.

Lệnh đã chạy (stdin, không cài script vào VPS):

```sh
ssh -o BatchMode=yes -o ConnectTimeout=10 vps \
  'timeout 240s nice -n 19 ionice -c 3 python3 -u -' < verify_daily.py
```

Không chạy bằng Python optimized mode: guard hiện dùng assert. Nguồn backup phải hoàn tất/ổn định; script không có lock đồng bộ với mọi producer. Scratch limit 2 GiB/profile, yêu cầu >12 GiB free lúc bắt đầu; timeout ngoài 240s. Nếu bị kill cứng có thể còn scratch private, không tự broad-clean `/tmp`.

Tại 10:25 VNT process metadata audit không thấy target match đọc được. Health check trong lượt này: H PID 2749236, S PID 2940374, active/readyz200/NRestarts0. Suckhoe có start timestamp 27/10 10:19:17, khác snapshot 08:57; đây không phải restart do lượt audit này. Không điều tra task khác trong scope backup. Bộ daily02:15 không bao gồm thay đổi phát sinh sau thời điểm backup.

Kiểm sau cùng: audit scratch còn 0 thư mục; H/S PID/restart giữ như trên, readyz200. Disk trở về 80%, khoảng20GiB available sau khi dọn scratch. Không có dung lượng backup được reclaim trong lượt này.

## Điểm vào cho lần sau

[BACKUP_CATALOG.md](../BACKUP_CATALOG.md) là danh mục hiện hành; lịch sử guard/retention vẫn giữ ở thư mục ngày cũ. Sau mỗi upgrade/backup/cleanup phải cập nhật vai trò, bộ thay thế và ngày bằng chứng. Danh mục không tự cấp quyền cleanup và không chứa private config.
