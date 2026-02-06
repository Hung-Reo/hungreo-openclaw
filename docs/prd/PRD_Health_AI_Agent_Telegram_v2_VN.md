# PRD — Health AI Agent (Telegram)

**Phiên bản:** v2 (bổ sung safety, source governance, memory và error handling)  
**Trạng thái:** Draft (Ready-for-Dev)  
**Người sở hữu:** Hưng (Product Owner)  
**Cập nhật lần cuối:** 2025-12-14  
**Bổ sung insights:** 2025-02-04

---

## 1. Overview

Health AI Agent là trợ lý tra cứu sức khoẻ cho gia đình trên Telegram. Agent tổng hợp thông tin đa nguồn theo 3 góc nhìn: (1) Tây Y (evidence-based), (2) Đông Y / y học cổ truyền (theo nguồn khoa học đáng tin), và (3) Myth-busting để giúp người dùng hiểu – chọn – hành động an toàn. Agent không chẩn đoán, không kê đơn, không thay thế bác sĩ.

### 1.1 Principles

- **Simple**: Trả lời theo format cố định, dễ đọc trên Telegram.
- **Safe**: Có disclaimer, triage dấu hiệu nguy hiểm, ưu tiên hành vi an toàn.
- **Effective**: Cá nhân hoá theo hồ sơ; có trích dẫn nguồn trong whitelist; giảm hallucination/link ảo.
- **Neutral**: Không thiên vị Tây/Đông; không tạo "phác đồ lai".

---

## 2. Goals & Success Metrics

### 2.1 Goals

- Cung cấp thông tin sức khoẻ theo 3 góc nhìn (Tây Y / Đông Y / Myth-busting) để người dùng tự đánh giá.
- Cá nhân hoá câu trả lời dựa trên hồ sơ sức khoẻ (tuổi, bệnh nền, thuốc đang dùng, v.v.).
- Giảm rủi ro tin giả & mẹo dân gian gây hại bằng giải thích dễ hiểu và hành động thay thế an toàn.

### 2.2 Success Metrics (đề xuất)

- > = 95% câu trả lời có citation hợp lệ từ whitelist (domain match).
- 0 incident: AI chẩn đoán/kê đơn/khuyến nghị thay bác sĩ.
- > = 90% câu trả lời đúng format 4 blocks.
- Tỷ lệ "link lỗi/không truy cập được" < 2%.

---

## 3. Scope

### 3.1 In-scope

- Nhận diện người hỏi qua Chat_ID (Telegram) và map sang Member_ID trong Excel KB.
- Hỗ trợ hỏi cho người khác (theo Display_Name) với cơ chế disambiguation khi trùng/không rõ.
- Tra cứu nội dung trong whitelist và trích dẫn nguồn.
- Triage dấu hiệu nguy hiểm và đưa khuyến cáo hành động cân bằng (không hù quá mức).
- Memory: dùng 5 lượt chat gần nhất để hiểu context.

### 3.2 Out-of-scope

- Không tạo phác đồ điều trị hoặc kết hợp Đông–Tây thành một phác đồ mới.
- Không thay thế bác sĩ; không kê đơn/đổi liều thuốc; không đưa kết luận chẩn đoán chắc chắn.
- Không lấy nguồn ngoài whitelist (trừ khi được Product Owner cập nhật whitelist).

---

## 4. Deployment on Telegram

### 4.1 High-level Flow

1. Telegram Bot nhận message, đọc chat.id (Chat_ID).
2. Lookup Excel KB: Chat_ID -> Member_ID (người hỏi). Nếu hỏi cho người khác: Display_Name -> Member_ID.
3. Load memory buffer (5 chat gần nhất) theo Chat_ID.
4. Run safety triage để xác định mode: NORMAL / CAUTION / URGENT.
5. Retrieve nội dung theo whitelist (theo source governance) và generate câu trả lời theo format chuẩn.
6. Ghi log tối thiểu (không PII) + cập nhật memory.

### 4.2 Message format (Telegram)

Câu trả lời chuẩn gồm 4 blocks (trừ URGENT có thể ưu tiên cảnh báo trước):

- **Block 1 — Western Medicine (Evidence-based)**
- **Block 2 — Traditional Medicine (Scientific Traditional)**
- **Block 3 — Warnings / Myth-busting** (nguy cơ, sai lầm phổ biến)
- **Block 4 — Personalized Interaction Notes** (bệnh nền/thuốc/độ tuổi; mức độ chắc chắn)

---

## 5. Data Model (Excel KB)

