# System Analysis & Design Document

# Health AI Agent (Telegram)

| Document     | SAD — Health AI Agent |
| ------------ | --------------------- |
| Version      | 1.0                   |
| Status       | Draft                 |
| Based on     | PRD v2.0 (2025-12-14) |
| Author       | System Analyst        |
| Last updated | 2025-12-25            |

---

## 1. Executive Summary

### 1.1 Mục tiêu

Thiết kế hệ thống Health AI Agent trên Telegram để tra cứu thông tin sức khỏe theo 3 góc nhìn (Tây Y, Đông Y, Myth-busting), có cá nhân hóa theo hồ sơ gia đình, đảm bảo **Simple, Safe, Effective**.

### 1.2 Nguyên tắc thiết kế

- **Simple**: Reuse existing Personal-Assistant architecture, minimize new components
- **Safe**: Whitelist-only sources, safety triage, no diagnosis/prescription
- **Effective**: Personalized responses, citation-backed, fast response (<12s)

---

## 2. System Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           HEALTH AI AGENT SYSTEM                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────┐     ┌──────────────────────────────────────────────────────┐ │
│  │ Telegram │     │                    n8n WORKFLOW                      │ │
│  │   User   │────▶│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐ │ │
│  │          │     │  │ Trigger │─▶│Security │─▶│ Member  │─▶│ Safety  │ │ │
│  │          │     │  │         │  │  Check  │  │ Lookup  │  │ Triage  │ │ │
│  │          │     │  └─────────┘  └─────────┘  └─────────┘  └────┬────┘ │ │
│  │          │     │                                               │      │ │
│  │          │     │  ┌─────────┐  ┌─────────┐  ┌─────────┐       │      │ │
│  │          │◀────│  │Response │◀─│ Format  │◀─│   AI    │◀──────┘      │ │
│  │          │     │  │  Send   │  │ Output  │  │  Agent  │              │ │
│  └──────────┘     │  └─────────┘  └─────────┘  └────┬────┘              │ │
│                   │                                  │                   │ │
│                   └──────────────────────────────────┼───────────────────┘ │
│                                                      │                     │
│  ┌───────────────────────────────────────────────────┼───────────────────┐ │
│  │                      EXTERNAL SERVICES            │                   │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┴─┐  ┌───────────┐  │ │
│  │  │   Google    │  │   Tavily    │  │    Claude/    │  │  Memory   │  │ │
│  │  │   Sheets    │  │  (Search)   │  │     GPT       │  │  (Buffer) │  │ │
│  │  │   (KB)      │  │  Whitelist  │  │               │  │           │  │ │
│  │  └─────────────┘  └─────────────┘  └───────────────┘  └───────────┘  │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Component Overview

| Component      | Technology           | Purpose                      | Source  |
| -------------- | -------------------- | ---------------------------- | ------- |
| Trigger        | n8n Telegram Trigger | Nhận message từ user         | Reuse   |
| Security Check | n8n IF node          | Validate authorized Chat_ID  | Reuse   |
| Member Lookup  | n8n Google Sheets    | Map Chat_ID → Profile        | **NEW** |
| Safety Triage  | n8n Code + AI        | Detect NORMAL/CAUTION/URGENT | **NEW** |
| AI Agent       | n8n AI Agent node    | Generate response với tools  | Modify  |
| Search Tool    | Tavily API           | Search whitelist domains     | **NEW** |
| Memory         | n8n Memory Buffer    | Lưu 5 chat gần nhất          | Reuse   |
| Response       | n8n Telegram Send    | Gửi response về user         | Reuse   |

---

## 3. Data Flow

### 3.1 Main Flow (Happy Path)

```
[1] User gửi message Telegram
         │
         ▼
[2] Telegram Trigger nhận message
    - Extract: chat_id, text, message_type
         │
         ▼
[3] Security Check
    - IF chat_id IN authorized_list → Continue
    - ELSE → Send "Unauthorized" message → END
         │
         ▼
[4] Member Lookup (Google Sheets)
    - Query: Chat_ID → Member Profile
    - IF found → Load profile (age, conditions, medications...)
    - IF not found → Send "Unregistered" message (FR-04) → END
         │
         ▼
[5] Check "Hỏi cho ai?"
    - IF message contains Display_Name (e.g., "Ông Ngoại")
      → Lookup Display_Name → Member_ID
      → IF multiple matches → Disambiguation (FR-05)
    - ELSE → Use sender's profile
         │
         ▼
[6] Load Memory (5 chat gần nhất)
    - Key: Chat_ID
    - Check context conflict → Ask clarification if needed
         │
         ▼
[7] Safety Triage
    - Analyze message for red flags
    - Determine: NORMAL | CAUTION | URGENT
         │
         ▼
[8] AI Agent Processing
    ├── Tool 1: Tavily Search (whitelist domains)
    ├── Tool 2: Google Sheets (member profile)
    └── Generate response theo format 4 blocks
         │
         ▼
[9] Format Output
    - Apply template based on triage level
    - Add disclaimer
    - Validate citations (whitelist only)
         │
         ▼
[10] Send Response + Update Memory + Log
```

