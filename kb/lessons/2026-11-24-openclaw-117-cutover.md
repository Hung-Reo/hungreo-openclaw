# Rùa lên 11.7 sau 5 lần cutover: CLI offline-only, Doctor tự restart, plugin TS 15s (24/11/2026)

Loại: upgrade | openclaw-11.7 | doctor | offline-only-cli | plugin-load | codex-model-catalog | rollback-ok | monitoring

Runbook dùng lại: `kb/openclaw-117-upgrade-runbook.md`. Bằng chứng: `tools/openclaw-ops/hungreo-117-sol62-20261123/ISSUE-LOG.md` (H117-05 → H117-10c).

## Kết quả

- 24/11 14:51: `UPGRADE_OK`. Rùa chạy 2026.11.7 + `openai/gpt-6.1-sol` (oauth), 48 job, heartbeat chạy dạng automation isolated. Hưng xác nhận `/status` lúc 16:47.
- 17:24: `hungreo-finance` nạp lại được sau khi đóng gói JS, 9/9 plugin.
- Tổng downtime 4 lần rollback khoảng 55 phút. Không mất tin nhắn, không đốt tiền (0 dòng fallback/api-key).

## Chuỗi nguyên nhân (đều VERIFIED bằng log + source 11.7)

| Lần    | Dừng ở             | Nguyên nhân                                                                        | Bài học                                                                             |
| ------ | ------------------ | ---------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| 09:35  | đổi model          | `gpt-6.2-sol` "Unknown model": cache model lúc đó vẫn do Codex 0.160 ghi           | Danh sách model phụ thuộc phiên bản Codex client. Nâng runtime trước, đổi model sau |
| 12:36  | `plugins update`   | Lệnh chỉ chạy offline và bị từ chối; Doctor đã cập nhật plugin rồi                 | Bỏ bước thừa; đọc `dist/local-state-owner-*` (`onForeignOwner: "refuse"`)           |
| 13:03  | `models auth list` | Cũng chỉ chạy offline, mà script gọi sau khi gateway đã bật                        | Lệnh admin offline chạy khi gateway dừng                                            |
| 13:55  | `models auth list` | **Doctor tự restart gateway** ở chế độ đầy đủ, mở Telegram giữa migration          | HOLD drop-in trước Doctor, stop lại sau Doctor                                      |
| 14:36  | —                  | PASS                                                                               | —                                                                                   |
| sau đó | plugin finance     | Thời hạn chuẩn bị nguồn TS là 15s cứng (`plugin-generation-preparation.worker.js`) | Đóng gói esbuild, bỏ `dependencies`                                                 |

## Bài học

1. **Dry-run phải có boot gateway thật trên bản sao** (Docker `--network none`). Bản dry-run chỉ có Doctor không bắt được lỗi offline-only, Doctor tự restart hay plugin timeout. Lỗi finance chỉ lộ ra khi gateway khởi động.
2. **Container khác host:** trong Docker không có systemd nên Doctor không restart được gì, và `plugins update` chạy được. Trên host thì ngược lại. Khi kết quả dry-run khác live, ghi rõ khác ở tầng nào.
3. **Theo dõi bằng trạng thái, không bằng tiến trình:** vòng `pgrep -f "cutover.sh …"` khớp chính lệnh ssh, treo 2 giờ nên báo trễ. Đọc marker trong log/phase file thay vào đó.
4. **Mỗi lần rollback để lại 6–7G.** Kiểm disk trước mỗi lần thử, và đặt chốt "disk < 15G thì không chạy" ngay trong lệnh hẹn giờ.
5. **Chờ heartbeat:** script chặn khi có job đến hạn trong 20 phút. Hẹn lịch ngay sau heartbeat để khỏi bị chặn.
6. **Chạy trên VPS bằng `nohup setsid`**, để Hưng gập máy, hết pin hay di chuyển cũng không sao.
7. Heartbeat 9.36 đọc checklist trong DB (`cron_job_scratch`), không đọc `HEARTBEAT.md`. Doctor giữ nguyên checklist đó.

## Còn mở

- Watcher hot-reload config lỗi "watch observation worker stopped" 3/3 lần sau mỗi lần start.
- Đổi Rùa sang Sol 6.2: cache Codex 0.170 đã có `gpt-6.2-sol` (17:46 ngày 24/11). Chờ GO.
- Suckhoe vẫn ở 9.36. Khi nâng, theo runbook, kiểm plugin TS local và heartbeat của profile đó.
