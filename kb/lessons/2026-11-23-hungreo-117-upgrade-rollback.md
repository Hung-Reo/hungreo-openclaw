# Nâng Rùa 9.36 → 11.7 + Sol 6.2 thất bại, rollback sạch; disk lên 94% vì chồng bản sao (23/11/2026)

Loại: upgrade | openclaw-11.7 | doctor | heartbeat | cron-jobs | disk-space | rollback-ok

Nguồn gốc (source of truth): `tools/openclaw-ops/hungreo-117-sol62-20261123/README.md`. Issue log: `tools/openclaw-ops/hungreo-117-sol62-20261123/ISSUE-LOG.md`.

## Kết quả

- Hiện trạng sau cùng (VERIFIED theo README, 20:46): Hungreo chạy lại OpenClaw 2026.9.36 + Sol 6.1. Config và env khớp checksum, `/readyz` 200 cả Hungreo lẫn Suckhoe, Telegram probe đạt, healthcheck timer active, job tuần còn trong DB.
- Sol 6.2 chưa chạy lượt nào. Không có Telegram traffic vào bản 11.7.
- Do Codex làm, Hưng duyệt kiểu "khỏi diễn tập, làm luôn, miễn có backup và fallback được".

## Diễn biến (giờ VN)

1. **19:39, lần 1:** backup đầy đủ, checksum khớp, `quick_check` 3 DB đạt. CLI 11.7 từ chối `agents.defaults.heartbeat` ngay ở preflight. Bản 11.7 bắt buộc chuyển heartbeat sang Automations, và việc này có ghi trong release notes nhưng bị bỏ sót khi rà trước. Hai lần chạy trước đó còn dừng vì phép kiểm `/proc` đụng tiến trình hệ thống được bảo vệ. Rollback về 9.36, phải start healthcheck timer riêng.
2. **20:03, heartbeat migration được duyệt (2h, 06:00–23:00, isolated, light context, Luna):** Doctor chạm timeout 220s giữa chừng. Shared schema lên 36, agent DB vẫn 24, heartbeat vẫn dạng cũ. Rollback, 20:14 probe đạt. 20:23 xoá đúng profile nâng dở của lần này (Hưng duyệt), thu về 7,09 GiB.
3. **20:34, lần cutover chính (Doctor timeout 600s):** Doctor chạy xong, schema 36/38, heartbeat chuyển đúng (cùng ID, lịch, checklist, giao cho owner). Nhưng config check chặn lại vì Doctor **xoá entry tắt `skills.entries.nano-banana-pro`** và sửa 2 field metadata wizard. So offline còn thấy bản 11.7 **mất 1 job `agentTurn` tuần đang bật** (vừa chạy 04:33 cùng ngày, lượt kế 04:33 ngày 30/11). Rollback tự động, 20:46 hậu kiểm đạt.
4. **Disk:** mỗi lần thử tạo một bản sao profile 6–7 GiB và giữ lại. Còn 6,55 GiB trống sau lần 20:34 (VPS khoảng 94%). Thread dọn disk sau đó đưa về khoảng 82%, trống 18G (PRIOR-EVIDENCE, số do thread dọn disk báo 23/11 21:08). Bản nâng dở 20:34 (`20261123-203424.x2NKjZ6y/post-cutover.UCo632MT/profile`, 7,1 GiB) đang giữ để đối chiếu; đã xoá hay chưa là UNVERIFIED.

## Bài học

1. **Đọc kỹ release notes trước khi nâng.** Lần đầu hỏng vì bỏ sót thay đổi heartbeat của 11.7, trong khi nó có ghi rõ. Rà release phải liệt kê mọi key config bị bỏ/đổi và đối chiếu với config thật của profile.
2. **Chạy thử Doctor trên bản sao, khi Rùa vẫn online.** Doctor tự xoá job tuần và dòng tắt `nano-banana-pro`. Chạy trên bản sao rồi so jobs/skills/config cũ với mới thì bắt được trước khi phải dừng gateway. Lần này bắt ở bước kiểm sau cutover nên tốn một lượt dừng.
3. **Kiểm dung lượng trước, dọn chỗ xong mới nâng.** Mỗi lần thử để lại một bản 6–7 GiB, nên disk lên 94%. Cần trống ít nhất 2 lần kích thước bản sao (bản rollback + bản migrate + file Doctor), và chỉ giữ 1–2 bản rollback.
4. **"Khỏi diễn tập" vẫn được nếu có backup, nhưng giữ bước Doctor thử.** Backup và rollback tự động đã làm đúng cả 3 lần. Bước chạy Doctor trên bản sao rẻ mà chặn đúng loại lỗi này, nên không bỏ. Chỉ ghi "an toàn" khi đã kiểm.
5. **Có danh sách "phải giữ nguyên" trong biên bản.** Ghi rõ các job đang bật, skill đang tắt, model/fallback, heartbeat. Lần sau diff bản migrate với danh sách này, lệch là dừng.

## Checklist cho lần nâng kế tiếp

**Trước khi dừng gateway**

- [ ] Đọc release notes từ 9.36 tới bản đích. Liệt kê key config bị bỏ/đổi (vd heartbeat → Automations) và xử lý từng key.
- [ ] Ghi danh sách phải giữ nguyên vào README: mọi cron/automation job đang bật (ID, lịch, lượt kế), skill đang tắt (`nano-banana-pro`…), model chính/sub/fallback, heartbeat.
- [ ] Kiểm disk: trống ≥ 2 lần kích thước bản sao profile (hiện ~7 GiB → cần ≥ 14 GiB, nên ≥ 15 GiB). Dọn bản rollback cũ đã hết cần trước.
- [ ] Kiểm Codex OAuth đã có Sol 6.2 (`codex-home/models_cache.json`), không để rơi sang OpenRouter trả phí.
- [ ] Chạy Doctor trên bản sao (Rùa vẫn online), timeout đủ dài (600s). Diff jobs, skills, config với danh sách phải giữ. Lệch thì sửa cách migrate rồi chạy thử lại, chưa cutover.

**Cutover**

- [ ] Chờ heartbeat/job đang chạy xong, không có approval chờ.
- [ ] Backup cuối: checksum khớp, `quick_check` cả 3 DB.
- [ ] Doctor + config check, rồi diff lại với danh sách phải giữ. Lệch là rollback.

**Sau cutover**

- [ ] `/readyz` 200 (Hungreo, Suckhoe), Telegram probe, healthcheck timer active, `SECRETS_DEGRADED` = 0, env của gateway đủ tên biến.
- [ ] Một lượt Sol 6.2 thật qua Codex OAuth, log không có fallback.
- [ ] Theo dõi 24–48 giờ: heartbeat 2 giờ chạy, lượt nền đầu tiên bình thường. Job tuần chạy lượt 04:33 ngày 30/11 (hoặc lượt kế). `nano-banana-pro` vẫn tắt.
- [ ] Hưng UAT trên điện thoại với Rùa và Suckhoe.

**Sau UAT**

- [ ] Dọn các bản rollback/nâng dở cũ, chỉ giữ 1 bản 9.36 khoảng 1 tuần.
- [ ] Ghi biên bản: 11.7 là bản chính thức. Cập nhật `kb/openclaw-upgrade-runbook.md` và skill `openclaw-ops` nếu quy trình đổi.

## Còn mở

- Chưa có cách migrate giữ được job tuần và entry tắt `nano-banana-pro` trên 11.7. Cần xác định trước lần thử sau.
- Issue chưa đăng ký vào VPS Ops Issue Registry (`/home/hung/openclaw-shared/ops-issues`), vì thread này chỉ sửa file trong repo.