Excel KB là nguồn dữ liệu nội bộ để cá nhân hoá. Tối thiểu cần các trường sau (có thể mở rộng):

- **Chat_ID** (Telegram) — khóa nhận diện người dùng
- **Member_ID** — mã thành viên gia đình
- **Display_Name** — tên gọi trong gia đình (ví dụ: Bố, Mẹ, Ông Ngoại, Bé...)
- **Age, Sex**
- **Chronic_conditions** (bệnh nền)
- **Current_medications** (thuốc đang dùng)
- **Allergies** (dị ứng)
- **Mental_state / stress_notes** (tuỳ chọn)
- **Notes / constraints** (tuỳ chọn)

---

## 6. Source Governance & Whitelist

### 6.1 Governance Principles

- **Domain-only**: Chỉ sử dụng và trích dẫn link thuộc whitelist domains.
- **Evidence ranking**: Ưu tiên guideline / systematic review > RCT > observational > expert summary.
- **Freshness**: Ưu tiên tài liệu cập nhật trong 5 năm gần đây nếu có (đặc biệt cho guideline).
- **Claim-level citation**: Mỗi luận điểm quan trọng phải có 1 citation (1-2 link).
- **No link, no claim**: Nếu không có nguồn phù hợp trong whitelist thì không khẳng định mạnh; chuyển sang nêu giới hạn + khuyến cáo hỏi bác sĩ.

### 6.2 Do / Don't

| DO                                                          | DON'T                                            |
| ----------------------------------------------------------- | ------------------------------------------------ |
| Ưu tiên nguồn bằng chứng mạnh (guideline/systematic review) | Trích blog/diễn đàn/social media ngoài whitelist |
| Ghi rõ mức độ chắc chắn (High/Medium/Low) khi evidence yếu  | Chẩn đoán chắc chắn, kê đơn, đổi liều thuốc      |
| Dùng ngôn từ trung tính, tôn trọng, dễ hiểu                 | Trộn Tây/Đông thành "phác đồ lai"                |
| Luôn kèm disclaimer và khuyến cáo y tế phù hợp              | Bịa link hoặc nêu claim không có nguồn           |

### 6.3 Whitelist (chuẩn hoá theo domain)

Danh sách dưới đây là whitelist mặc định. Mọi thay đổi cần Product Owner phê duyệt.

| Group                | Domain                   | Notes / Allowed use                                |
| -------------------- | ------------------------ | -------------------------------------------------- |
| Western Medicine     | pubmed.ncbi.nlm.nih.gov  | Bài nghiên cứu/abstract; ưu tiên review/systematic |
| Western Medicine     | ncbi.nlm.nih.gov         | NCBI Bookshelf/PMC khi phù hợp                     |
| Western Medicine     | www.cochranelibrary.com  | Systematic review/meta-analysis                    |
| Western Medicine     | www.who.int              | Public health guidance/guideline                   |
| Western Medicine     | www.mayoclinic.org       | Patient education (high-quality)                   |
| Western Medicine     | www.nhs.uk               | Patient guidance (high-quality)                    |
| Western Medicine     | moh.gov.vn               | Thông tin/y tế công cộng Việt Nam                  |
| Western Medicine     | www.has-sante.fr         | Guideline/khuyến cáo y tế (FR)                     |
| Western Medicine     | www.vidal.fr             | Monograph/thuốc (FR)                               |
| Traditional Medicine | www.nccih.nih.gov        | NIH NCCIH - evidence-based CAM                     |
| Traditional Medicine | vienduoclieu.org.vn      | Thông tin dược liệu (VN)                           |
| Traditional Medicine | www.sciencedirect.com    | Giới hạn: review/monograph về herbal/traditional   |
| Myth-busting         | www.snopes.com           | Fact-check (ưu tiên health-related)                |
| Myth-busting         | sciencebasedmedicine.org | Phản biện khoa học (health claims)                 |
| Myth-busting         | vfa.gov.vn               | Cục An toàn thực phẩm (VN)                         |

### 6.4 Myth-busting Policy & Rationale (vì sao không khuyến khích mẹo dân gian)

Agent có nhiệm vụ Myth-busting để giảm rủi ro người dùng làm theo "mẹo dân gian" không phù hợp. Mục tiêu không phải là chê bai niềm tin, mà là giúp người dùng hiểu rủi ro và chọn hành động an toàn hơn.

#### 6.4.1 Vì sao "mẹo dân gian" thường không phù hợp

