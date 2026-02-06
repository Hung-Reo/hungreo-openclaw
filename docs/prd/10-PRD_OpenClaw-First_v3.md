# PRD — Health AI Agent (Telegram) — OpenClaw-first

**Phiên bản:** v3 (định hướng OpenClaw-first)
**Trạng thái:** Draft
**Product Owner:** Hưng
**Ngày:** 2026-02-04

## 0) Tóm tắt ý tưởng

Trợ lý sức khỏe cho gia đình trên Telegram. Hướng **OpenClaw-first**: OpenClaw làm bộ não trung tâm (nhận text/voice → hiểu ngữ cảnh + hồ sơ → trả lời), automation chỉ là “tay chân” khi cần (nhắc lịch, ping URGENT, log tối giản).

## 1) Key decisions (đã chốt)

- **Profile store**: Excel trên Google Drive, share cho người nhà cập nhật khi cần; **Hưng control**.
- **Whitelist**: bổ sung thêm nguồn VN uy tín (ưu tiên cơ quan/ bệnh viện tuyến trung ương).
- **Escalation**: khi **URGENT** → **ping Hưng**.
- **Injection**: chặn link ngoài whitelist ngay ở ingestion layer.
- **Cost guardrails**: có giới hạn độ dài voice + rate limit.
- **Disclaimer**: cần bản ngắn cho người lớn tuổi.

## 2) Goals

- Trả lời theo 3 góc nhìn: Tây Y (evidence-based), Đông Y (scientific traditional), Myth-busting.
- Cá nhân hóa theo hồ sơ gia đình.
- Safe-by-default: triage, disclaimer, whitelist sources, không chẩn đoán/kê đơn.

## 3) Non-goals

- Không thay bác sĩ.
- Không kê đơn/đổi liều.
- Không phác đồ lai.
- Không dùng nguồn ngoài whitelist.

## 4) Users & Access

- Người dùng: thành viên gia đình (ưu tiên UX cho người lớn tuổi).
- Access control: Chat_ID allowlist.
- Hỏi cho ai: Display_Name + disambiguation.

## 5) Input/Output

- Input: Telegram text + Telegram voice note (STT).
- Output: Text trên Telegram (giai đoạn 1).

## 6) Safety requirements

- Áp dụng `docs/prd/20-Safety-Policy_v1.md`.

## 7) Memory

- **Open question:** dùng “standard memory” của OpenClaw hay giới hạn 5 turns như PRD v2?
  - Khuyến nghị v1: giới hạn theo _conversation_ để giảm rủi ro lộ dữ liệu nhạy cảm; vẫn có thể giữ “memory dài hạn” nhưng cần cơ chế opt-out.

## 8) Open questions (còn lại)

1. Cụ thể list **VN sources** sẽ gồm những domain nào? (Hưng duyệt danh sách)
2. Voice guardrails: max seconds? (đề xuất 30s)
3. Rate limit: mỗi Chat_ID bao nhiêu message/phút?
4. Khi URGENT: chỉ ping Hưng hay ping thêm người thân khác?

## 9) Implementation approach (phased)

- Phase 1: OpenClaw-only (Telegram + STT + safety + manual profile).
- Phase 2: Profile store chuẩn + whitelist retrieval + logging tối giản.
- Phase 3: Automation (nhắc lịch, ping URGENT) nếu cần.
