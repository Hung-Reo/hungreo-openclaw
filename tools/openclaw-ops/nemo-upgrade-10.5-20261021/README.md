# Nemo 2026.10.4 → 2026.10.5 (21/10/2026) — chỉ Nemo

**GO:** Hưng 21/10: "Proceed cho Nemo only, giữ hungreo và suckhoe". Core + plugin `@openclaw/codex` lên 10.5. **Giữ LCM 1.1.1** để mỗi lần chỉ đổi 1 biến; LCM 1.2.0 làm sau theo `lcm-120-plan-20261021/PLAN.md`. Không đổi model, auth, fallback, config ngoài plugin codex, cũng không đụng H/S/Hermes.

## Bằng chứng trước khi soạn (VERIFIED 21/10)

- npm: `latest = 2026.10.5`, integrity `sha512-9rCu…zHg==`; `@openclaw/codex@2026.10.5` có (peer `openclaw >=2026.10.5`); node cần ≥24.16 (image 24.21.0).
- Nemo hiện tại: 10.4, Up từ 18/10, 0 restart/OOM, 1,15/2,5 GiB, pids 63, codex app-server = 0, 5 inbound/3 ngày (dùng ít → soak chỉ cho tín hiệu yếu).
- Issue 10.5 đáng chú ý:
  - #178804 P1: codex app-server tích tụ khi bật `sessionCatalog` → `30_verify` đếm app-server; config Nemo không đặt sessionCatalog, nên `15_dryrun` in mặc định của 10.5 ra để biết.
  - #178608: rotate transcript generation khi có commentary media làm context-engine `session-rebound` → `30_verify` đếm `session-rebound`.
  - Nhiều issue "Update failure" (P0/P2) nằm ở đường `openclaw update`/`/update` tích hợp. **Không dùng đường đó**; cách ở đây là stage runtime riêng rồi đổi container, giống 10.2→10.4.

## Các bước

| #   | Ai             | Lệnh                                                                                                                                                                                                                                                                                                                                   | Kỳ vọng / dừng nếu                                                                                                                                                                                                   |
| --- | -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0   | Hưng           | `scp -i ~/.ssh/hostinger_kvm2 *.sh hung@72.61.123.33:/home/hung/sandbox-nemo/ops-10.5-20261021/` (trước đó `ssh … 'mkdir -p -m 700 /home/hung/sandbox-nemo/ops-10.5-20261021'`)                                                                                                                                                        | —                                                                                                                                                                                                                    |
| 10  | Hưng           | `ssh … 'bash /home/hung/sandbox-nemo/ops-10.5-20261021/10_stage.sh'`                                                                                                                                                                                                                                                                   | `OK 10`, ~600M runtime mới; Nemo live không bị đụng                                                                                                                                                                  |
| 15  | Hưng           | `ssh … 'bash …/15_dryrun.sh'`                                                                                                                                                                                                                                                                                                          | 4 dòng PASS + `OK 15`. FAIL → dừng, gửi Claude                                                                                                                                                                       |
| 16  | Hưng           | `ssh … 'bash /home/hung/sandbox-nemo/ops-10.5-20261021/16_rehearsal.sh'` (~5–8 phút; Nemo live vẫn chạy)                                                                                                                                                                                                                               | gate OAuth ≥48h, `MIGRATE_OK agent_db_user_version=≥25`, doctor không đổi 8 mục cốt lõi, `BOOT_OK`, `TURN_OK`, `OK 16`. Thêm sau sự cố 12:55: bước 20 chỉ chạy khi có marker 16 PASS <24h và openclaw.json không đổi |
| 20  | Hưng           | `ssh … 'setsid nohup bash /home/hung/sandbox-nemo/ops-10.5-20261021/20_cutover.sh > /home/hung/sandbox-nemo/ops-10.5-20261021/cutover.log 2>&1 < /dev/null &'` rồi `ssh … 'tail -n 50 -f /home/hung/sandbox-nemo/ops-10.5-20261021/cutover.log'` (Ctrl-C khi thấy `OK 20` hoặc `OK 99`) — chạy nền để SSH rớt không làm script chết dở | `NEMO_BACKUP_OK`, `CONFIG_AND_SQLITE_GATES_OK`, `OK 20`; lỗi giữa chừng → tự rollback 10.4                                                                                                                           |
| UAT | Hưng           | Telegram Nemo: 1 câu thường + 1 câu hỏi lại chuyện cũ                                                                                                                                                                                                                                                                                  | Trả lời bình thường                                                                                                                                                                                                  |
| 30  | Claude         | `30_verify.sh` ngay sau, rồi +24h, +48h                                                                                                                                                                                                                                                                                                | core 10.5, codex 10.5, LCM 1.1.1, app-server không tăng dần, 0 session-rebound, H/S/Hermes PID không đổi                                                                                                             |
| 99  | Hưng (nếu cần) | `ssh … 'bash …/99_rollback.sh <BACKUP_DIR>'`                                                                                                                                                                                                                                                                                           | `OK 99 — ROLLBACK_10_4_READY`                                                                                                                                                                                        |