### 3.2 Error Flows

| Error Case                | Handler        | Output (PRD Reference)                            |
| ------------------------- | -------------- | ------------------------------------------------- |
| Chat_ID not authorized    | Security Check | "⛔ Unauthorized"                                 |
| Chat_ID not in KB         | Member Lookup  | FR-04: Onboarding message                         |
| Display_Name ambiguous    | Disambiguation | FR-05: List options                               |
| No whitelist source found | AI Agent       | "Không tìm thấy nguồn phù hợp" + recommend doctor |
| URGENT detected           | Safety Triage  | FR-06: Priority warning template                  |
| API timeout               | Error Handler  | Graceful degradation message                      |

---

## 4. Data Model

### 4.1 Google Sheets - Family KB

**Sheet name:** `family_members`

| Column              | Type     | Required | Description                | Example                            |
| ------------------- | -------- | -------- | -------------------------- | ---------------------------------- |
| Chat_ID             | String   | ✅       | Telegram chat ID           | "123456789"                        |
| Member_ID           | String   | ✅       | Unique member code         | "MEM001"                           |
| Display_Name        | String   | ✅       | Tên gọi trong gia đình     | "Bố", "Mẹ", "Bé Na"                |
| Age                 | Number   | ✅       | Tuổi                       | 45                                 |
| Sex                 | String   | ✅       | Giới tính                  | "M" / "F"                          |
| Chronic_conditions  | String   |          | Bệnh nền (comma-separated) | "Tiểu đường type 2, Cao huyết áp"  |
| Current_medications | String   |          | Thuốc đang dùng            | "Metformin 500mg, Lisinopril 10mg" |
| Allergies           | String   |          | Dị ứng                     | "Penicillin, Hải sản"              |
| Mental_state        | String   |          | Tình trạng tâm lý          | "Stress công việc"                 |
| Notes               | String   |          | Ghi chú khác               | "Ăn chay, tập yoga"                |
| Created_at          | DateTime | Auto     | Ngày tạo                   | 2025-01-01                         |
| Updated_at          | DateTime | Auto     | Ngày cập nhật              | 2025-12-25                         |

**Sheet name:** `chat_logs` (Optional - for analytics)

| Column           | Type     | Description                    |
| ---------------- | -------- | ------------------------------ |
| Log_ID           | String   | UUID                           |
| Chat_ID          | String   | Telegram chat ID               |
| Timestamp        | DateTime | Thời điểm                      |
| Triage_mode      | String   | NORMAL/CAUTION/URGENT          |
| Query_type       | String   | implicit/explicit              |
| Target_member    | String   | Member_ID được hỏi             |
| Whitelist_hit    | Boolean  | Có citation từ whitelist không |
| Response_time_ms | Number   | Latency                        |

### 4.2 Memory Structure

```javascript
// Memory Buffer (per Chat_ID)
{
  "chat_id": "123456789",
  "messages": [
    {
      "role": "user",
      "content": "Bé Na bị sốt 38.5 độ",
      "timestamp": "2025-12-25T10:00:00Z",
      "target_member": "MEM003"
    },
    {
      "role": "assistant",
      "content": "...",
      "timestamp": "2025-12-25T10:00:15Z",
      "triage_mode": "CAUTION"
    }
    // ... max 5 turns (10 messages)
  ],
  "last_updated": "2025-12-25T10:00:15Z"
}
```

---

## 5. Integration Specifications

### 5.1 Tavily Search API

**Purpose:** Search health information within whitelist domains only

**Endpoint:** `https://api.tavily.com/search`

**Configuration:**

