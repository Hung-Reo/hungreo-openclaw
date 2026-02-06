# Health AI Agent (Telegram) — OpenClaw-first docs

Mục tiêu: chuyển thiết kế từ **n8n-centric** sang **OpenClaw-first**.

## Files

- `10-PRD_OpenClaw-First_v3.md`: PRD cho hướng mới (single source of truth).
- `20-Safety-Policy_v1.md`: 1 trang safety policy (triage + disclaimers + escalation).
- `30-System-Design_OpenClaw-First_v1.md`: system design (components + data flows + storage + security).

## Nguyên tắc

- Simple: OpenClaw làm “brain”; automation chỉ là “hands” (cron/hooks/n8n optional).
- Safe: tool policy tối thiểu + whitelist sources + không chẩn đoán/kê đơn.
- Effective: profile + memory ngắn hạn + citations.