- **Thiếu bằng chứng kiểm chứng**: nhiều mẹo dựa trên trải nghiệm cá nhân, khó biết hiệu quả thật hay trùng hợp.
- **Không rõ liều lượng/chống chỉ định/tương tác**: dễ dùng sai đối tượng (trẻ em, người già, bệnh nền) hoặc tương tác với thuốc đang dùng.
- **Rủi ro trì hoãn xử lý y tế**: nguy hiểm nhất là tin mẹo khiến bỏ lỡ thời điểm đi khám phù hợp, đặc biệt khi có dấu hiệu nặng.
- **Có thể gây tác hại phụ**: kích ứng, bỏng, dị ứng, ảnh hưởng gan/thận hoặc làm nặng triệu chứng.
- **Dễ bị thổi phồng và lan truyền sai** trên mạng xã hội, thiếu điều kiện áp dụng cụ thể.

#### 6.4.2 Nguyên tắc truyền thông khi bác bỏ mẹo

- **Tôn trọng**: ghi nhận đây là kinh nghiệm truyền miệng/niềm tin phổ biến.
- **Giải thích ngắn** 1-2 lý do rủi ro (bằng chứng/liều/tương tác/trì hoãn).
- **Đưa lựa chọn thay thế an toàn hơn** (hành động cụ thể).
- **Nhắc điều kiện cần đi khám** khi có dấu hiệu cảnh báo.

#### 6.4.3 Do/Don't riêng cho mẹo dân gian

- **DO**: giải thích theo cơ chế rủi ro; ưu tiên nguồn trong whitelist; dùng giọng điệu nhẹ nhàng để tránh phản ứng phòng vệ.
- **DON'T**: khẳng định tuyệt đối "mẹo nào cũng sai"; chế giễu niềm tin; đưa ra một "mẹo mới" thay cho mẹo cũ.

#### 6.4.4 Output structure cho Myth-busting block

1. Nhắc lại mẹo/niềm tin đang được hỏi (để xác nhận hiểu đúng).
2. Nêu vì sao mẹo có thể không phù hợp (1-2 lý do chính).
3. Đề xuất thay thế an toàn hơn (hành động cụ thể).
4. Nếu có red flags: nhắc điều kiện cần đi khám.

---

## 7. Safety & Disclaimer

### 7.1 Master Disclaimer (bắt buộc)

> "Lưu ý: Nội dung dưới đây do AI tổng hợp từ nguồn y khoa trong whitelist và có thể không chính xác hoặc không phù hợp với tình trạng cá nhân của bạn. Đây không phải chẩn đoán hay kê đơn. Nếu bạn cần lời khuyên chính xác nhất cho trường hợp cụ thể, hãy liên hệ bác sĩ/cơ sở y tế."

### 7.2 Triage levels (không hù quá, nhưng đủ 'hù vừa liều')

- **NORMAL**: không có dấu hiệu nguy hiểm -> trả theo 4 blocks chuẩn.
- **CAUTION**: có dấu hiệu cần theo dõi sớm -> thêm khuyến nghị theo dõi và mốc thời gian (X giờ/ngày).
- **URGENT** (red-flag): có triệu chứng nguy hiểm -> đưa cảnh báo ưu tiên với giọng bình tĩnh, hành động rõ ràng.

### 7.3 URGENT template (đề xuất)

> "Mình không muốn làm bạn hoảng, nhưng với mô tả này có thể là dấu hiệu cần được đánh giá y tế sớm. Vì an toàn, bạn nên liên hệ cơ sở y tế gần nhất hoặc gọi cấp cứu nếu triệu chứng đang diễn tiến nhanh/nặng. Trong lúc chờ hỗ trợ, tránh tự dùng thêm thuốc mới."

---

## 8. Memory: 5 chat gần nhất

### 8.1 Definition

- Lưu 5 lượt chat gần nhất theo Chat_ID (khuyến nghị lưu cả user + assistant turns).
- Dùng để hiểu context: triệu chứng đang tiếp diễn hay mới, ai là người được hỏi, đã thử biện pháp gì.
- Nếu context mâu thuẫn (ví dụ lúc thì hỏi cho bé, lúc hỏi cho bố) -> hỏi lại 1 câu để xác nhận.

### 8.2 Storage & privacy

- **Store**: Redis/SQLite/Postgres tuỳ hạ tầng; key = Chat_ID.
- **Retention**: rolling TTL đề xuất 30 ngày.
- **Không log PII nhạy cảm** trong memory/log; ưu tiên tóm tắt ngắn (summary) thay vì raw text.

---

## 9. Functional Requirements

### FR-01 — Implicit question (hỏi cho chính mình)

Agent nhận diện Chat_ID, map Member_ID và lấy hồ sơ; trả lời theo format chuẩn.

