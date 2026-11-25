# Rùa đốt hết quota Codex 5h: heartbeat dùng chung phiên `main` + LCM nén dồn sau 9.36 (12/11/2026)

Loại: cost | heartbeat | lossless-claw | upgrade-9.36 | codex-quota | stuck-session

## Kết quả

- 12/11 18:14 quota ChatGPT Plus (Codex) của Hưng về 100% cửa sổ 5h, 31% tuần, trong lúc Hưng không dùng gì. Nguồn tiêu: chỉ Hungreo (Rùa). Suckhoe, Hermes, Nemo, Codex trên Mac không liên quan (VERIFIED).
- Đã làm (GO Hưng): 18:42 bật `agents.defaults.heartbeat.isolatedSession = true` cho Hungreo (hot reload); 18:45 tắt healthcheck timer, restart riêng `openclaw-gateway-hungreo.service`, `ready` 18:52:24, bật lại timer.
- Sau restart đến 20:11 (VERIFIED): 0 `model-fetch`, 0 `stuck session`, 0 bản tóm tắt LCM mới, `MODEL_DRIFT=0`, `NRestarts=0`, `readyz=200`. Model chính, fallback, auth, slot không đổi.
- Backup: `/home/hung/backups/hungreo-heartbeat-isolated-20261112-184209/openclaw.json` (+ `SHA256SUMS`). Rollback: đặt khoá về `false` hoặc chép backup về.

## Chuỗi nguyên nhân (VERIFIED trừ chỗ ghi rõ)

1. Heartbeat Hungreo (2h/lượt, `gpt-5.6-luna`, `session: main`) ghi vào phiên `agent:main:main` từ 25/09, khoảng 6.880 sự kiện, chưa từng reset. LCM không nén phiên này từ 30/09.
2. Nâng 9.36 tối 11/11. Lượt heartbeat đầu (20:33) LCM ghi `transcript resync reason=legacy-migration imported=4282`, áp lực ngữ cảnh 17,9M token so với đích 204K. Từ đó mỗi lượt heartbeat kéo theo 12 bản tóm tắt bằng `gpt-6.1-sol` (model nén mặc định = model chính).
3. Restart 12/11 15:00 (nạp bản sửa plugin Finance). Lượt 16:33 gặp `generation_mismatch`, LCM chuyển sang nén tiền cảnh; prompt khoảng 245K vượt cửa sổ 200K của luna, heartbeat treo khoảng 7 phút, `CommandLaneTaskTimeoutError`, cơ chế gỡ phiên kẹt chạy lại. 14 vòng từ 16:33 đến 18:14, tiếp tục từ 18:33 tới lúc restart.
4. Tổng LCM 16:33–18:47: 192 bản tóm tắt, đọc khoảng 4,8M token, viết 0,31M. Quota: 12:33 0%/0% → 15:33 70%/11% (việc thật trong group/DM, phần lớn là cache) → 18:14 100%/31%.
5. Vì sao 9.36 kích `legacy-migration`: UNVERIFIED (changelog không ghi, tìm issue không ra).

## Bài học

1. **Heartbeat không dùng chung phiên dài.** Phiên chung phình dần và mỗi lượt kéo theo cả lịch sử. `isolatedSession: true` cho mỗi lượt một phiên mới (docs 9.36: khoảng 100K → 2–5K token/lượt).
2. **Việc nền của plugin cũng ăn quota model chính.** LCM tóm tắt bằng model nén mặc định; `[model-fetch] ... model=gpt-6.1-sol` khi không ai nhắn là dấu hiệu. Khi quota tụt bất thường, đếm `model-fetch` theo giờ và đếm `summaries` trong `lcm.db` trước khi nghi người dùng.
3. **Sau upgrade, kiểm lượt heartbeat/cron thật đầu tiên**, không chỉ `readyz` và drift: thời lượng lượt, dòng `transcript resync`, số bản tóm tắt mới. Lượt 20:33 ngày 11/11 đã lộ dấu hiệu, 20 giờ trước khi hết quota.
4. **Restart gateway có thể đổi đường nén** (`generation_mismatch` → nén tiền cảnh). Sau restart có nợ nén lớn thì theo dõi lượt nền kế tiếp.
5. **Số liệu token phải biết là của cái gì.** Một phân tích khác đọc tổng `input + cacheRead` của 15 tin trong một lượt thành "148K mỗi lượt gọi" rồi nhân ra 10M. Hướng xử lý vẫn đúng, con số sai. Đối chiếu từng nguồn: `transcript_events.usage`, `token_count` trong rollout Codex, `summaries` của LCM.
6. **Mình đã nói sai một lần:** "vòng lặp dừng lúc 18:14 vì hết quota". Thực tế các lượt gọi vẫn trả 200 sau mốc 100%. Đã đính chính trong phiên; lý do lượt 16:33 kết thúc lúc 18:15 chưa rõ.

## Cách kiểm nhanh khi gặp lại (read-only)

- Quota theo thời gian: sự kiện `token_count` (`rate_limits.primary/secondary.used_percent`) trong `agents/main/agent/codex-home/sessions/YYYY/MM/DD/*.jsonl`.
- Ai gọi model: `journalctl --user -u openclaw-gateway-hungreo.service | grep model-fetch`, gom theo giờ và theo `model=`.
- LCM: `lcm.db` bảng `summaries` (đếm theo giờ), log riêng `/tmp/openclaw/lossless-claw-YYYY-MM-DD.log`.
- Lượt heartbeat: `state/openclaw.sqlite` bảng `cron_run_receipts`. Mở SQLite bằng `?mode=ro`.

## Còn mở

- Lượt heartbeat phiên riêng đầu tiên (20:33 ngày 12/11) chưa quan sát lúc ghi file này; chưa có UAT Telegram của Hưng.
- Nợ nén còn khoảng 2M token trên conversation của `agent:main:main` trong `lcm.db`. Nằm im khi không có lượt nào trên phiên đó; sẽ chạy lại nếu tắt `isolatedSession` hoặc có lượt ghi vào phiên `main`.
- LCM vẫn tóm tắt bằng `gpt-6.1-sol` cho DM và group. Đề xuất `summaryModel` rẻ hơn cho `lossless-claw` (cần `llm.allowModelOverride` + `allowedModels`) là thay đổi liên quan model, cần GO riêng của Hưng.
- Suckhoe heartbeat 1h vẫn dùng phiên chung; hiện nhỏ (khoảng 0,05M token/ngày), chưa rà.
- Chưa kiểm healthcheck có gửi cảnh báo FAIL trong khoảng restart 18:45–18:52 hay không.
