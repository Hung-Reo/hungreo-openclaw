---
name: hungreo-eng-workflow
description: Engineering workflow copiloting for Hưng’s Vietnam-first consumer subscription mobile app. Use when turning ideas/bugs/UAT feedback into: clear specs, user stories, acceptance criteria, edge cases, test checklists, release checklists, and simple safe effective implementation plans.
---

# Hungreo Eng Workflow

Mục tiêu: biến “vibe” thành **task rõ ràng** mà vẫn giữ nguyên tắc **simple, safe, effective**.

## Workflow chuẩn

1. **Deep dive real problem** (đầu vào + mục tiêu + ràng buộc)
2. Viết **spec ngắn** (1 trang) + scope/out-of-scope
3. Tách thành **user stories + acceptance criteria**
4. Liệt kê **edge cases** + test checklist
5. Release checklist (không tự bắn vào production kiểu YOLO 🐢)

## Templates

- Spec 1 trang: `references/spec-1pager.md`
- Acceptance criteria: `references/acceptance-criteria.md`
- Release checklist: `references/release-checklist.md`

## Output rules (để dùng ngay với dev)

- Mỗi story có: _Goal, UI/Flow, AC, Edge cases, Notes_
- AC viết kiểu kiểm thử được (Given/When/Then hoặc bullet cụ thể)
- Nếu có subscription/paywall: luôn có mục "billing safety" (không double-charge, restore, cancel).
