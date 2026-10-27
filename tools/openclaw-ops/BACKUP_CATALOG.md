# Danh mục backup VPS — kiểm ngày 27/10/2026

Entry point cho các lượt rà backup/retention tiếp theo. Đây là **snapshot evidence**, không phải cấu hình retention hoặc quyền xóa. Báo cáo đầy đủ: [backup-review-20261027/REPORT.md](backup-review-20261027/REPORT.md).

## Quy tắc dùng lại

1. Đọc danh mục này và handover mới nhất, rồi kiểm live phần đã thay đổi. Không dùng ngày/tên thư mục để kết luận orphan.
2. Mỗi nhóm có vai trò riêng: daily data recovery, core rollback, plugin rollback, Node/config rollback, hoặc snapshot nghiệp vụ. Một bộ mới không mặc nhiên thay mọi nhóm.
3. Bộ giữ phải hoàn tất, checksum đúng và đủ thành phần. Phân biệt archive đọc được, SQLite integrity, isolated boot và UAT; không gộp thành một chữ PASS.
4. Chỉ đưa exact paths vào đợt cleanup sau khi có bộ thay thế, kiểm consumer/process/mount đủ quyền, kiểm không có job/agent bảo trì đồng thời và GO đúng scope.
5. Sau thay đổi: cập nhật bảng này, báo cáo theo ngày và handover; giữ lịch sử đợt cũ. Không tạo thêm skill/plugin cho cùng quy trình.

Các path dưới đây tương đối với `/home/hung/backups`, dung lượng allocated GiB (1024^3), không cộng với runtime/caches ở ngoài backup root.

| Nhóm                            | Path / generation                                                                         |        GiB | Vai trò và quyết định                                                                                                                                                                                                               |
| ------------------------------- | ----------------------------------------------------------------------------------------- | ---------: | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Daily H/S                       | `openclaw/{hungreo,suckhoe}/20261026-021528` và `20261027-021528`                         |       3.31 | KEEP cả 2 generation; default producer `RETENTION_KEEP=2`, effective environment override chưa audit. Bộ 27/10: 4/4 archive checksum PASS; JSON 2/2; critical SQLite 6/6 PASS trên scratch.                                         |
| KB companion                    | `openclaw/kb/20261013-*` đến `20261027-024001`                                            |      0.009 | KEEP; latest chứa KB, scripts, crontab. Chỉ kiểm thành phần, chưa verify checksum/restore bộ này.                                                                                                                                   |
| Core rollback H/S               | `openclaw-hungreo-pre934-20261026-193928`, `openclaw-suckhoe-pre934-20261026-192200`      |       1.96 | KEEP: snapshot core 9.33 trước 9.34. SHA 14/14 + 13/13 PASS; có canonical/agent/LCM DB và npm archive. Không phải snapshot current 9.34.                                                                                            |
| LCM rollback H/S                | `lcm-120-hungreo-20261025-142747`, `lcm-120-suckhoe-20261025-142410`                      |       0.79 | KEEP: trước plugin 1.2.0. Không tự coi pre934 (đã LCM 1.2.0) thay được rollback 1.1.1.                                                                                                                                              |
| Node rollback H/S               | `node-24221-hungreo-20261026-160355`, `node-24221-suckhoe-20261026-160024`                |      0.059 | KEEP: Node/config recovery; không phải full data backup.                                                                                                                                                                            |
| Nemo core rollback              | `nemo-10.5-20261021-203858`                                                               |      0.830 | KEEP cùng runtime/container 10.4 và recipe riêng; metadata check trong lượt này.                                                                                                                                                    |
| Nemo LCM rollback               | `nemo-lcm120-20261022-062251`                                                             |      0.895 | KEEP: plugin rollback riêng; metadata check, chưa rehash/restore trong lượt này.                                                                                                                                                    |
| Historical maintenance H/S      | Hai `openclaw-*-pre933-20261018-*` và hai `post933-cleanup-*-20261018-*`                  | 0 (đã xóa) | COMPLETED theo GO27/10 10:59:52. Net df thu hồi739,143,680bytes (~0.688GiB),10bộ giữ/66checksums và baseline PASS. [Kết quả](backup-cleanup-20261027/REPORT.md). Không chạy lạiapply hoặc dùngGO này xóa thêm.                      |
| Hermes 18/10 zips & Runtime 9.9 | 3 zip `~/.hermes/backups/pre-update-2026-10-18-*.zip` và `~/openclaw-upgrade-20261008-99` | 0 (đã xóa) | COMPLETED theo GO Đợt 1 27/10 13:57:44. Net df thu hồi 4,602,281,984 bytes (~4.60 GB), 18 bộ giữ (10 backup + 2 Hermes 25/10 + 2 voice models + 4 runtimes) 74 checksums PASS. [Kết quả](storage-reduce-batch1-20261027/REPORT.md). |
| Nghiệp vụ/embeddings            | `hungreo-embeddings-20261006`, `edu-memory-hungreo-20261023-093745`                       |      0.899 | HOLD: chưa chứng minh mất vai trò rollback nghiệp vụ.                                                                                                                                                                               |
| n8n / các snapshot nhỏ khác     | Các path còn lại                                                                          |          — | HOLD; không mở rộng đợt cleanup hiện tại.                                                                                                                                                                                           |

