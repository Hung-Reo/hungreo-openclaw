# 05/11/2026 — Gate bản tin dựng theo prompt cũ, lượt thật đầu tiên bị giữ cả bản tin

Loại: hermes, cron, news-source-gate, prompt-contract, replay, rollout, uat

## Catch-up nhanh

- VERIFIED: lượt thật đầu tiên qua `news-source-gate` v0.9.0 (05/11 06:40) gửi cảnh báo thay cho bản tin: `header_unknown`, vì cả 3 tiêu đề có `— 3 TIN`.
- VERIFIED: chỉ sửa tiêu đề thì vẫn chỉ giữ 2/9 tin. 7 tin còn lại có receipt nhưng nội dung `web_extract` không có ngày đọc được.
- v0.10.0 đã cài live 05/11 12:20 từ `~/work/news-source-gate-20261103/impl-v10r3/`, sau ba vòng review script. v0.11.0 (lấy ngày từ RSS, replay 5/9) cài tiếp 13:39 từ `impl-v11/`, Hưng GO không qua review độc lập. Chưa có lượt thật; UAT là bản tin 06:40 ngày 06/11. Báo cáo: `impl-v11/REPORT-v11.md`, `impl-v10r3/REPORT-r3.md`, root cause và replay: `impl-v10r3/REPORT.md`.

## Nguyên nhân

1. Prompt job đổi ngày 03/11, thêm `Heading ghi đúng số tin thực tế`.
2. Claude dựng grammar tiêu đề từ bản nháp theo prompt cũ, không đối chiếu với prompt đang áp dụng lúc rollout.
3. 9 vòng review tập trung vào parser thời gian bằng fixture, không có lần nào đưa một bản nháp theo prompt mới qua gate.

## Những điều đã làm sai và cách tránh lặp

- **Kiểm trên dữ liệu cũ khi đầu vào đã đổi.** Trước khi bật một gate kiểm format, chạy thử một bản nháp sinh từ đúng prompt sẽ chạy thật. Mỗi lần sửa prompt phải chạy lại replay.
- **Đã biết số 59/274 mà không quy ra hậu quả.** Con số đó báo trước bản tin sẽ thưa, nhưng mình chỉ ghi là "có thể thưa". Phải đo trên một lượt hoàn chỉnh và nói số tin mỗi mục trước khi xin bật.
- **Test tiêu đề đạt không có nghĩa bản tin đạt.** Luôn báo tách hai mức.
- **Script triển khai chỉ test đường thẳng thì chưa phải đã test.** 21/21 PASS của `upgrade-v10.sh` bản đầu không có ca lỗi giữa chừng; Hermes tiêm lỗi rename là thấy rollback kẹt. Rename atomic cho từng file, không cho cặp file. Script đổi nhiều file phải có test tiêm lỗi trước và sau từng bước, kể cả SIGKILL.
- **Muốn chặn lượt mới, tìm khoá mà chính hệ thống đang dùng trước khi nghĩ tới pause, và đọc khoá đó làm gì khi hết thời gian chờ.** r2 giữ `.jobs.lock`, nhưng khoá này hết 30 giây thì cho đi tiếp. `_fire_job_lock` nằm ngay dưới nó trong cùng file và hết giờ thì từ chối. Mình đã đọc đoạn timeout rồi ghi thành "giới hạn" thay vì đọc tiếp, và Rùa, Hermes đều tái hiện được.
- **Ghi một giới hạn vào báo cáo không có nghĩa là nó đã được chấp nhận.** Chỉ Hưng mới chấp nhận được residual.
- **Lối thoát viết trong báo cáo cũng phải được chạy thử.** "Pause là thoát được claim kẹt" là câu mình suy ra, không thử; Hermes thử và nó sai. Nguyên tắc: runbook chưa chạy end-to-end thì ghi UNVERIFIED.
- **Đo xem đường mới có được đi qua không, trước khi hứa.** Replay 05/11 đẹp (5/9), nhưng đếm trên các lượt cũ mới thấy model chỉ mở RSS bằng `web_extract` ở 1/43 lượt. Một lượt đẹp không nói được gì về sáng mai.
- **Test chống nới quá tay pass trên bản cũ thì không chứng minh gì.** Bản cũ không đọc RSS nên tự pass. Phải phá từng quy tắc (mutation test) để biết test có bắt được không; lần này nó còn chỉ ra một kiểm tra thừa để bỏ.
- **Không phải finding nào cũng đáng thêm một vòng code.** Lỗi cần hai sự cố cùng lúc, còn đường dừng và đường khôi phục bằng tay đã thử, thì để Hưng quyết nhận rủi ro và giữ nguyên bản đã review.
- **Đọc cùng một trường dữ liệu với hệ thống gốc thì phải dùng đúng mặc định của nó.** `job.get("enabled")` khác `job.get("enabled", True)`, và lỗi đó làm guard mở khi trường bị thiếu.
- **`--check` in BLOCKED mà exit 0 là nói dối với script gọi nó.** Trạng thái chưa sẵn sàng phải có mã thoát riêng.

## Cách replay một lượt cron (Hermes v0.22.5)

- Bản nháp trước transform không nằm ở `messages.content` mà ở `codex_message_items` của message cuối.
- Tool result trong `state.db` đã bọc `<untrusted_tool_result>`; kết quả lớn nằm ở `~/.hermes/cache/spillover/<call_id>.txt`.
- Kiểm độ trung thực: bản cũ phải replay ra đúng decision trong log live trước khi tin kết quả của bản mới.
- Cron chạy trong worker riêng và worker tự nạp plugin từ đĩa (log `handed to restart-safe worker pid=…`). Mới thấy ở một lượt.
