# Nâng lossless-claw (LCM) 1.1.0 → 1.1.1 — Suckhoe trước, Hungreo sau (2026-10-15)

**GO:** Hưng 15/10 "nâng LCM 1.1.0 → 1.1.1 cho Suckhoe trước, sau là Hungreo, sao cho safe". Chỉ plugin; core giữ 2026.9.9.
**Ai chạy:** Claude chạy 00 + 20 (read-only); **Hưng chạy 10 (và 99 nếu cần)**, mỗi lần MỘT bot.

## Vì sao an toàn ở mức này (VERIFIED 15/10)

| Kiểm                                                                             | Kết quả                                                                                                                                                                  |
| -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Dry-run thật `plugins update @martian-engineering/lossless-claw@1.1.1 --dry-run` | Cả 2 bot: `Would update lossless-claw: 1.1.0 -> 1.1.1`, rc=0, config hash không đổi (`evidence/00_precheck.txt`)                                                         |
| Tương thích core                                                                 | 1.1.1 yêu cầu `minGatewayVersion 2026.9.2`; core đang 2026.9.9. Nemo chạy 1.1.1 trên 10.3 từ 14/10                                                                       |
| Migration `lcm.db`                                                               | Chỉ thêm 2 cột NULL `active_ordinal_start/end` vào `pending_summary_nodes` (`ALTER TABLE ADD COLUMN`), không xoá/sửa dữ liệu (diff v1.1.0…v1.1.1, `src/db/migration.ts`) |
| Quay về 1.1.0                                                                    | 1.1.0 INSERT bảng đó bằng danh sách cột tường minh → rollback mềm giữ DB được. Release note ghi `release-rollback-version: 1.1.0`                                        |
| DB hiện tại                                                                      | Suckhoe 92 MB, quick_check ok; Hungreo 579 MB, quick_check ok                                                                                                            |

Thay đổi hành vi cần biết: 1.1.1 có thể chạy **một lượt compaction tiền cảnh có giới hạn** khi context gần đầy (>75–90%) → lượt đó có thể chậm hơn vài giây; config không đặt `summaryModel` (VERIFIED) nên tóm tắt đi theo model của bot (Sol 6.1, gói ChatGPT) — ASSUMPTION theo thứ tự "Summary model resolution" trong docs LCM; cấu hình model không đổi so với 1.1.0, nên chi phí tóm tắt không đổi về provider.

## Rủi ro & chi phí

- **Downtime** ~1–3 phút mỗi bot (stop → backup → update → ready ~60s).
- **Giờ chạy (tránh job):** Suckhoe — nhắc thuốc **19:30**, tĩnh nguyện 04:10–06:45, heartbeat mỗi giờ; OAuth Suckhoe hết hạn **15/10 16:56** (đừng chạy sát giờ đó để không lẫn biến số). Hungreo — nhắc lịch **16:45 hôm nay**, 06:00, 07:00, heartbeat 2h.
- **Swap VPS gần đầy** (2039/2047 MiB): restart thực tế giải phóng swap của bot đó; không làm nặng thêm.
- **Disk** 25G trống; backup mỗi bot < 1 GB (Hungreo ~650 MB do lcm.db).
- Lỗi plugin sau update → bot vẫn lên nhưng LCM hỏng có thể làm lượt trả lời lỗi → UAT bắt buộc trước khi sang bot thứ 2.

## Các bước (Terminal trên Mac)

```bash
cd ~/Development/hungreo-openclaw/tools/openclaw-ops/lcm-111-20261015
```

| #         | Ai            | Lệnh                                                                                                                           | Kỳ vọng                                                                                              | Dừng nếu                                      |
| --------- | ------------- | ------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| 00        | Claude        | `00_precheck.sh` (đã chạy 12:08)                                                                                               | dry-run PASS 2 bot                                                                                   | —                                             |
| 10a       | **Hưng**      | `ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s suckhoe' < 10_upgrade.sh`                                             | `index: …@1.1.1`, `config changed keys: 0`, `ready`, `readyz: 200`, `OK 10 suckhoe`, dòng `BACKUP=…` | `FAILED`/`ABORT` → script in sẵn lệnh 99 hard |
| 20a       | Claude        | `20_verify.sh suckhoe`                                                                                                         | spec 1.1.1, quick_check ok, không lỗi lossless                                                       | —                                             |
| UAT       | **Hưng**      | Nhắn Suckhoe 1 câu thường + 1 câu hỏi lại chuyện cũ (vd "hôm trước mình hỏi về viêm gan B, bạn tóm lại giúp") ; gõ `/lossless` | Trả lời bình thường, nhớ được chuyện cũ; `/lossless` hiện DB + số summary                            | Trả lời lỗi/không nhớ → báo Claude            |
| —         | —             | **Chờ ≥ 24h** (qua nhắc thuốc 19:30 + tĩnh nguyện sáng)                                                                        | Claude chạy lại 20a                                                                                  |                                               |
| 10b       | **Hưng**      | `… 'bash -s hungreo' < 10_upgrade.sh`                                                                                          | như 10a                                                                                              | như 10a                                       |
| 20b + UAT | Claude + Hưng | như trên với Rùa                                                                                                               |                                                                                                      |                                               |

## Rollback

| Mức  | Khi nào                                   | Lệnh                                                                                                                                                           |
| ---- | ----------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| soft | Bot chạy nhưng LCM/trả lời có vấn đề      | `ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s <bot> soft' < 99_rollback.sh` — cài lại 1.1.0, giữ DB                                                 |
| hard | Script 10 dừng giữa chừng / bot không lên | `… 'bash -s <bot> hard <BACKUP_DIR>' < 99_rollback.sh` — khôi phục config + state + lcm.db + plugin từ backup; trạng thái hỏng cất vào `<BACKUP_DIR>/failed-*` |

Backup: `~/backups/lcm-111-<bot>-<giờ>/` — `openclaw.json`, `state/openclaw.sqlite*`, `lcm/lcm.db*`, `npm-lossless-1.1.0.tgz`, `SHA256SUMS`.

## What could still be wrong

- Rollback mềm/cứng **chưa chạy thử** trên VPS (chỉ đọc mã + dry-run). Nếu cần rollback, chạy dry-run soft trước là bước đầu của 99.
- 1.1.1 được upstream test với core 9.4/9.5, không phải 9.9; Nemo chạy 1.1.1 trên 10.3, không phải 9.9.
- Lượt đầu sau update có thể migrate DB lúc mở (2 cột) — nếu `pending_summary_nodes cols` chưa có `active_*` ngay sau start thì sẽ có ở lượt đầu.
