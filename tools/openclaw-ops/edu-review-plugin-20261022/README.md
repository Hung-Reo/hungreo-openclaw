# edu-review plugin cho hungreo (Rùa) — 22/10/2026

Plugin local duyệt phiếu research giáo dục qua Telegram. Code + test: `hungreo-super-app/tools/edu-review-plugin/`
(dùng chung `tools/edu-review/store.mjs`, `tools/research-card/validate.mjs`; `pack.sh` → bundle tự chứa + MANIFEST sha256).

## Trạng thái — DEPLOYED, smoke PASS (VERIFIED 22/10 19:53 VNT)

| Mốc         | Việc                                                                                                                                         | Kết quả                                                                                                                                                                            |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 18:47       | `10_apply.sh` lần 1                                                                                                                          | FAILED sau stop (2 `config set` riêng; dry-run thiếu extension) → `99_rollback.sh`, downtime ~2 phút, config về sha gốc                                                            |
| 18:53       | `10_apply.sh` sửa (1 `config patch`, dry-run có extension)                                                                                   | OK — plugin 0.1.1 loaded, downtime ~1 phút                                                                                                                                         |
| 19:04       | Smoke nút                                                                                                                                    | Nút `command` rơi xuống AI; gõ tay `/edu_review status` OK                                                                                                                         |
| 19:50       | `11_update_extension.sh` → 0.1.2 (nút callback + `registerInteractiveHandler` ns `edu`)                                                      | OK, config không đổi, downtime ~1 phút                                                                                                                                             |
| 19:53       | Hưng bấm Xem phiếu + Duyệt W43 v1                                                                                                            | `approved`, `approved/EDU-2026-W43_v1.md` có `reviewed_sha256`, không lượt AI                                                                                                      |
| 23/10 09:00 | `11_update_extension.sh` → 0.1.3 (fix F1–F4 review Codex: commit-first + reconcile, ingest idempotent, alerts bền, xác nhận đúng trạng thái) | OK, downtime ~1 phút, config không đổi, 20_verify PASS, DB Rùa `check` PASS                                                                                                        |
| 23/10 09:38 | `30_memory_extrapaths.sh` (GO-R): `extraPaths` += `kb/education/approved`, `memory index --force`                                            | Hot reload, không restart; 1066→1067 file, baseline search 4=4, truy vấn W43 ra đúng file approved. Backup `~/backups/edu-memory-hungreo-20261023-093745` (config + agent DB 531M) |

Model/fallback/slots không đổi (Sol 6.1 / Muse / lossless-claw); drift sessions 0.

## Thành phần trên VPS

- Extension: `~/.openclaw-hungreo/extensions/edu-review/` (0.1.3 từ 23/10 09:00); config `plugins.allow` + `plugins.entries["edu-review"]`.
- KB: `/home/hung/openclaw-shared/kb/education/` (inbox, review, state, approved, changes, rejected, invalid, logs, alerts).
- Poll inbox 300s; nhắn trong 07:30–21:30; nút callback `edu:<action>:<token>`; lệnh gõ tay `/edu_review …` dự phòng.
- Bundle: `~/edu-review-plugin-0.1.1/`, `0.1.2/`, `0.1.3/` (kèm log apply/update/rollback). Backup code 0.1.2: `~/backups/edu-review-ext-hungreo-*-085944`.

## Script

- `10_apply.sh hungreo <BUNDLE> [dry]` — cài lần đầu (allow + entry bằng 1 `config patch`), stop-first.
- `11_update_extension.sh hungreo <BUNDLE> [dry]` — thay code plugin, không đổi config, gửi lại phiếu pending.
- `20_verify.sh` — read-only.
- `12_rollback_extension.sh hungreo ~/backups/edu-review-ext-hungreo-<ts>` — trả code plugin cũ.
- `30_memory_extrapaths.sh hungreo [dry|apply|rollback <BACKUP_DIR>]` — GO-R: cho Rùa tra phiếu đã duyệt qua `memory_search`; rollback trả `extraPaths` cũ + reindex.
- `99_rollback.sh hungreo ~/backups/edu-review-hungreo-<ts> [delta|full] [force]` — gỡ hẳn plugin. Mặc định `delta`: một
  `config patch` chỉ bỏ `edu-review` khỏi allow + entries, giữ mọi thay đổi config khác. `full` chép lại cả file backup,
  chỉ chạy khi config hiện tại không lệch backup ngoài phạm vi edu-review/meta (hoặc `force`). (Sửa theo review Codex F5, 23/10.)
- 23/10: `11_update_extension.sh` xử lý KB rỗng/state hỏng trước khi stop (F6) và ABORT nếu không đặt lại được `notifiedAt` (F7);
  biến `EDU_KB_ROOT` chỉ để chạy harness local. Đã kiểm F5–F7 bằng harness có `systemctl`/`ss`/`journalctl` giả; chưa chạy trên VPS.
  Backup hiện hành: `edu-review-hungreo-20261022-185323` (trước khi cài), `edu-review-ext-hungreo-*` mới nhất (0.1.1).

## Việc mở

- GO-L: task theo lịch thêm `deliver.sh` (scp vào inbox).
- Ghi entry vào `SESSION_HANDOVER.md` + dòng index lesson: chưa ghi vì 2 file đang có WIP chưa commit của phiên khác.
- Cân nhắc áp dụng nút callback cho Suckhoe `/kb-review` (lesson 2026-10-11) — plan riêng.

Lesson: `kb/lessons/2026-10-22-edu-review-plugin-dryrun-and-command-buttons.md`.