Baseline trước nâng: chạy `30_verify.sh` lúc 21/10 10:54 (số liệu ở trên).

## Rủi ro / chi phí

- Downtime Nemo khoảng 4–7 phút: phải chờ lease `gateway-owner` cũ ≥100s rồi mới chạy được CLI 10.5 (xem dưới). Disk +~0,6G runtime +~0,9G backup (còn 24G). RAM: container tạm 1,3G lúc update plugin; script chặn nếu RAM available < 1,2–1,5G.
- Rollback khôi phục snapshot lúc stop. Tin phát sinh sau đó được cất ở `config.failed-10.5-*`.
- Không có chi phí model mới (model và route giữ nguyên).

## Sự cố dry-run lần 1 (21/10 ~11:25) — đã sửa

`15_dryrun` FAIL cả 4 lệnh. Nguyên nhân (VERIFIED): bản sao chứa lease `state_leases(gateway-owner/global)` với heartbeat của Nemo live vừa ghi vài giây trước. CLI 10.5 chạy ở container khác (khác PID namespace) thấy heartbeat dưới 90s thì từ chối (`cannot verify Gateway ownership … wait up to 90 seconds`); `config validate` báo `Shared-state read … failed` cũng do đó. 10.4 không có kiểm tra này. Nếu không sửa, bước 20 sẽ fail ngay sau `docker stop` rồi tự rollback. Cách sửa: `wait_lease_stale` chỉ ĐỌC DB, chờ heartbeat cũ ≥100s rồi mới chạy CLI, áp cho cả 15 và 20. Không sửa hay xoá lease.

## Cutover 21/10 12:55 — FAIL, tự rollback OK

Gateway 10.5 thoát với mã 78 vì `openclaw-agent.sqlite` ở schema 24, cần `openclaw doctor --fix` (migrate session identities) khi gateway đang dừng. `99` tự chạy → 10.4 ready 13:00:59 (gián đoạn ~5,5 phút); codex 10.4, LCM 1.1.1, quick_check ok; H/S/Hermes giữ PID. State lỗi: `config.failed-10.5-20261021-125948`. Lesson: `kb/lessons/2026-10-21-nemo-105-dryrun-missed-schema-migration.md`. **Không chạy lại 20 khi chưa có rehearsal mới.**

## Rehearsal v2 (thêm sau sự cố)

`16_rehearsal.sh` chạy trên bản sao, thứ tự giống bước 20: codex 10.5 → `doctor --lint` → `doctor --fix --non-interactive` trên config chưa cách ly (env không có token Telegram) → gate user_version ≥25 + 8 mục config cốt lõi không đổi → cách ly (bỏ Telegram, cron OFF, loopback) → boot thử gateway (openclaw.json `:ro`, không cổng) → 1 lượt Muse → dọn. Review opus vòng 3 không ra lỗi chặn logic; đã áp: gate OAuth (bản sao mang refresh token live), đếm app-server qua `/proc` (image không có `ps` → mọi số `0` trước đây là sai; baseline thật = 2 process), RAM gate trước boot, xoá bản config đầy đủ khỏi log, kiểm reply qua JSON, marker kèm hash config.

## Review

Fresh-context (opus) 21/10: phát hiện 2 lỗi chặn ở đường rollback, đều đã sửa:

1. 99 ABORT khi fail trước bước rename → Nemo nằm stopped.
2. ERR trap bị kế thừa vào `$(...)` → rollback chạy ngầm nhưng vẫn in `OK 20`.

Đã sửa thêm các lỗi phụ: tar khi file đổi lúc đọc, npm cache riêng cho dry-run, RAM gate 1800, assert LCM hook, redact log. 99 đã được mô phỏng bằng docker giả: fail trước rename / sau rename / sau `docker run` đều về 10.4 với config cũ; mount lạ → ABORT.

## What could still be wrong

- Mặc định `sessionCatalog` của 10.5 chưa biết cho tới khi chạy 15.
- Nemo ít dùng nên soak 48h không chứng minh được 10.5 ổn cho tải như Rùa.
- `config validate`/`plugins inspect` PASS trên bản sao không bảo đảm gateway lên được → readyz và UAT mới là gate.
