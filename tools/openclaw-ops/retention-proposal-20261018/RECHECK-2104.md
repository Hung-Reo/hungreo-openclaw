# Recheck backup versions và phần còn lại — 18/10/2026 21:04 VNT

Scope: read-only sau GO cleanup10GB đã hoàn thành. Không xóa/đổi retention thêm.

## Version thật

- Public package metadata live: shared runtime09/24=2026.9.6;10/03=2026.9.8;10/08-99=2026.9.9;10/18-933=2026.9.33.
- H/S active PIDs329781/327653 không đổi, NRestarts0; cả3readyz200.
- Script repo upgrade-933/99_rollback_933.sh ghi rõ target2026.9.9 và root99=/home/hung/openclaw-upgrade-20261008-99/runtime/node_modules/openclaw.
- Cặp serving/rollback được giữ là **9.33 / 9.9**, không phải9.3. Các runtime9.6/9.8 vẫn có trên đĩa vì Node/loader/refs, không coi là các bộ backup đầy đủ riêng.
- Runtime Nemo10.2/10.3/10.4 đều còn.

## Backup coverage quan trọng

| Bot     | Daily full gần nhất                      | Pre933                | Post933-plugin-cleanup |
| ------- | ---------------------------------------- | --------------------- | ---------------------- |
| Hungreo | 18/10 02:15,1.431GB,state.tgz+sqlite.tgz | 15:47,0.041GB,12files | 16:42,0.351GB,43files  |
| Suckhoe | 18/10 02:15,0.249GB,state.tgz+sqlite.tgz | 15:46,0.020GB,11files | 16:38,0.329GB,36files  |

Metadata-only inspection: pre933/post933 đều có canonical state snapshot; không có lcm.db, agent transcript SQLite hoặc fullstate archive. Vì vậy các bộ maintenance mới không tự thay daily fullbackup. Chưa thực hiện full rollback/restore boot trong audit này.
Full daily02:15 được tạo trước upgrade chiều, nên chưa xác nhận fullsnapshot của toàn state đang chạy9.33 sau nâng cấp.
Timer live: next daily **19/10 02:15 VNT**; next automated restore-check **25/10 03:00**. Đây là lịch đã kiểm, không tạo automation mới.

## Storage và ứng viên

Live df21:02: used74.946GB (73%), available27.925GB.
Backuproot hiện5.487GB. Không khuyên dọn thêm H/S recovery material trước khi có daily9.33 full và kiểmchecksum/thành phần/SQLite.

Ứng viên để xem sau, chưa SAFE-TO-DELETE:

- Nemo failed config1.341GB.
- Nemo oldops10.3 rehearsal/stage tổngtốiđa1.187GB; scripts/backup-pointer phải giữ.
- Nemo rollback10.2 cũ hơn predecessor10.3: runtime0.642GB + backup14/10 0.627GB + containerwritableước0.087GB; chỉ bỏ khi gói10.3 mới được chứng nhận đủ để thay.
- Hai ZIP Hermes cũ ~0.481GB; latestzip CRC PASS trước đó chưa là fullrestore chứng nhận.
  Các nhóm này ~4.37GB chưa tính mọi overhead/container rehearsal; không cộng vào dung lượng đã thu hồi10.14GB.

Giữ captures H1.047GB/S0.995GB/N0.522GB, Node/loader hiện hành, voice deps/cache models. Không tự thêm cleanup chỉ vì còn dung lượng.

## Giới hạn quyền đọc

Automatic review chặn đọc rộng backup.conf/CLI vì có thể chứa token. Đã bỏ cách đó, không retry/bypass; thay bằng public package.version, filepresence/size và mã rollback trong repo. Không xuất secrets/chat/DB values.
Checksum104của8bộ là bằng chứng cleanup17:12; không chạy lại fullhash toàn bộ21:04 vì kiểm này chỉ bổ sungversion/coverage, không có actiondelete mới.

Kết luận: giữ current9.33 + previous9.9 là hướng đúng, nhưng không nên gọi toàn bộ recovery đã đạt fullrestorePASS hoặc đã gộp còn1bộ. Ưu tiên full9.33 backup+verify và đúngretention1 trước đợt cleanup tiếp.