```javascript
// Tavily Search Request
{
  "api_key": "${TAVILY_API_KEY}",
  "query": "vitamin D deficiency treatment",
  "search_depth": "advanced",
  "include_domains": [
    // Western Medicine
    "pubmed.ncbi.nlm.nih.gov",
    "ncbi.nlm.nih.gov",
    "www.cochranelibrary.com",
    "www.who.int",
    "www.mayoclinic.org",
    "www.nhs.uk",
    "moh.gov.vn",
    "www.has-sante.fr",
    "www.vidal.fr",
    // Traditional Medicine
    "www.nccih.nih.gov",
    "vienduoclieu.org.vn",
    "www.sciencedirect.com",
    // Myth-busting
    "www.snopes.com",
    "sciencebasedmedicine.org",
    "vfa.gov.vn"
  ],
  "max_results": 10
}
```

**Response Handling:**

```javascript
// Expected response structure
{
  "results": [
    {
      "title": "Vitamin D Deficiency - StatPearls",
      "url": "https://www.ncbi.nlm.nih.gov/books/NBK532266/",
      "content": "Vitamin D deficiency is defined as...",
      "score": 0.95
    }
  ]
}
```

**Fallback:** Nếu Tavily không tìm được kết quả trong whitelist → AI trả lời với disclaimer "không tìm thấy nguồn phù hợp trong whitelist"

### 5.2 Google Sheets API

**Credentials:** OAuth2 (n8n Google Sheets node)

**Operations:**

| Operation              | Sheet          | Filter                           | Output                 |
| ---------------------- | -------------- | -------------------------------- | ---------------------- |
| Lookup by Chat_ID      | family_members | `Chat_ID = {{chat_id}}`          | Single row (profile)   |
| Lookup by Display_Name | family_members | `Display_Name CONTAINS {{name}}` | Array (disambiguation) |
| Append log             | chat_logs      | N/A                              | Success/Fail           |

### 5.3 AI Model Configuration

**Primary:** Claude 3.5 Sonnet (via Anthropic API)
**Fallback:** GPT-4o-mini (via OpenAI API)

**System Prompt Structure:**

```markdown
# ROLE

Bạn là Health AI Agent - trợ lý tra cứu sức khỏe cho gia đình trên Telegram.

# PRINCIPLES

- Simple: Trả lời theo format cố định, dễ đọc
- Safe: Có disclaimer, không chẩn đoán/kê đơn
- Effective: Cá nhân hóa, trích dẫn nguồn whitelist
- Neutral: Không thiên vị Tây/Đông, không tạo phác đồ lai

# CONSTRAINTS (MUST NOT)

- ❌ Chẩn đoán chắc chắn
- ❌ Kê đơn hoặc đổi liều thuốc
- ❌ Trộn Tây/Đông thành "phác đồ lai"
- ❌ Dùng link ngoài whitelist
- ❌ Bịa link hoặc claim không có nguồn

# OUTPUT FORMAT (4 BLOCKS)

## Block 1 — Tây Y (Evidence-based)

[Thông tin từ Western Medicine sources]
📚 Nguồn: [link từ whitelist]

## Block 2 — Đông Y (Scientific Traditional)

[Thông tin từ Traditional Medicine sources]
📚 Nguồn: [link từ whitelist]

## Block 3 — Cảnh báo / Myth-busting

[Giải thích mẹo sai + hành động thay thế]

## Block 4 — Ghi chú cá nhân

[Dựa trên profile: tuổi, bệnh nền, thuốc đang dùng]
⚠️ Mức độ chắc chắn: [High/Medium/Low]

---

📋 **Lưu ý:** Nội dung trên do AI tổng hợp từ nguồn y khoa và có thể không chính xác. Đây không phải chẩn đoán hay kê đơn. Nếu cần lời khuyên chính xác, hãy liên hệ bác sĩ.

# TRIAGE MODES

- NORMAL: Trả lời 4 blocks chuẩn
- CAUTION: Thêm khuyến nghị theo dõi + mốc thời gian
- URGENT: Cảnh báo ưu tiên trước, giọng bình tĩnh

# URGENT TEMPLATE

"Mình không muốn làm bạn hoảng, nhưng với mô tả này có thể là dấu hiệu cần được đánh giá y tế sớm. Vì an toàn, bạn nên liên hệ cơ sở y tế gần nhất hoặc gọi cấp cứu nếu triệu chứng đang diễn tiến nhanh/nặng."

# CURRENT USER PROFILE

- Member: {{member_name}}
- Age: {{age}}
- Sex: {{sex}}
- Chronic conditions: {{chronic_conditions}}
- Current medications: {{current_medications}}
- Allergies: {{allergies}}

# MEMORY CONTEXT

{{last_5_chats}}
```