**Acceptance criteria:**

- Nếu Chat_ID hợp lệ -> load profile và memory, sau đó trả lời 4 blocks.
- Output có disclaimer và có citation từ whitelist.

### FR-02 — Explicit question (hỏi cho người khác)

Nếu user nhắc Display_Name (ví dụ: Ông Ngoại), agent tìm Member_ID tương ứng.

**Acceptance criteria:**

- Nếu match đúng 1 người -> trả lời theo hồ sơ người đó.
- Nếu không match hoặc match nhiều người -> kích hoạt FR-05 disambiguation.

### FR-03 — Output layout 4 blocks

Cấu trúc trả lời chuẩn để người dùng scan nhanh trên Telegram.

**Acceptance criteria:**

- Block 1/2/3/4 theo thứ tự cố định (trừ URGENT).
- Mỗi luận điểm quan trọng có ít nhất 1 citation từ whitelist.
- Ngôn từ trung tính; không kê đơn; không kết luận chẩn đoán chắc chắn.

### FR-04 — Error handling: Chat_ID không tìm thấy trong Excel

Nếu Chat_ID không tồn tại trong Excel KB, agent phải từ chối trả lời y tế vì lý do bảo mật.

**Acceptance criteria:**

- Không trả nội dung y tế; trả message onboarding/bảo mật.
- Message nêu rõ cần admin thêm Chat_ID vào Excel để kích hoạt.
- Sự kiện được log (event=UNREGISTERED_CHAT_ID) không chứa PII.

### FR-05 — Disambiguation khi hỏi cho người khác

Nếu Display_Name trùng nhiều người hoặc không rõ, agent hỏi lại 1 câu để chốt đúng đối tượng.

**Acceptance criteria:**

- Nếu match nhiều -> hiển thị danh sách lựa chọn ngắn (kèm tuổi/đặc điểm tối thiểu).
- Nếu user không trả lời rõ -> fallback trả cho chủ chat và nêu rõ giả định.

### FR-06 — Safety triage & escalation

Agent phải phát hiện dấu hiệu nguy hiểm và ưu tiên khuyến cáo hành vi an toàn, không gây hoảng loạn.

**Acceptance criteria:**

- Nếu URGENT -> hiển thị cảnh báo ưu tiên + template bình tĩnh + khuyến cáo liên hệ y tế.
- Không nêu chẩn đoán chắc chắn; không dùng ngôn từ giật gân.
- Ghi log event triage mode (NORMAL/CAUTION/URGENT).

### FR-07 — Memory 5 chat gần nhất

Agent dùng context 5 chat gần nhất để trả lời nhất quán và giảm hỏi lại.

**Acceptance criteria:**

- Nếu có context -> tóm tắt ngắn trước khi trả lời.
- Nếu context mâu thuẫn -> hỏi lại 1 câu để xác nhận.
- Memory không lưu PII nhạy cảm; có TTL/retention.

---

## 10. Non-functional Requirements

- **Privacy & anonymity**: xử lý theo ID; không hiển thị/ghi log dữ liệu nhạy cảm không cần thiết.
- **Latency (Telegram)**: mục tiêu phản hồi < 8–12 giây (tuỳ infra).
- **Reliability**: graceful degradation khi thiếu nguồn/KB lỗi.
- **Security**: bot token được bảo vệ; rate-limit chống spam; hạn chế prompt injection.
- **Observability**: log triage mode, whitelist hit rate, lookup failures, latency.

---

## Appendix A — Standard Response Template

**Template (NORMAL/CAUTION):**

```
Block 1 — Western Medicine (Evidence-based)
- ... (có citation)

Block 2 — Traditional Medicine (Scientific Traditional)
- ... (có citation)

Block 3 — Warnings / Myth-busting
- ... (rationale ngắn + hành động thay thế)

Block 4 — Personalized Interaction Notes
- ... (theo profile; mức độ chắc chắn)

Disclaimer
- ...
```

---

## Appendix B — Error Message Templates

### B1) Unregistered Chat_ID:

> "Mình chưa nhận diện được tài khoản này trong danh sách gia đình (Chat_ID chưa đăng ký). Để bảo mật, mình chưa thể trả lời nội dung sức khoẻ. Bạn hãy nhờ admin thêm Chat_ID vào file Excel."

### B2) Ambiguous person:

> "Mình thấy có nhiều người trùng tên/định danh. Bạn muốn mình trả lời cho ai? (1) ..., (2) ..."

---

## Appendix C — Open Decisions

