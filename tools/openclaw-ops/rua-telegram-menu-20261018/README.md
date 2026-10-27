# Rùa: đưa /lossless, /lcm trở lại menu Telegram (2026-10-18)

**Root cause (VERIFIED):** journal Hungreo 17/10 14:49 báo `Telegram limits bots to 100 commands. 111 configured; registering first 100`. Code 2026.9.9 (`transport-status-*.mjs`) xếp menu theo thứ tự custom → builtin + skill → plugin → alias, nên đuôi danh sách bị cắt, mà đuôi đó là lệnh plugin. `getMyCommands` hiện có 100 lệnh: 43 builtin, **47 lệnh skill**, 10 lệnh plugin (`/case` … `/finance_status`). `/lossless` và `/lcm` nằm trong 11 lệnh bị cắt. Suckhoe chỉ có 64 lệnh nên đủ chỗ.

**Đổi:** `channels.telegram.commands.nativeSkills = false`. Khoá này chỉ áp cho kênh Telegram của Hungreo (schema `ProviderCommandsSchema`, giá trị ở provider đè giá trị global). Tác dụng: bỏ 47 lệnh skill riêng khỏi menu, giữ `/skill`, menu còn ~64 lệnh, đủ chỗ cho cả 21 lệnh plugin. Prefix `channels.telegram` là hot reload: kênh Telegram khởi động lại, gateway không restart.

**Mất gì:** các nút skill riêng trên menu (`/lossless_claw`, `/weather`, …). Vẫn gọi được skill bằng cách gõ `/skill <tên>`, và model vẫn tự dùng skill như cũ. Gõ thẳng `/lossless_claw` sau khi đổi có còn chạy không thì UNVERIFIED.

| #     | Ai                     | Lệnh                                                                                                            | Kỳ vọng                                                                                                      |
| ----- | ---------------------- | --------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| check | Claude (đã chạy 14:25) | `ssh … 'bash -s check' < 10_apply.sh`                                                                           | `CHECK OK`, dry-run strict PASS, hash không đổi                                                              |
| 10    | Hưng                   | `ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 10_apply.sh` (ngoài khung 05:35–07:20, 16:35–16:55) | `BACKUP=…`, readback `false`, khoá đổi đúng 1, pid giữ nguyên, `menu sau: … lossless=True lcm=True`, `OK 10` |
| UAT   | Hưng                   | Telegram Rùa: gõ `/` thấy `/lossless`, `/lcm` → bấm `/lossless` → gõ `/skill lossless_claw`                     | `/lossless` hiện trạng thái DB; `/skill` vẫn gọi được skill                                                  |
| 99    | Hưng (nếu cần)         | `ssh … 'bash -s <BACKUP>' < 99_rollback.sh`                                                                     | readback `null`, menu quay về 100 lệnh, có `lossless_claw`                                                   |

Review fresh-context (opus): không có lỗi chặn. Đã sửa 5 lỗi phụ: lỗi trong `$(...)` làm script dừng giữa chừng, CLI có thể nuốt stdin, diff khi giá trị cũ là null, lọc `meta`, đường khôi phục tay. Đã thêm kiểm readback, kiểm hash backup ở 99, dùng `mktemp`, nới khung giờ.

**Còn có thể sai:**

- Menu Telegram có thể sync chậm hơn 60 giây.
- Lệnh plugin chỉ gõ chữ (đường text) trên 9.9 từng rơi xuống AI (lesson 11/10). `/lossless` được đăng ký là lệnh native nên ASSUMPTION là không gặp lỗi đó; UAT sẽ cho biết.
- `config unset` khi rollback có thể để lại object `commands: {}`, ASSUMPTION là vô hại.