Runtime hiện hành và runtime rollback nằm ngoài root này, vẫn cần giữ: core 9.34 + Node 24.22.1, core 9.33 và Node/loader ngày cũ còn được service/recipe tham chiếu. Không dùng bảng backup để cho phép xóa runtime.

## Tools và lịch sử cần tái sử dụng

- [Skill vận hành](../../.agents/skills/openclaw-ops/SKILL.md): GO, stop-first, backup coverage, review độc lập.
- [Retention proposal 18/10](retention-proposal-20261018/PLAN.md) và [recheck coverage](retention-proposal-20261018/RECHECK-2104.md): lịch sử và bài học, phiên bản/path trong đó đã cũ.
- [Cleanup có bảo vệ 18/10](reclaim-10gb-20261018/README.md): tái sử dụng cơ chế exact allowlist/fingerprint/refs, **không chạy lại target hoặc GO cũ**.
- [Bài học coverage](../../kb/lessons/2026-10-18-maintenance-backup-coverage.md) và [recovery-set retention](../../kb/lessons/2026-10-18-one-recovery-set-retention.md).
- [Verifier daily 27/10](backup-review-20261027/verify_daily.py): exact generation, đọc backup + ghi scratch riêng, kiểm checksum/config/3 critical DB mỗi profile; không boot, không delete backup. Đổi generation phải review lại trước chạy.
- [Gói cleanup4backup27/10](backup-cleanup-20261027/README.md): đã audit/review/execute/verify theoGO, scope hoàn tất; tái sử dụng cơ chếguard cho đợt mới nhưng không chạy lạitarget/GOcũ.

Trên VPS đã có `~/bin/openclaw-backup.sh`, `openclaw-restore-check.sh`, `openclaw-prune-upgrade-backups.sh`. Script prune lựa chọn theo pattern/mtime và KEEP, không có bằng chứng nó hiểu recovery dependency của tất cả nhóm trong bảng. Không dùng nó thay exact allowlist chưa review.

Kiểm mã live bổ sung27/10: script prune mặc định dry-run, chỉ xóa khi `--yes`, và chỉ xét hai family `openclaw-upgrade-*` / `lcm-*upgrade-*`. Các tên `openclaw-*-pre933-*`, `post933-cleanup-*`, `openclaw-*-pre934-*`, `node-24221-*`, `lcm-120-*` không thuộc hai family này. Đây là khoảng trống cụ thể khiến snapshot theo sự kiện tiếp tục tích lại; không tự mở rộng glob hoặc sửa retention trong lượt audit.

## Vì sao còn phát sinh việc rà lại

Daily có default giữ 2 generation. Snapshot theo sự kiện (core/plugin/Node/maintenance/nghiệp vụ) thuộc nhiều producer và recipe khác nhau; chưa có bằng chứng một cơ chế live chung biết bộ nào thay bộ nào. Vì vậy số lượng tăng sau upgrade dù daily retention vẫn hoạt động. Danh mục này giúp giảm dò lịch sử; không loại bỏ nhu cầu kiểm live và không tự bật cleanup định kỳ.
