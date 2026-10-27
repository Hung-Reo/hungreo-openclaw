# Đề xuất retention VPS — 18/10/2026

**Trạng thái: PROPOSAL ONLY. Hưng yêu cầu “chưa delete gì”. Không có lệnh xóa, không đổi script/timer/retention trên VPS.**

Scope Hưng giao: tiếp tục inventory backup, thử nghiệm Nemo, plugin captures; các bot khác hướng tới một bộ backup phiên bản gần nhất. Không lấy dự kiến OpenClaw sắp ra làm bằng chứng bỏ rollback.

## Chính sách đề xuất

1. Mỗi bot giữ **một bộ khôi phục gần nhất đã hoàn tất và kiểm chứng**. Một bộ có thể gồm nhiều archive + checksum + metadata phiên bản. File cấu hình mới nhất không tự là backup đầy đủ.
2. Runtime đang chạy và công cụ còn được service tham chiếu không tính là backup. Giữ chúng ngay cả khi tên thư mục có ngày cũ.
3. Với Nemo giữ runtime serving10.3 và một gói rollback10.2 duy nhất: backup config/workspace + runtime10.2 + container10.2 + scripts/backup-path. Đưa10.1/9.8 và rehearsal vào danh sách đề xuất loại bỏ.
4. Khi có backup mới: tạo xong → kiểm checksum/thành phần/SQLite nhất quán → chọn mới làm bộ giữ → mới bỏ bộ cũ. Backup mới lỗi không được làm mất bộ hợp lệ cũ.
5. Không áp retention một cách máy móc cho dữ liệu ngoài bộ bot, archive tài chính, VNStock, n8n, hoặc credential-recovery. Đối chiếu coverage trước; giữ nguyên hiện tại.
6. Retention chỉ là mục tiêu đề xuất. Producer daily vẫn KEEP=2 và weekly restore-check giữ nguyên. Không bật cleanup tự động.

## Bộ giữ được chọn

| Bot      | Bộ giữ đề xuất                                   | Allocated GB | Bằng chứng và giới hạn                                                                                     |
| -------- | ------------------------------------------------ | -----------: | ---------------------------------------------------------------------------------------------------------- |
| Hungreo  | backups/openclaw/hungreo/20261018-021528         |        1.431 | state.tgz + sqlite.tgz; hai checksum PASS; restore-check18/10 03:00 PASS                                   |
| Sức Khoẻ | backups/openclaw/suckhoe/20261018-021528         |        0.249 | state.tgz + sqlite.tgz; hai checksum PASS; restore-check18/10 03:00 PASS                                   |
| Hermes   | .hermes/backups/pre-update-2026-10-18-124844.zip |        0.241 | CRC PASS; 1480 members, 12 DB members, có config/auth/state-name coverage; chưa full isolated restore/boot |
| Nemo     | backups/nemo-10.3-lcm-20261014-212310            |        0.627 | config.tar + workspace.tar checksum PASS; backup-path hiện trỏ đúng bộ này; dùng rollback10.2              |

Các đường dẫn tương đối với /home/hung.

Lưu ý Nemo: bộ14/10 là snapshot **trước** nâng10.3, phục vụ rollback về10.2; không bao gồm dữ liệu phát sinh trên10.3 sau đó. Cron backup daily hiện chỉ có Hungreo/Suckhoe. Chưa chứng minh có recovery snapshot mới cho toàn bộ Nemo10.3. Dữ liệu serving được bảo vệ; trước một upgrade/cleanup có rủi ro sau này cần GO tạo snapshot nhất quán của trạng thái hiện tại, không dùng bộ rollback cũ thay backup dữ liệu mới.

Daily H/S không chứa npm/tmp: cần giữ runtime/plugin generation hiện hành hoặc pin package chính xác để khôi phục. RESTORE-NOTE hiện hướng dẫn update không pin target; không chạy nguyên dòng đó một cách mù quáng vì có thể đưa máy lên latest ngoài scope. Full boot restore chưa được chạy trong lượt này.

Trong probe member list, memory/main.sqlite không có ở hai daily archive, nhưng metadata live cũng cho thấy tên đang lưu là main.sqlite.migrated. Đây không tự là missing active store; canonical state/openclaw.sqlite, agent/openclaw-agent.sqlite, lcm.db và config đều có. Không mở nội dung DB/chat và không chứng nhận integrity của archive .migrated bằng quick_check.

KB/script/crontab có companion backup riêng backups/openclaw/kb/20261018-024001 (kb-shared.tgz, hungreo-scripts.tgz, crontab.txt). Không bỏ lịch sử KB trước khi xác minh bản companion mới có đủ phạm vi khôi phục. Một bộ khôi phục có thể gồm dữ liệu phụ trợ chung này.

## Danh sách ứng viên — chưa phải “đã an toàn để xóa”

Exact allowlist, bytes và gates nằm trong [manifest.json](./manifest.json). Không dùng wildcard để thực thi.

| Nhóm                                                              | Backup cũ / file thử đề xuất GB |
| ----------------------------------------------------------------- | ------------------------------: |
| Hungreo: daily17/10 + pre9.8/pre9.9/LCM1.1.0/embeddings cũ        |                           5.330 |
| Sức Khoẻ: daily17/10 + pre9.8/pre9.9/LCM1.1.0 cũ                  |                           1.674 |
| Nemo: backup cũ + runtime9.8/10.1 + failed-config/rehearsal/stage |                           5.947 |
| Hermes: hai zip10:18 và12:40, giữ zip12:48                        |                           0.481 |
| **Tổng allocated của ứng viên file, không overlap parent/child**  |                      **13.432** |

