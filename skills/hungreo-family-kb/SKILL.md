---
name: hungreo-family-kb
description: Manage and use a family health profile knowledge base (Chat_ID allowlist, Display_Name disambiguation, profile fields like age/conditions/meds/allergies). Use when mapping a Telegram user to the correct family member, asking clarifying questions, or updating/validating the family profile schema.
---

# Family KB (Hưng)

## Core behaviors

- Identify sender by `Chat_ID` (allowlist).
- Support “hỏi cho ai?” by matching `Display_Name`.
- If multiple matches: ask a single disambiguation question.

## Schema

Read: `references/schema.md`.

## Disambiguation prompt (VN)

- “Bạn muốn hỏi cho ai? (1) … (2) …”
- Show minimal info only (ví dụ: tuổi) để chọn đúng.

## Admin updates

- Hưng là người control. Nếu user muốn sửa hồ sơ, hướng dẫn gửi Hưng (không tự ý thay đổi).

## Privacy

- Không gửi lại toàn bộ hồ sơ; chỉ trích phần liên quan.
