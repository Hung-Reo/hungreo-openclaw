# Brief cho Hermes — vn-stock: thẻ AI 12:45 + ví AI_FOLLOW_MIDDAY (Hưng chốt 10/10/2026)

Repo `Hung-Reo/vn-stock-agent`, base `main` `5d23f67`. Làm trên nhánh riêng, mở PR draft. Không deploy, không sửa production, không đổi timer trên VPS.

## Hưng đã quyết (chat 10/10)

- 12:45 chạy research AI **đầy đủ như 9:30**: đủ kịch bản, được đề xuất mã mới. Trước đó phải **đánh giá phiên sáng**.
- **Không** làm lượt 13:45.
- **Q1** — thêm ví giả lập thứ 2 `AI_FOLLOW_MIDDAY`, làm theo thẻ 9:30 + thẻ 12:45; ví S1 `AI_FOLLOW` giữ nguyên tới 31/10.
- **Q2** — thẻ trưa **thay** tin midday code-only hiện tại (mỗi trưa 1 tin).
- **Q3** — được chạy sớm 12:40 nếu đo thấy không kịp gửi trước 13:00.
- **Jev bắt buộc** ở lượt trưa giống 9:30: challenger cùng packet Sol thấy, ghi `challenger/ledger.jsonl`, chung cap `monthly_usd_cap` 1 USD (VERIFIED 10/10: tháng 10 mới 119 lượt, 0,012 USD → thêm 20 lượt/ngày vẫn dưới cap). Jev chỉ là ý kiến phụ, không quyết thay Sol, cohort riêng `midday`.

## Không được đổi

Prompt và thẻ 9:30, model/route, luật ví S1, thẻ đã niêm phong, scorecard lịch sử. Không có lệnh tiền thật.

## Thiết kế

1. **Đánh giá phiên sáng (code, deterministic).** Dùng bảng giá 11:30 (đã có `stages/<day>/midday/evidence.json`) + snapshot 9:32 + nến ngày đã chốt + RSS mới sau 9:30 + VNINDEX trưa (nếu bảng giá không có thì lấy thêm, giữ request limit). Mỗi mã:
   - giá so với tham chiếu, giá vào, cắt lỗ, mục tiêu của thẻ sáng;
   - lệnh sáng khớp chưa;
   - đỉnh/đáy phiên sáng;
   - nhịp khối lượng so với cùng giờ của 20 phiên trước (không dùng khối lượng nửa ngày như cả ngày);
   - khối ngoại;
   - hàng T+2 đã bán được từ 13:00 chưa.
     Kiểm độ mới của quote (≥ 11:29), quote cũ thì ghi rõ.
2. **AI research trưa.** Prompt mới có version riêng (`midday/v1`), không sửa prompt sáng. Packet gồm phần 1 + thẻ sáng đã niêm phong + "còn N phút khớp liên tục". Đầu ra cùng schema với 9:30, **thêm** mỗi mã 1 dòng `giữ | đổi` so với thẻ sáng, kèm bằng chứng mới sau 9:30. Không có bằng chứng mới thì phải giữ.
3. **Kiểm cứng (code).** Code từ chối hoặc hạ cấp đầu ra AI nếu vi phạm:
   - tính lại `risk_reward_net` tại giá trưa, phí 0,4%;
   - nâng giá vào lệnh hoặc mua mới chỉ khi tỷ lệ ≥ ngưỡng hiện hành (2);
   - **không hạ mức cắt lỗ** để giữ lệnh;
   - lô 100, vốn ngăn, biên độ giá;
   - lệnh trưa chỉ hiệu lực phiên chiều hôm đó.
4. **Một tin Telegram, plain text:** kết luận → phiên sáng thế nào → giữ/đổi gì so với thẻ sáng và vì sao → việc phiên chiều → ghi chú Jev ở cuối (giống thẻ sáng).
   - Model lỗi hoặc trễ: gửi bản midday code-only cũ + cảnh báo.
   - Giữ guard "sau 13:30 không gửi".

## Ví `AI_FOLLOW_MIDDAY`

- **Điểm xuất phát:** bản sao trạng thái ví S1 tại phiên đầu tiên có thẻ trưa. So hai ví từ cùng ngày đó, không so từ 24/09.
- **Luật:** cùng vốn, phí, thuế, luật bán và T+2 như S1. Khác duy nhất: làm theo cả quyết định của thẻ trưa (đã qua bước 3).
- **Khớp lệnh trưa phải thận trọng.** Chỉ có nến ngày, nên LO mua trưa giá P chỉ tính là khớp khi chắc chắn buổi chiều đã chạm giá:
  - đáy cả ngày < đáy phiên sáng **và** đáy cả ngày ≤ P;
  - ngược lại ghi `UNVERIFIABLE_AFTERNOON_FILL`, không tính khớp.
  - Áp tương tự cho bán.
- Code replay, không ghi sổ. Ledger/scorecard riêng, không trộn vào số liệu S1.

## Chỉ số tới 31/10 (thêm mục riêng trong báo cáo tuần)

- % ngày gửi trước 12:55
- số lần lỗi dữ liệu cũ
- tỷ lệ AI trưa đổi ý so với thẻ sáng
- số lần bị chặn vì đuổi giá
- số lệnh `UNVERIFIABLE_AFTERNOON_FILL`
- giá trị ví 2 trừ ví 1 từ cùng ngày bắt đầu
- Jev trưa: cùng ý / khác ý

Ghi rõ: khoảng 13 phiên **không đủ để chứng minh có lời hơn**.

## Test bắt buộc (RED trước GREEN)

- Morning path không đổi: AST các hàm sáng giữ nguyên, artifacts production giữ hash.
- Luật chống đuổi giá: case HPG 08/10 (giá vào 20.050 → giá trưa 20.350, tỷ lệ 1,84) phải bị chặn.
- Không hạ được mức cắt lỗ.
- Fill thận trọng: đáy cả ngày bằng đáy sáng → `UNVERIFIABLE`.
- Model lỗi → gửi midday cũ + cảnh báo; sau 13:30 không gửi.
- Jev:
  - cap chặn trước khi gọi;
  - Jev lỗi chỉ làm hỏng phần challenger;
  - không lộ key.
- Ví 2 xuất phát đúng bằng ví S1 ở ngày bắt đầu; ví S1 không đổi byte nào.
- Full suite + `issue_status.py --check` + `git diff --check`.

## Bằng chứng nộp kèm PR

- Preview offline từ dữ liệu thật 06–09/10. Không gọi model thật thì dùng mock có nhãn rõ; nếu gọi thật thì ghi số lượt và chi phí. Không gửi Telegram.
- Đo thời gian 9:30 thực tế (fetch → gửi) để đề xuất 12:45 hay 12:40.
- Chi phí và quota Sol cho lượt thứ 2 mỗi ngày: kiểm và ghi. Chưa rõ thì ghi UNVERIFIED.

## Quy trình

Thêm dòng issue-list → nhánh `feat/midday-ai-card` → PR draft → Claude Code review → Hưng GO merge → Hưng ff production + cài timer. Báo cáo cho Hưng phải **trích nguyên văn** preview, không diễn giải; kèm số test, commit hash, "what could still be wrong".