- **Onboarding**: ai là admin cập nhật Chat_ID/Member_ID? Manual Excel hay Google Sheet?
- **Memory**: lưu 5 turns (user+assistant) hay 5 user messages?
- **URGENT wording**: có dùng cụm "gọi 115" hay chỉ "liên hệ cơ sở y tế/cấp cứu" (tuỳ mức 'hù vừa liều').

---

## Appendix D — Phân tích Đối thủ Cạnh tranh

_Bổ sung ngày: 2025-02-04_

### D.1 Tổng quan ChatGPT Health (Ra mắt 8/1/2026)

OpenAI vừa ra mắt **ChatGPT Health** ngày 8/1/2026 - một không gian riêng (dedicated space) trong ChatGPT cho các cuộc trò chuyện về sức khỏe:

**Tính năng chính:**

- Không gian sức khỏe riêng biệt trong ChatGPT
- Tích hợp hồ sơ bệnh án + ứng dụng wellness (Apple Health, MyFitnessPal, Peloton, Instacart, Function, Weight Watchers)
- Bảo mật: Lưu trữ riêng biệt, không dùng để train model
- Hợp tác với b.well (nền tảng kết nối dữ liệu sức khỏe)
- Có sẵn cho người dùng Free/Go/Plus/Pro

**Tình trạng hiện tại:**

- Đang triển khai dần (có waitlist)
- Loại trừ: EEA, Thụy Sĩ, Anh
- **Tình trạng Việt Nam**: Có khả năng available nhưng OpenAI chưa confirm chính thức

**Quy mô:**

- 230 triệu người dùng/tuần hỏi câu hỏi sức khỏe toàn cầu
- 40 triệu người dùng/ngày (từ báo cáo OpenAI)

**Hạn chế:**

- Không dùng cho chẩn đoán/điều trị (disclaimer tương tự như của chúng ta)
- Chỉ tập trung Tây y
- Không tối ưu hóa tiếng Việt/văn hóa Việt
- Không có trên Telegram
- Format trả lời tự do (không có cấu trúc blocks rõ ràng)

### D.2 Khả năng Sức khỏe của Claude AI (Anthropic)

**Tình trạng hiện tại:** ❌ KHÔNG có sản phẩm sức khỏe cho người tiêu dùng

**Những gì đang có:**

- **Claude for Life Sciences** (T10/2025) - Tập trung doanh nghiệp/nhà nghiên cứu
  - Đối tượng: Công ty dược phẩm, nghiên cứu lâm sàng
  - Use cases: Hồ sơ quy định, phát triển thuốc, phân tích dữ liệu lâm sàng
  - Khách hàng: Sanofi, Komodo Health, 10x Genomics
  - KHÔNG phải sản phẩm cho người tiêu dùng

**Triển vọng tương lai:**

- Anthropic có sự kiện về healthcare (12/1/2026 - SF)
- Chưa có tín hiệu về tính năng sức khỏe cho người tiêu dùng
- Vẫn tập trung vào doanh nghiệp/nghiên cứu

### D.3 Tình trạng Google & Microsoft

**Google:**

- Hợp tác với b.well (T10/2025) - có thể tích hợp trong tương lai
- ❌ Gemini Health chưa có thông báo
- Tập trung: Giáo dục (Gemini for Education)

**Microsoft:**

- ❌ Chưa có sản phẩm AI sức khỏe cho người tiêu dùng
- Tập trung: Copilot cho nhiều lĩnh vực khác nhau, chưa có sức khỏe

### D.4 Ma trận So sánh Cạnh tranh

| Yếu tố                    | ChatGPT Health    | Health AI Agent (Của chúng ta)          | Lợi thế                             |
| ------------------------- | ----------------- | --------------------------------------- | ----------------------------------- |
| **Góc nhìn**              | Chỉ Tây y         | 3 góc nhìn (Tây + Đông + Phá bỏ mê tín) | ✅ **Của chúng ta**                 |
| **Thị trường mục tiêu**   | Toàn cầu          | Tập trung Việt Nam                      | ✅ **Của chúng ta**                 |
| **Nền tảng**              | ChatGPT (web/iOS) | Telegram                                | ✅ **Của chúng ta** (thị trường VN) |
| **Hệ thống An toàn**      | Disclaimer chung  | Phân loại 3 cấp + whitelist             | ✅ **Của chúng ta**                 |
| **Cá nhân hóa**           | Tích hợp ứng dụng | Hồ sơ gia đình (Excel KB)               | ✅ **Của chúng ta**                 |
| **Format Trả lời**        | Tự do             | 4 blocks có cấu trúc                    | ✅ **Của chúng ta**                 |
| **Nguồn Tiếng Việt**      | Không có          | moh.gov.vn, vfa.gov.vn, vienduoclieu    | ✅ **Của chúng ta**                 |
| **Nhận diện Thương hiệu** | OpenAI/ChatGPT    | Sản phẩm mới                            | ❌ ChatGPT                          |
| **Quy mô/Hạ tầng**        | Khổng lồ          | Startup                                 | ❌ ChatGPT                          |
| **Bảo mật Dữ liệu**       | Tại Mỹ            | Có thể host tại VN                      | ⚖️ Tùy thuộc                        |

