# Nemo LCM 1.1.1 → 1.2.0 (canary cho Suckhoe/Rùa) — soạn 21/10, chạy tối 22/10

**GO:** Hưng 21/10 "Phương án 1: soạn script LCM 1.2.0 cho Nemo ngay bây giờ; tối 22/10 chạy 30_verify +24h, PASS thì nâng". Chỉ đổi plugin LCM trên Nemo; core giữ 2026.10.5, cùng container, không đổi model/auth/config. H/S/Hermes không đụng.

## Vì sao làm trên Nemo trước

LCM 1.2.0 đổi cách ingest: chỉ đọc phần transcript mới qua cursor, không đối chiếu lại cả transcript mỗi lượt. Đây là ứng viên giảm tải RSS cho Rùa (DB 636 MiB). Nemo là canary: kiểm plugin load được trên OpenClaw mới, migrate sang cursor mode, ghi gaps, không nhập trùng, recall qua `lcm_grep`, rollback mềm về 1.1.1 chạy được trên DB đã migrate. Nemo chỉ có ~146 msgs, 0 summary → **không** chứng minh được hiệu năng/compaction trên DB lớn; phần đó để rehearsal bản sao Rùa (PLAN `lcm-120-plan-20261021`).

## Điều kiện trước khi chạy (tối 22/10)

1. `30_verify.sh` của `nemo-upgrade-10.5-20261021` ở mốc +24h: restarts 0, OOM 0, app-server không tăng dần, 0 session-rebound, không lỗi lạ.
2. Issue tracker LCM chưa có regression nghiêm trọng cho 1.2.0 (kiểm 21/10 21:00: chưa có; chỉ #1255 có từ 1.1.1).
3. OAuth Nemo còn ≥48h (hạn 27/10 07:48Z).

## Các bước

| #   | Ai                    | Lệnh                                                                                                                                                                                                                              | Kỳ vọng                                                                                                                                                                                                                                                       |
| --- | --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0   | Hưng                  | `ssh … 'mkdir -p -m 700 /home/hung/sandbox-nemo/ops-lcm120-20261022'` rồi `scp -i ~/.ssh/hostinger_kvm2 16_rehearsal.sh 20_cutover.sh 30_verify.sh 99_rollback.sh hung@72.61.123.33:/home/hung/sandbox-nemo/ops-lcm120-20261022/` | Claude kiểm hash                                                                                                                                                                                                                                              |
| 16  | Hưng (nền, **1 lần**) | `ssh … 'setsid nohup bash /home/hung/sandbox-nemo/ops-lcm120-20261022/16_rehearsal.sh > /home/hung/sandbox-nemo/ops-lcm120-20261022/rehearsal.log 2>&1 < /dev/null &'`                                                            | `lcm-dryrun` báo 1.1.1→1.2.0, index bản sao 1.2.0, config không đổi, `BOOT_OK`, Nemo dừng ~4–6 phút, `TURN_OK default/recall`, log `cursor_mode_entered≥1`, `capability_error=0`, `LCM_120_INGEST_OK`, `ROLLBACK_SOFT_111_OK`, `NEMO_LIVE_RESTARTED`, `OK 16` |
| 20  | Hưng (nền, **1 lần**) | `ssh … 'setsid nohup bash /home/hung/sandbox-nemo/ops-lcm120-20261022/20_cutover.sh > /home/hung/sandbox-nemo/ops-lcm120-20261022/cutover.log 2>&1 < /dev/null &'`                                                                | `NEMO_BACKUP_OK`, `CONFIG_INDEX_SQLITE_GATES_OK lossless-claw=1.2.0`, `OK 20`; lỗi → tự rollback 1.1.1                                                                                                                                                        |
| UAT | Hưng                  | Chờ ~1 phút sau `OK 20`; nhắn Nemo 1 câu thường + 1 câu hỏi lại chuyện cũ                                                                                                                                                         | Trả lời bình thường; recall đúng                                                                                                                                                                                                                              |
| 30  | Claude                | `30_verify.sh` (thư mục này) ngay sau, +24h                                                                                                                                                                                       | lcm 1.2.0, cursors ≥1, dup 0, capability_error 0, quick_check ok                                                                                                                                                                                              |
| 99  | Hưng (nếu cần)        | `ssh … 'bash /home/hung/sandbox-nemo/ops-lcm120-20261022/99_rollback.sh <BACKUP_DIR>'`                                                                                                                                            | `OK 99 — ROLLBACK_LCM_111_READY`                                                                                                                                                                                                                              |

## Baseline trước nâng (VERIFIED 21/10 21:05, Nemo 10.5 + LCM 1.1.1)

RAM 1,61/2,5 GiB, memory.peak 2560 MiB (chạm trần từ khi start, OOM 0), app-server 2, LCM 146 msgs / 0 summary / dup 0, chưa có bảng cursor/gaps, agent DB v25, log 0 lỗi.

## Review opus 21/10 — đã sửa

- CHẶN 1: rehearsal ban đầu chỉ chạy session mới → conversation DM cũ (`agent:main:main`, 114+ msgs từ 1.1.1) chưa bao giờ phải resync sang cursor — đúng đường Prod sẽ đi ở tin đầu. Sửa: lượt recall chạy trên DM cũ; gate riêng: DM tăng 2–8 msgs, có cursor, conversation không đổi; tổng msgs ≤ +25.
- CHẶN 2 (có điều kiện): rollback tar trả lại kho OAuth cũ → nếu token đã tự refresh sau backup sẽ `refresh_token_reused`. Sửa: 20 gate OAuth ≥48h; 99 so hạn OAuth trước/sau, lệch → in "RE-AUTH NGAY".
- Phụ: 99 không khôi phục workspace (plugin update không đụng); marker chỉ ghi khi có lượt model; preflight slot/hook + disk ≥5G trước khi stop; rollback mềm [f] ghi rõ không phải đường Prod.

## Áp bài học từ 21/10

Chờ lease ≥100s trước mọi CLI · readyz ≠ agent sẵn sàng (turn tự thử lại 3 phút) · rehearsal cùng giới hạn RAM với live · đếm app-server qua `/proc` · boot rehearsal khi Nemo còn chạy, chỉ dừng Nemo ở pha lượt model · trap luôn bật lại Nemo · flock chống chạy chồng ở 20 · Hưng chỉ bấm lệnh nền 1 lần.

## What could still be wrong

- Nemo quá ít dữ liệu: migrate cursor trên DB lớn (Rùa) chưa được đo ở đây.
- Recall phụ thuộc model Muse có chịu gọi `lcm_grep` — ở 16 chỉ in ra, không làm gate cứng; UAT Telegram mới là gate.
- Rollback mềm 1.1.1 được thử trên bản sao; rollback thật dùng tar (cứng) — dữ liệu sau backup nằm ở `*.failed-lcm120-*`.