---

## 6. Safety Triage Logic

### 6.1 Red Flag Keywords (URGENT)

```javascript
const URGENT_KEYWORDS = {
  vi: [
    // Cardiac
    "đau ngực dữ dội",
    "khó thở đột ngột",
    "tim đập nhanh bất thường",
    // Neurological
    "đột quỵ",
    "liệt",
    "méo miệng",
    "nói ngọng đột ngột",
    "co giật",
    // Respiratory
    "không thở được",
    "tím tái",
    "ngạt thở",
    // Trauma
    "chảy máu nhiều",
    "gãy xương",
    "bất tỉnh",
    // Pediatric
    "bé không phản ứng",
    "sốt cao co giật",
    "bỏ bú hoàn toàn",
    // Other
    "ngộ độc",
    "tự tử",
    "tự gây thương tích",
  ],
};

const CAUTION_KEYWORDS = {
  vi: [
    "sốt cao trên 39",
    "sốt kéo dài",
    "đau đầu dữ dội",
    "nôn nhiều",
    "tiêu chảy nhiều",
    "mất nước",
    "phát ban lan rộng",
    "sưng phù",
    "đau bụng dữ dội",
  ],
};
```

### 6.2 Triage Decision Tree

```
INPUT: user_message
         │
         ▼
    ┌────────────────────┐
    │ Contains URGENT    │──YES──▶ Return "URGENT"
    │ keywords?          │
    └────────┬───────────┘
             │ NO
             ▼
    ┌────────────────────┐
    │ Contains CAUTION   │──YES──▶ Return "CAUTION"
    │ keywords?          │
    └────────┬───────────┘
             │ NO
             ▼
    ┌────────────────────┐
    │ Profile has high-  │──YES──▶ Return "CAUTION"
    │ risk conditions?   │         (elderly, pregnant, infant)
    └────────┬───────────┘
             │ NO
             ▼
        Return "NORMAL"
```

---

## 7. n8n Workflow Design

### 7.1 Node Inventory

| #   | Node Name          | Type               | Purpose                         |
| --- | ------------------ | ------------------ | ------------------------------- |
| 1   | Telegram Trigger   | telegramTrigger    | Receive messages                |
| 2   | Set Input          | set                | Extract chat_id, text           |
| 3   | Security Check     | if                 | Validate authorized users       |
| 4   | Unauthorized Msg   | telegram           | Send rejection                  |
| 5   | Member Lookup      | googleSheets       | Get profile by Chat_ID          |
| 6   | Check Registration | if                 | FR-04 handling                  |
| 7   | Unregistered Msg   | telegram           | Send onboarding message         |
| 8   | Parse Target       | code               | Detect "hỏi cho ai"             |
| 9   | Disambiguation     | code               | FR-05 handling                  |
| 10  | Load Memory        | memoryBufferWindow | Get 5 recent chats              |
| 11  | Safety Triage      | code               | Determine NORMAL/CAUTION/URGENT |
| 12  | AI Agent           | agent              | Main processing                 |
| 13  | Tavily Tool        | httpRequest (tool) | Search whitelist                |
| 14  | Format Output      | code               | Apply template                  |
| 15  | Send Response      | telegram           | Reply to user                   |
| 16  | Log Event          | googleSheets       | Append to chat_logs             |
| 17  | Error Handler      | errorTrigger       | Graceful degradation            |

### 7.2 Workflow Diagram

```
┌─────────────┐
│  Telegram   │
│   Trigger   │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  Set Input  │
└──────┬──────┘
       │
       ▼
┌─────────────┐     ┌──────────────────┐
│  Security   │─NO─▶│  Unauthorized    │──▶ END
│   Check     │     │     Message      │
└──────┬──────┘     └──────────────────┘
       │ YES
       ▼
┌─────────────┐     ┌──────────────────┐
│   Member    │─NOT─▶│  Unregistered   │──▶ END
│   Lookup    │FOUND │    Message      │
└──────┬──────┘     └──────────────────┘
       │ FOUND
       ▼
┌─────────────┐     ┌──────────────────┐
│   Parse     │─AMB─▶│ Disambiguation  │──┐
│   Target    │IGUOUS│    Message      │  │
└──────┬──────┘     └──────────────────┘  │
       │ CLEAR                             │
       ▼                                   │
┌─────────────┐                           │
│    Load     │◀──────────────────────────┘
│   Memory    │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   Safety    │
│   Triage    │
└──────┬──────┘
       │
       ▼
┌─────────────┐     ┌──────────────────┐
│  AI Agent   │────▶│  Tavily Search   │
│             │◀────│  (Whitelist)     │
└──────┬──────┘     └──────────────────┘
       │
       ▼
┌─────────────┐
│   Format    │
│   Output    │
└──────┬──────┘
       │
       ├──────────────────┐
       ▼                  ▼
┌─────────────┐    ┌─────────────┐
│    Send     │    │  Log Event  │
│  Response   │    │             │
└─────────────┘    └─────────────┘
```

