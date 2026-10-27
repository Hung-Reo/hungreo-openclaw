# Healthcheck alert candidate — 28/09/2026

> **Backup/retention:** xem [danh mục hiện hành](BACKUP_CATALOG.md) và [review 27/10](backup-review-20261027/REPORT.md) trước khi dò hoặc đề xuất cleanup. Các báo cáo/GO ngày cũ không phải quyền xóa mới.

**Production deployed28/09/2026 theo GO Hưng.** Cài wrapper/helper11:13–11:14;
28/28 tests trên VPS + lượt systemd thật16.32s PASS; timer30phút khôi phục active,
hai gateway PID/config giữ nguyên. Không gửi test thủ công; delivery UAT chưa kiểm.
Evidence/backup: `live-vps-snapshot/2026-09-28-healthcheck-production/report.md`.

Script live lấy token từ config legacy không còn tồn tại rồi return0, sau đó ghi
`fail=1`. Vì vậy thiếu credential vừa làm mất alert vừa tiêu thụ failure transition.
Probe mỗi30phút còn bỏ sót OOM nếu gateway đã tự phục hồi trước lượt probe.

## Thay đổi

- Bash giữ kiểm hai profiles và recovery hiện có (restart service khi down), dùng
  CLI canonical `$HOME/bin/openclaw`. Thêm lock cho cả lượt chạy; không lưu raw CLI
  diagnostics vào log. Đây vẫn là script có recovery action: **không chạy trên VPS
  để audit read-only**.
- Python stdlib đọc token đúng `OPENCLAW_ALERT_PROFILE` (hungreo/suckhoe), theo thứ
  tự `gateway.systemd.env` → `.env` → string token legacy trong `openclaw.json`.
  Không `source`/`eval`; không lấy `TELEGRAM_BOT_TOKEN` kế thừa từ profile khác;
  không in token hoặc đưa URL chứa token vào process arguments.
- Đọc user journal bằng cursor, không cần sudo. Attribution dùng `USER_UNIT` cho
  systemd manager (`_SYSTEMD_USER_UNIT=init.scope`). Gộp OOM + automatic restart
  cùng profile trong một lượt; stop/start bình thường không tạo incident alert.
- Snapshot mốc cuối trước khi đọc incident, cập nhật cursor cả khi không có incident.
  Không replay lịch sử trong lần đầu. State legacy `fail=1` tạo cảnh báo có ghi rõ
  “prior failure; delivery was not recorded”, không tuyên bố đã mất/gửi tin thật.
- Persist outbox + cursor cùng lúc (atomic replace, fsync,0600), rồi persist `sending`
  trước HTTP. Chỉ ghi ACK sau `ok:true`, message_id hợp lệ và chat ID khớp.
  Lỗi credential/chat hoặc API rejection4xx giữ pending để retry ở lượt kế tiếp.
  Timeout/5xx/ACK không hợp lệ/crash sau `sending` thành uncertain và chặn tự resend.
- Tối đa một HTTP attempt mỗi lượt, queue64. Failure/recovery/incident được giữ
  theo thứ tự; queue hoặc uncertain có thể làm thông báo mới chậm. Exit1 còn có
  nghĩa pending/uncertain notification, không chỉ gateway down. Exit2 là observer error.

Contract ACK được đối chiếu [Telegram Bot API](https://core.telegram.org/bots/api#making-requests)
và [sendMessage](https://core.telegram.org/bots/api#sendmessage).

## Kiểm tra offline

```bash
python3 -B -m unittest discover -s tools/openclaw-ops -p 'test_*.py' -v
bash -n tools/openclaw-ops/openclaw-healthcheck.sh
```

Tests dùng temporary directory, fake credentials, stub systemctl/openclaw và mock
HTTP/journal. Không gọi Telegram, không restart gateway thật. Fixture journal
`fixtures/incident-20260928.jsonl` chỉ giữ unit/time/event đã lọc; cursor thay bằng
fixture IDs, không chứa raw application logs/credentials/PII.

**Không dùng `OPENCLAW_ALERT_TEST=1` để test offline**: opt-in legacy đó gửi thật.
Test giao hàng thật cần GO Telegram và Hưng xác nhận nhận tin.

## Quy trình deploy đã áp dụng, dùng cho lần thay tiếp

Target: `/home/hung/bin/openclaw-healthcheck.sh` và helper cùng thư mục
`/home/hung/bin/openclaw_healthcheck.py`; giữ timer30phút, gateway/OOMPolicy/model/auth.
Prerequisites đã kiểm read-only: Python3 + flock + user journal + CLI canonical có sẵn.

1. Đo health/PID/readyz lại; verify SHA script live trước thay để tránh đè WIP mới.
   Baseline **trước cutover28/09**: `38f66137452734511898b8f53c7f71ea4b742162d3d95e0afde27129e4eca25d`.
   Wrapper sau cutover: `3035991dd8308131d65a89437e19145df68097a6631e9db9ee797674f0eece82`;
   lần thay tiếp phải đối chiếu generation/live mới, không dùng baseline cũ.
2. Snapshot script, state và unit metadata vào backup riêng; kiểm pending/uncertain
   trước migration. Không in credential. Validate numeric alert chat ID và presence/
   format token đúng profile trong process memory; chưa test API gửi thật.
3. Tạm dừng **healthcheck timer/service** trong cửa sổ bảo trì (script tự restart
   gateway down). Cài helper trước, thay wrapper atomically; check syntax/hash/modes.
   Không dừng/restart hai gateway, không đổi cron/automation khác.
4. Khởi tạo journal baseline và state migration dưới lock, bằng current probe
   evidence, qua helper `--observe-only` (ghi state, không đọc token/gửi tin).
   Truyền `--failed-profile <profile>` cho từng profile lỗi theo evidence vừa đo;
   không truyền nghĩa hai profiles vừa PASS. Nếu pending/legacyfail tồn tại thì
   thống nhất xử lý trước khi bật gửi.
   Không tự erase outbox hoặc coi uncertain đã gửi.
5. Bật lại timer đã giữ nguyên lịch; quan sát receipt/status/log. Phải có GO cho
   alert Telegram tự động khi bật candidate. Test message thủ công là GO riêng.

**Rollback:** khôi phục wrapper backup, giữ nguyên version2 state/helper/evidence;
script cũ đọc được field `fail` nhưng bỏ qua outbox, nên rollback làm mất chức năng
retry/incidents. Không xóa hay chuyển state ngược tự động; review pending/uncertain
trước lần cutover tiếp. Không cần restart gateway.

## Giới hạn còn lại

- Patch giúp phát hiện/thông báo sự cố, không chữa nguyên nhân tăng RAM/OOM.
  Kernel killed PID/allocation cause vẫn chưa xác nhận; không cần sudo để làm patch.
- Timer giữ30phút, nên alert có độ trễ đến lượt sau; không phải watcher realtime.
- Dựa vào journal còn retained giữa hai lượt. Cursor hỏng/unreadable hoặc journal
  invalid giữ state và fail closed; cần operator review, không tự baseline lại.
- Snapshot time bound dùng journal wall clock; thay đổi đồng hồ lớn cần kiểm
  cursor/coverage. Không cam kết exactly-once Telegram: uncertain cần reconcile
  bằng delivery evidence rồi GO, không tự sửa status để thử lại.
- Mock ACK/copy replay không phải Production delivery UAT. Chưa benchmark lượt chạy
  đầy đủ trên VPS; helper tối đa hai journal reads20s + một HTTP attempt20s.
