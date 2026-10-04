# Runbook bảo trì — cập nhật + ghim plugin 9.6→9.8, restart Hungreo & Suckhoe (2026-10-04)

**GO:** Hưng "GO Q1–Q4 theo đề xuất" (04/10). Q1 cập nhật+ghim plugin, gộp restart Suckhoe · Q2 bỏ qua `security.installPolicy` · Q3 chuyển skill `google-sheets` ra backup · Q4 hoãn `doctor --fix` codex.
**Ai chạy:** harness chặn Claude Code ghi Production → **Hưng chạy 01, 02, 03 (và 99 nếu cần)**; Claude Code chạy 00 và 04 (read-only + UAT) rồi kiểm.

## Phạm vi

| Làm                                                                                | Không làm                                                                                       |
| ---------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Hungreo: brave, deepseek, parallel, typesafe → `@2026.9.8` (spec chính xác = ghim) | codex (giữ 9.8, chưa ghim — để restart Suckhoe là phép thử sạch cho lỗi 403, không lẫn biến số) |
| Suckhoe: brave, deepseek → `@2026.9.8`                                             | lossless-claw (giữ pin 1.1.0)                                                                   |
| Chuyển `workspace/skills/google-sheets` (Hungreo) → backup                         | model / auth / fallback / exec / `installPolicy` / `doctor --fix` / transcript                  |
| Restart suckhoe → hungreo                                                          | Nemo (Docker `nemo-sandbox`), n8n                                                               |

## Rủi ro & chi phí

- **Downtime** ~5–8 phút mỗi bot (Hungreo ready ~60–70s sau start). Cron trong 3 giờ tới: chỉ heartbeat (Hungreo 20:33, Suckhoe 20:46) — lỡ 1 nhịp không sao.
- **Cùng tài khoản OAuth** cho 2 bot → restart lần lượt, chờ ready từng cái (lesson 2026-09-30 failed refresh fence).
- **Lỗi 403 Suckhoe** (từ 03/10 15:45, đang chạy Muse dự phòng): restart **có thể không sửa** — `models auth list` báo `cooldown:auth` và gợi ý đăng nhập lại. Nếu sau restart vẫn 403 thì Suckhoe vẫn ở trạng thái như hiện nay (không tệ hơn); việc đăng nhập lại thuộc phiên KB/P1-A, cần Hưng thao tác.
- **Auto-migration lúc gateway start** (lesson 6.1) → 04 DIFF config sau restart.
- **Chi phí:** không đổi provider. UAT Suckhoe nếu còn 403 sẽ rơi sang Muse (OpenRouter) 1 lượt ngắn — không đáng kể.
- **Healthcheck timer** phải TẮT trong lúc dừng (nếu không nó tự bật gateway giữa chừng) — 01 tắt, 03 bật lại.

## Các bước

Mở Terminal, `cd` vào thư mục này trước:

```bash
cd ~/Development/hungreo-openclaw/tools/openclaw-ops/plugins-pin-20261004
```

| #   | Ai       | Lệnh                                                                           | Kỳ vọng                                                                                                                        | Dừng nếu                                                                        |
| --- | -------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------- |
| 00  | Claude   | `00_precheck.sh` (đã chạy 20:31, `evidence/00_precheck.txt`)                   | 2 gateway active, plugin 9.6, index Suckhoe 307 chunks                                                                         | —                                                                               |
| 01  | **Hưng** | `ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 01_stop_backup.sh` | `OK 01`, SHA256SUMS in ra, 2 gateway `inactive pid=0`                                                                          | có `ABORT`/`FAILED`                                                             |
| 02  | **Hưng** | `ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 02_update.sh`      | 6 dòng update → 9.8; DIFF config **chỉ** khác ở mục plugins (không có `model`/`auth`); `OK 02`                                 | có `FAILED`, DIFF đụng model/auth → **gửi output cho Claude trước khi chạy 03** |
| 03  | **Hưng** | `ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 03_start.sh`       | suckhoe rồi hungreo `ready`, `healthcheck.timer: active`                                                                       | `STOP` → báo Claude                                                             |
| 04  | Claude   | `04_verify.sh`                                                                 | plugin 9.8 loaded, audit hết `unpinned` (trừ codex), DIFF sau restart không đổi model/auth, UAT Hungreo `gpt-6-sol attempts=1` | —                                                                               |
| 05  | **Hưng** | Nhắn `/status` cho Rùa và Suckhoe trên Telegram                                | Rùa trả lời model `gpt-6-sol`; Suckhoe: ghi lại model đang hiện                                                                | —                                                                               |

**Mức đạt (PASS):** Hungreo đủ 3 tầng PASS. Suckhoe: plugin + gateway PASS; model PASS **nếu** hết 403 — nếu còn 403 thì ghi "maintenance PASS, P1-A chưa sửa bằng restart" (chuyển cho phiên KB, bằng chứng A1).

## Rollback

| Mức  | Khi nào                              | Lệnh                                                                                                                                                                                                                                   |
| ---- | ------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| soft | plugin 9.8 lỗi nhưng config/state ổn | `ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s soft' < 99_rollback.sh` — cài lại `@2026.9.6`, trả `google-sheets` về                                                                                                         |
| hard | config/state hỏng, gateway không lên | `ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s hard' < 99_rollback.sh` — khôi phục `openclaw.json` + `state/openclaw.sqlite*` + thư mục plugin từ `/home/hung/backups/maint-20261004-plugins` (mất state ghi sau lúc backup) |

## Backup (tạo ở bước 01)

`/home/hung/backups/maint-20261004-plugins/{hungreo,suckhoe}/` — `openclaw.json`, `state/openclaw.sqlite*` (chép khi gateway dừng), `npm-projects-plugins.tgz`; `skills/google-sheets/`; `SHA256SUMS`.
Ngoài ra Hungreo có `openclaw.json.bak-20261004-pre-timeout600` (trước đổi timeout) và Suckhoe các backup của phiên KB (`…pre-kb-embeddings`).