---

## 8. Security Considerations

### 8.1 Authentication & Authorization

| Layer        | Mechanism                 | Implementation                   |
| ------------ | ------------------------- | -------------------------------- |
| Telegram Bot | Bot Token                 | Environment variable (encrypted) |
| User Auth    | Chat_ID whitelist         | Google Sheets lookup             |
| API Keys     | Tavily, OpenAI, Anthropic | n8n Credentials (encrypted)      |

### 8.2 Privacy & Data Protection

| Data Type      | Storage       | Retention     | Encryption |
| -------------- | ------------- | ------------- | ---------- |
| Chat_ID        | Google Sheets | Permanent     | At rest    |
| Health Profile | Google Sheets | Permanent     | At rest    |
| Chat Memory    | n8n Memory    | 30 days (TTL) | In transit |
| Logs           | Google Sheets | 90 days       | At rest    |

### 8.3 Prompt Injection Prevention

```javascript
// Input sanitization before AI processing
function sanitizeInput(text) {
  // Remove potential injection patterns
  const patterns = [
    /ignore previous instructions/gi,
    /disregard.*system prompt/gi,
    /you are now/gi,
    /act as/gi,
  ];

  let sanitized = text;
  patterns.forEach((p) => {
    sanitized = sanitized.replace(p, "[FILTERED]");
  });

  return sanitized;
}
```

---

## 9. Deployment Architecture

### 9.1 Local Development (Docker)

```yaml
# docker-compose.yml
version: "3.8"
services:
  n8n:
    image: n8nio/n8n:latest
    ports:
      - "5678:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD}
      - WEBHOOK_URL=http://localhost:5678/
    volumes:
      - n8n_data:/home/node/.n8n
    restart: unless-stopped

volumes:
  n8n_data:
```

### 9.2 Production (Render)

```yaml
# render.yaml (existing setup)
services:
  - type: web
    name: health-ai-agent
    env: docker
    dockerfilePath: ./Dockerfile
    envVars:
      - key: N8N_BASIC_AUTH_ACTIVE
        value: true
      - key: WEBHOOK_URL
        sync: false
```

### 9.3 Environment Variables

| Variable                  | Description            | Required |
| ------------------------- | ---------------------- | -------- |
| TELEGRAM_BOT_TOKEN        | Telegram Bot API token | ✅       |
| TAVILY_API_KEY            | Tavily search API key  | ✅       |
| ANTHROPIC_API_KEY         | Claude API key         | ✅       |
| OPENAI_API_KEY            | GPT fallback           | Optional |
| GOOGLE_SHEETS_CREDENTIALS | OAuth2 JSON            | ✅       |
| N8N_ENCRYPTION_KEY        | n8n encryption         | ✅       |

---

## 10. Testing Strategy

### 10.1 Test Scenarios