### D.5 Đánh giá Cơ hội Thị trường

**Tại sao Health AI Agent có thể thắng ở thị trường Việt Nam:**

1. **Phù hợp Văn hóa:**
   - Y học cổ truyền (Đông y) đóng vai trò lớn trong healthcare VN
   - Quyết định sức khỏe theo gia đình → tính năng hồ sơ gia đình của chúng ta
   - Telegram phổ biến hơn ChatGPT ở Việt Nam
   - Tối ưu hóa ngôn ngữ/nguồn tiếng Việt

2. **Cửa sổ Thời gian:**
   - ChatGPT Health mới ra (1/2026) - vẫn chưa mature
   - Chưa bản địa hóa cho thị trường Việt Nam
   - Không có góc nhìn Y học Cổ truyền
   - Cửa sổ lợi thế người đi trước: **3-6 tháng**

3. **Điểm khác biệt Kỹ thuật:**
   - Quản lý nguồn với whitelist đặc thù VN
   - Phân loại an toàn 3 cấp (chi tiết hơn ChatGPT)
   - Phá bỏ mê tín phù hợp với mẹo dân gian Việt Nam
   - Telegram-first (vs ChatGPT chỉ có web/iOS)

4. **Các yếu tố Rủi ro:**
   - OpenAI có thể mở rộng sang VN + thêm Đông y
   - Google/Anthropic có thể ra sản phẩm cạnh tranh
   - Hạn chế nguồn lực vs Big Tech

**Chiến lược Đề xuất:**

- ✅ **Tăng tốc phát triển** - tận dụng lợi thế người đi trước
- ✅ **Xây dựng niềm tin cộng đồng** với người dùng Việt Nam sớm
- ✅ **Nhấn mạnh điểm khác biệt địa phương** trong marketing
- ✅ **Học hỏi UX của ChatGPT Health** để áp dụng best practices
- ⏰ **Mục tiêu Timeline**: Ra mắt MVP trong 7-14 ngày (trước khi ChatGPT Health có chỗ đứng tại VN)

### D.6 Yêu cầu Theo dõi

**Checklist Theo dõi Đối thủ:**

- [ ] Theo dõi triển khai ChatGPT Health tại Việt Nam
- [ ] Theo dõi cập nhật tính năng (có thêm y học cổ truyền không?)
- [ ] Theo dõi thông báo từ Google/Anthropic
- [ ] Phân tích phản hồi người dùng về ChatGPT Health (Reddit, Twitter)
- [ ] Theo dõi sự chấp nhận công cụ AI sức khỏe ở thị trường VN

**Tần suất Cập nhật:** Scan đối thủ hàng tuần

---

## Appendix E — Kinh nghiệm Triển khai từ Lịch sử Phát triển

_Bổ sung ngày: 2025-02-04 - Tổng hợp từ lịch sử chat phát triển_

### E.1 Quyết định Công nghệ

**Stack Cuối cùng (tính đến 29/12/2025):**

| Thành phần             | Công nghệ                                   | Lý do                                               |
| ---------------------- | ------------------------------------------- | --------------------------------------------------- |
| **Công cụ Workflow**   | n8n (Docker)                                | Đã có bot Personal-Assistant hoạt động tốt          |
| **Mô hình AI**         | Claude (chính) + GPT (dự phòng)             | Claude MCP có sẵn trong n8n                         |
| **API Tìm kiếm**       | Tavily (Free tier)                          | Hỗ trợ `include_domains` để bắt buộc whitelist      |
| **Cơ sở dữ liệu**      | Google Sheets                               | Tích hợp OAuth2, thân thiện gia đình, không cần SQL |
| **Memory**             | n8n Memory Buffer                           | Có sẵn, xử lý context 5 chat                        |
| **Hosting**            | Docker local + Render (production)          | Setup đã chứng minh từ Personal-Assistant           |
| **Công cụ Phát triển** | Claude Code, Claude.ai, Codex, Gemini 3 Pro | Phương pháp đa công cụ cho vibe coding              |

