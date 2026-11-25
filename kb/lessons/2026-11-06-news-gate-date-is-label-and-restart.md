# 06/11/2026 — Bản tin Hermes: ngày đăng là nhãn, và "đã cài" chỉ tính khi tiến trình đã nạp

Loại: hermes, cron, news-source-gate, policy, restart, uat, multi-agent

## Catch-up nhanh

- VERIFIED: gateway PID 1201688 giữ gate v0.9.0 từ 04/11, nên v0.10.0, v0.11.0 và bản Codex chưa có hiệu lực ở lượt cron nào. Sau restart 06/11 09:22, dòng `registered version=0.12.0` có `pid` trùng `MainPID` của gateway.
- VERIFIED: 9/9 link đều đã mở ở cả 05/11 và 06/11. Tin bị mất là do luật ngày đăng, vì đa số trang không có ngày đọc được.
- Hưng quyết: trang không có ngày thì giữ và gắn nhãn `⚠️ chưa xác minh ngày đăng`; ngày đọc được mà ngoài 48h thì loại; link chưa mở thì vẫn chặn.
- VERIFIED: Suckhoe (`bsy_morning_brief.py`, `publication_date_ok`) đã dùng đúng logic này từ trước: thiếu ngày thì giữ, biết chắc quá hạn thì loại. Đây là tham chiếu đáng lẽ phải đọc từ đầu.

- 11:24 cùng ngày: Hưng đổi mốc 48h thành 72h theo Suckhoe (gate v0.13.0), sau khi thấy mốc 48h loại 2 tin AI thật, một tin chỉ quá 1,6h.

## Bài học

1. **"Đã cài" chỉ tính khi tiến trình đã nạp.** Hash trên đĩa, test, replay đều không chứng minh. Bằng chứng tối thiểu: dòng `registered` có `pid` trùng `MainPID`; bằng chứng cuối: dòng `decision` của lượt thật.
2. **Công cụ kiểm báo lạ thì điều tra.** `runtime_receipt=none` là tín hiệu thật, từng bị giải thích cho qua.
3. **Hỏi lại mục tiêu trước khi vá.** Gate để chặn tin bịa; ngày đăng là phụ. Nhiều vòng sửa parser không chạm được vấn đề vì dữ liệu không có ngày để đọc.
4. **Hệ khác trong nhà đã giải bài này chưa?** Đọc Suckhoe trước sẽ tiết kiệm nhiều vòng.
5. **Việc nhỏ thì chọn cách nhỏ.** Bản sửa cuối chỉ đổi 19 dòng.
6. **Mỗi lần chỉ một agent đổi live.** Cùng sáng 06/11 có hai agent thay đổi hoặc chạy gate mà phiên kia không nắm đủ.
7. **Hỏi con số thì đưa kèm hệ quả và số của hệ tham chiếu.** Hưng chọn 48h khi chưa thấy Suckhoe dùng 72h và mốc đó loại tin nào.
8. **Công cụ replay phải chọn đúng phiên.** `impl-v11/inspect_run.py` lấy phiên `web_extract` mới nhất, không theo `execution_id`, nên replay lượt cũ thực chất đọc bản nháp mới nhất.

## Giới hạn còn lại

- Bài cũ không có ngày đọc được có thể lọt, nhưng có nhãn (Hưng chấp nhận).
- Trang có tín hiệu ngày mơ hồ vẫn bị loại.
- Chưa có lượt cron thật nào chạy qua v0.12.0 tại thời điểm ghi; UAT là lượt 07/11 06:40.