| ID  | Scenario            | Input                 | Expected Output               | FR    |
| --- | ------------------- | --------------------- | ----------------------------- | ----- |
| T01 | Normal query - self | "Tôi bị đau đầu"      | 4 blocks + disclaimer         | FR-01 |
| T02 | Query for other     | "Bố bị ho"            | 4 blocks (Bố's profile)       | FR-02 |
| T03 | Unregistered user   | New Chat_ID           | Onboarding message            | FR-04 |
| T04 | Ambiguous name      | "Bé bị sốt" (có 2 Bé) | Disambiguation options        | FR-05 |
| T05 | URGENT case         | "Bé co giật, sốt cao" | Priority warning first        | FR-06 |
| T06 | CAUTION case        | "Sốt 39.5 độ 2 ngày"  | 4 blocks + follow-up advice   | FR-06 |
| T07 | Memory context      | Follow-up question    | Reference previous chat       | FR-07 |
| T08 | No source found     | Obscure health topic  | Disclaimer + recommend doctor | 6.1   |

### 10.2 Performance Targets

| Metric                  | Target       | Measurement  |
| ----------------------- | ------------ | ------------ |
| Response latency        | < 12 seconds | End-to-end   |
| Whitelist citation rate | >= 95%       | Per response |
| Uptime                  | >= 99%       | Monthly      |
| Error rate              | < 2%         | Per request  |

---

## 11. Open Decisions (from PRD Appendix C)

| #   | Decision         | Options                                     | Recommendation                             | Status     |
| --- | ---------------- | ------------------------------------------- | ------------------------------------------ | ---------- |
| 1   | Onboarding admin | Manual Excel vs Google Sheet                | **Google Sheet** (real-time sync)          | ✅ Decided |
| 2   | Memory storage   | 5 turns (user+assistant) vs 5 user messages | **5 turns** (10 messages total)            | ✅ Decided |
| 3   | URGENT wording   | "gọi 115" vs "liên hệ cơ sở y tế"           | **"liên hệ cơ sở y tế/cấp cứu"** (generic) | ✅ Decided |
| 4   | Search tool      | Tavily vs Perplexity vs Google Custom       | **Tavily** (include_domains support)       | ✅ Decided |
| 5   | Primary LLM      | Claude vs GPT                               | **Claude 3.5 Sonnet** (better Vietnamese)  | Pending    |

---

## 12. Implementation Phases

### Phase 1: Foundation (Day 1-2)

- [ ] Setup Google Sheet KB với schema
- [ ] Clone Personal-Assistant workflow
- [ ] Add Member Lookup node
- [ ] Configure Tavily credentials

### Phase 2: Core Logic (Day 3-4)

- [ ] Implement Safety Triage (Code node)
- [ ] Configure AI Agent với new system prompt
- [ ] Add Tavily search tool với whitelist domains
- [ ] Implement 4-block output format

### Phase 3: Edge Cases (Day 5-6)

- [ ] FR-04: Unregistered Chat_ID handling
- [ ] FR-05: Disambiguation logic
- [ ] Error handling & graceful degradation
- [ ] Logging to Google Sheets

### Phase 4: Testing & Polish (Day 7)

- [ ] Run test scenarios T01-T08
- [ ] Performance optimization
- [ ] Documentation update
- [ ] Deploy to Render

---

## 13. Appendices

### Appendix A: Whitelist Domains (Full)

```javascript
const WHITELIST_DOMAINS = {
  western_medicine: [
    "pubmed.ncbi.nlm.nih.gov",
    "ncbi.nlm.nih.gov",
    "www.cochranelibrary.com",
    "www.who.int",
    "www.mayoclinic.org",
    "www.nhs.uk",
    "moh.gov.vn",
    "www.has-sante.fr",
    "www.vidal.fr",
  ],
  traditional_medicine: ["www.nccih.nih.gov", "vienduoclieu.org.vn", "www.sciencedirect.com"],
  myth_busting: ["www.snopes.com", "sciencebasedmedicine.org", "vfa.gov.vn"],
};
```

### Appendix B: Response Templates

**NORMAL Template:**

```
🏥 **Block 1 — Tây Y (Evidence-based)**
[content]
📚 Nguồn: [link]

🌿 **Block 2 — Đông Y (Scientific Traditional)**
[content]
📚 Nguồn: [link]

⚠️ **Block 3 — Cảnh báo / Myth-busting**
[content]

👤 **Block 4 — Ghi chú cá nhân**
[content]
📊 Mức độ chắc chắn: [High/Medium/Low]

---
📋 **Lưu ý:** [Master Disclaimer]
```

**URGENT Template:**

```
🚨 **CẢNH BÁO QUAN TRỌNG**

Mình không muốn làm bạn hoảng, nhưng với mô tả này có thể là dấu hiệu cần được đánh giá y tế sớm.

**👉 Bạn nên:**
- Liên hệ cơ sở y tế gần nhất
- Hoặc gọi cấp cứu nếu triệu chứng đang diễn tiến nhanh/nặng

**⏳ Trong lúc chờ:** Tránh tự dùng thêm thuốc mới.

---
[4 blocks nếu cần]
```

---

_Document generated based on PRD v2.0 — Health AI Agent (Telegram)_