### E.2 Các Thành phần Tái sử dụng từ Bot Personal-Assistant

**Workflow: Hungreo_BĐS_bot** (có thể clone/chỉnh sửa)

**Các Thành phần Hiện có (✅ Tái sử dụng):**

- Telegram Trigger + Response nodes
- Kiểm tra bảo mật (kiểm tra người dùng được ủy quyền)
- Voice-to-Text (phiên âm OpenAI Whisper)
- AI Agent với Memory Buffer
- Tích hợp tìm kiếm Perplexity/Tavily
- Ghi log Google Sheets
- Error handling wrapper

**Các Thành phần Mới Cần thiết (🆕 Xây dựng):**

- Tra cứu Excel KB (Chat_ID → Member_ID → Profile)
- Logic phân loại an toàn (phát hiện NORMAL/CAUTION/URGENT)
- Định dạng response 4 blocks
- Bộ lọc domain whitelist cho Tavily
- Luồng disambiguation (nhiều Display_Names)

### E.3 Phân tích Lựa chọn Công cụ Tìm kiếm

**Yêu cầu:**

- Phải hỗ trợ lọc domain whitelist
- Nguồn y tế chất lượng
- Hiệu quả về chi phí cho MVP
- Tích hợp n8n dễ dàng

**Các Lựa chọn Đã đánh giá:**

| Công cụ              | Ưu điểm                                                                             | Nhược điểm                                                   | Quyết định     |
| -------------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------------ | -------------- |
| **Tavily API**       | ✅ Tham số `include_domains`<br>✅ Free tier có sẵn<br>✅ Tương thích HTTP node n8n | ⚠️ Không chuyên về y tế                                      | ✅ **ĐÃ CHỌN** |
| PubMed API           | ✅ Chuyên về y tế<br>✅ Miễn phí                                                    | ❌ Không có thông tin sức khỏe tổng quát<br>❌ Chỉ tiếng Anh | ⏸️ Bổ sung     |
| Perplexity           | ✅ Tóm tắt tốt<br>✅ Đã tích hợp                                                    | ❌ Không lọc domain chặt chẽ                                 | ⏸️ Dự phòng    |
| Google Custom Search | ✅ Kiểm soát hoàn toàn                                                              | ❌ Phức tạp setup<br>❌ Có phí                               | ❌             |

**Quyết định Cuối cùng:**

- **Chính:** Tavily API với tham số `include_domains`
- **Lý do:** Công cụ duy nhất có thể bắt buộc tuân thủ whitelist 100% qua API
- **Triển khai:** Truyền 15 domains đã whitelist dưới dạng array trong API call

### E.4 Chiến lược Tái sử dụng Kiến trúc

**Phương pháp Clone & Mở rộng:**

```
Personal-Assistant (Hungreo_BĐS_bot)
├─ Telegram Trigger ─────────► ✅ TÁI SỬ DỤNG (không thay đổi)
├─ Security Check ───────────► ✅ TÁI SỬ DỤNG (sửa logic whitelist)
├─ Voice-to-Text ────────────► ✅ TÁI SỬ DỤNG (tùy chọn cho Health)
├─ Memory Buffer ────────────► ✅ TÁI SỬ DỤNG (context 5 chat)
├─ AI Agent ─────────────────► 🔄 CHỈNH SỬA (thêm tools + system prompt)
│  ├─ Search Tool ───────────► 🆕 THÊM (Tavily whitelist)
│  ├─ KB Lookup Tool ────────► 🆕 THÊM (Google Sheets query)
│  └─ Triage Tool ───────────► 🆕 THÊM (phân loại an toàn)
├─ Response Formatter ───────► 🆕 XÂY DỰNG (cấu trúc 4 blocks)
└─ Google Sheets Log ────────► ✅ TÁI SỬ DỤNG (mở rộng schema)
```

### E.5 Timeline Phát triển (Ước tính)

**Giai đoạn 1: Nền tảng (Ngày 1-2)**

- Clone workflow từ Personal-Assistant
- Setup Google Sheets KB với schema (Mục 5)
- Cấu hình Tavily API với whitelist
- Test luồng cơ bản Telegram → Google Sheets → Response

**Giai đoạn 2: Logic Cốt lõi (Ngày 3-4)**

- Triển khai tra cứu Chat_ID → Member_ID
- Xây dựng prompt phân loại an toàn
- Tạo định dạng response 4 blocks
- Tích hợp memory với context sức khỏe

**Giai đoạn 3: Tính năng Nâng cao (Ngày 5-6)**