Docker: đề xuất sau này bỏ đúng ba container đang dừng nemo-rehearsal-103-lcm, nemo-sandbox-10.1, nemo-sandbox-9.8, cùng các bind paths ứng viên được duyệt. Tổng writable bytes Docker báo khoảng **0.211 GB**; logical accounting, chưa chứng minh lượng physical thực sự được thu hồi.

Vì vậy khoảng **13.43 GB file + 0.21 GB Docker** là upper estimate của danh sách đang xét, không là guaranteed reclaim. Không cộng runtime10.2, serving10.3, cache đang mount hoặc legacy Nemotron vào con số này.

## Bảo vệ bắt buộc

### Plugin captures: HOLD toàn bộ parent

- Hungreo PID1237 đang mở tree0d054beb…; tổng parent khoảng1.067 GB.
- Suckhoe PID1211 đang mở tree4ae86e51…; tổng parent khoảng0.995 GB.
- Nemo PID1422 tham chiếu /sandbox/config/tmp/plugin-captures/4bbb158f…; mount-normalized host parent khoảng0.522 GB.
- Các child native khác chưa chứng minh có thể bỏ. Tổng parent khoảng **2.584 GB** không đưa vào estimate.
- Không suy “tmp” hoặc “không có open fd” thành quyền xóa, vì runtime có thể lazy-load. Không restart chỉ để dọn capture trong scope này.

### Runtime ngày cũ vẫn đang dùng

- /home/hung/openclaw-upgrade-20260924: running executable Node của H/S resolve vào đây.
- /home/hung/openclaw-upgrade-20261003: service còn trỏ Node và patch-binding-loader-hook.mjs ở đây.
- /home/hung/openclaw-upgrade-20261008-99: serving core9.9.
- Do đó không xóa cả cây runtime cũ chỉ dựa ngày/tên version.
- Giữ Nemo runtime10.2/container10.2 làm rollback, runtime10.3/container serving, toàn bộ ops99_rollback.sh/backup-path và backup đang được trỏ.

### Nhóm chưa gộp/không thuộc allowlist

- .openclaw-nemotron legacy (~0.98GB): chưa xác minh coverage toàn bộ.
- Hermes state-snapshots (~0.179GB) là cơ chế quick-restore khác full zip, chưa chứng nhận có thể bỏ; installs đang chạy/được launcher tham chiếu cần audit trước.
- Các backup config/credential/manual bên trong profile và backup global nhỏ chưa chứng nhận superseded: HOLD, không mặc nhiên xóa.
- Giữ voice dependencies, shared caches, globalKB, finance records, VNStock, n8n/Caddy và mọi phần root-owned chưa audit.

## Điều kiện trước bất kỳ lượt thực thi sau này

- Hưng duyệt exact target delete; hiện tại chưa có GO.
- Re-read inventory và chọn lại latest completed set tại thời điểm chạy, không hardcode “18/10” mãi.
- Xác minh phần giữ đủ scope/phiên bản; đặc biệt latest Hermes còn thiếu restore/boot gate, failed-state Nemo cần kiểm không có dữ liệu riêng còn cần.
- Không backup/restore/update nào đang chạy; kiểm locks và consumers. Producer/consumer không được tự xóa giữ lại trái kế hoạch.
- Recheck process/cgroup, Docker mounts cả stopped containers, symlinks và service refs; không coi scan thiếu quyền root là toàn bộ.
- Bỏ container stopped liên quan trước khi bỏ bind directories được duyệt; không đụng runtime chung hoặc container10.2.
- Đo allocated/df trước–sau; filesystem/Docker accounting không cộng trùng.
- Retention producer thay KEEP=1 là thay đổi riêng phải kiểm failure path và giữ lại một bộ hợp lệ khi backup mới thất bại. Chưa sửa gì trong lượt này.

## Kiểm chứng và giới hạn

- SHA256 mới H/S bốn archive và Nemo hai archive: PASS.
- H/S restore-check18/10 03:00: hai profile ok, split_sqlite=true, cleaned_work_dir=true; service Result success.
- Latest Hermes ZIP CRC PASS, source backup.py xử lý SQLite qua backup API và loại sidecars. Không claim đã restore thành công.
- Quét metadata /proc đọc được154process;118fd directories không đọc được. Không match không có nghĩa chắc chắn unreferenced; Docker paths phải normalize theo bind mount.
- Full config_machine_state value query bị automatic approval review chặn do rủi ro lộ cấu hình; bỏ truy vấn đó. Tiếp tục bằng metadata, Docker mounts, archive checks; không retry gián tiếp hoặc xuất DB.
- Không chạy prune kể cả dry-run của script cũ: script dựa family/mtime, khác policy một bộ/bot. Không chạy restore/check script có tạo/xóa workspace; chỉ đọc receipt đã chạy trước.
- Không deploy/restart/model/auth/cron/send/cleanup; không commit/push. Chỉ ghi proposal/lesson/tracking local.