- Luồng disambiguation (xung đột Display_Name)
- Xử lý lỗi (FR-04: người dùng chưa đăng ký)
- Testing với câu hỏi sức khỏe mẫu
- Tinh chỉnh dựa trên chất lượng output

**Giai đoạn 4: Hoàn thiện & Triển khai (Ngày 7)**

- Testing cuối cùng (tất cả FRs)
- Cập nhật tài liệu
- Deploy lên Render
- Giai đoạn testing với gia đình

**Tổng Timeline Ước tính:** 7 ngày (phát triển tập trung)

### E.6 Ghi chú Triển khai Quan trọng

**Từ Thảo luận Phát triển:**

1. **Bắt buộc Whitelist:**
   - Dùng tham số `include_domains` của Tavily
   - Truyền tất cả 15 domains dưới dạng JSON array
   - Fallback sang Perplexity nếu Tavily fail (với kiểm tra domain thủ công)

2. **Chiến lược Memory:**
   - Lưu 5 cặp message user+assistant gần nhất
   - Key theo Chat_ID
   - TTL: 30 ngày rolling
   - Chế độ tóm tắt (không lưu text thô có PII)

3. **Schema Google Sheets:**
   - Tab 1: Hồ sơ Thành viên (Chat_ID, Member_ID, Display_Name, Age, Conditions, Medications...)
   - Tab 2: Chat Logs (timestamp, Chat_ID, Member_ID, query, triage_mode, response_preview)
   - Tab 3: Error Events (timestamp, Chat_ID, error_type, message)

4. **Cấu hình AI Agent:**
   - System prompt: Bao gồm tất cả nguyên tắc PRD (3 góc nhìn, an toàn, giọng điệu trung tính)
   - Tools: Tavily search, Google Sheets lookup, Calculator (cho câu hỏi liều lượng)
   - Temperature: 0.3 (thận trọng cho thông tin sức khỏe)
   - Max tokens: 2000 (cấu trúc 4 blocks cần không gian)

5. **Chiến lược Testing:**
   - Test cases: NORMAL (đau đầu), CAUTION (sốt kéo dài), URGENT (đau ngực)
   - Kịch bản gia đình: User hỏi cho bản thân, hỏi cho "Bố", hỏi cho "Bé" (không rõ ràng)
   - Kịch bản lỗi: Chat_ID chưa đăng ký, KB trống, Tavily API down

### E.7 URL Workflow n8n (Tham khảo)

**Instance Production:**

- URL: https://ai-agent-n8n-8jq7.onrender.com
- Workflow ID: `8KvfGZomUAbYdrlI` (Personal-Assistant - clone từ đây)
- Truy cập: OAuth2 protected, kiểm tra Render dashboard để lấy credentials

**Phát triển Local:**

- Docker: `localhost:5678`
- Workflow export: Lưu JSON trước khi thay đổi lớn
- Version control: Khuyến nghị backup Google Drive

### E.8 Câu hỏi Mở & Log Quyết định

**Đã Giải quyết:**

- ✅ Công cụ tìm kiếm: Tavily (với whitelist)
- ✅ Database: Google Sheets
- ✅ Mô hình AI: Claude chính, GPT dự phòng
- ✅ Timeline: 7 ngày tập trung

**Vẫn Mở (tính đến 1/2026):**

- ⏳ Cách diễn đạt URGENT: "gọi 115" vs "liên hệ cơ sở y tế" (xem Appendix C)
- ⏳ Luồng Admin: Cách onboard Chat_IDs mới (thủ công vs form)
- ⏳ Memory: 5 user messages vs 5 cặp user+assistant (khuyến nghị cặp)
- ⏳ Monitoring: Metrics nào cần track trong Google Sheets logs

**Cải tiến Tương lai (Sau MVP):**

- Tích hợp wearables (Apple Health, Fitbit)
- Tùy chọn phản hồi bằng giọng nói (TTS)
- Hỗ trợ đa ngôn ngữ (Tiếng Anh + Tiếng Việt)
- Web dashboard cho quản lý gia đình

---

## Lịch sử Thay đổi Tài liệu

| Ngày       | Phiên bản | Thay đổi                                                                  | Tác giả |
| ---------- | --------- | ------------------------------------------------------------------------- | ------- |
| 2025-12-14 | 2.0       | Bản thảo PRD ban đầu với safety & source governance                       | Hưng    |
| 2025-02-04 | 2.1       | Thêm Appendix D (Phân tích Đối thủ) + Appendix E (Kinh nghiệm Triển khai) | Hưng    |

---

**Hết Tài liệu**
