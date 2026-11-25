# Rùa: ghi chú kiểm version plugin đúng (2026-10-18)

**Vì sao:** 18/10 13:41 Rùa trả lời "LCM 0.11.2" trong khi Hungreo chạy 1.1.1. Transcript cho thấy Rùa không thấy `plugins.installs` trong openclaw.json (9.x lưu bản ghi cài ở `state/openclaw.sqlite`), rồi tìm rộng ra và đọc `~/.openclaw/extensions/lossless-claw/package.json` (profile mặc định cũ, tháng 5).

**Đổi gì:** chèn 2 dòng (marker + 1 bullet) vào `~/.openclaw-hungreo/workspace/AGENTS.md`, mục "Production, dữ liệu và runtime", sau bullet "Không tự đổi agents.defaults.model.\*". Đặt ở AGENTS.md vì 2026.9.9 không còn nạp TOOLS.md. AGENTS.md: 17337 → 17863 ký tự (giới hạn 20000). Không restart.

Lệnh `openclaw --profile <p> plugins inspect lossless-claw` đã chạy thử read-only trên VPS cho cả hungreo và suckhoe → `Version: 1.1.1`.

| #   | Ai             | Lệnh                                                                     | Kỳ vọng                               |
| --- | -------------- | ------------------------------------------------------------------------ | ------------------------------------- |
| 10  | Hưng           | `ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < 10_apply.sh` | `BACKUP=…`, `diff lines: 2`, `OK 10`  |
| UAT | Hưng           | Telegram Rùa: `/new` → "bạn đang xài LCM bản mấy?"                       | 1.1.1 + có nêu lệnh `plugins inspect` |
| 99  | Hưng (nếu cần) | `ssh … 'bash -s <BACKUP>' < 99_rollback.sh` → `/new`                     | `OK 99 — sha 05de36e7`                |

Script dừng (ABORT) nếu AGENTS.md đổi so với sha `05de36e7` lúc soạn. Đã test local (apply / idempotent / rollback / các nhánh ABORT) + review fresh-context (opus): không lỗi chặn, 5 lỗi phụ đã sửa.

**Còn có thể sai:** exec của Rùa có bị chặn/hỏi khi chạy `openclaw … plugins inspect` không — UNVERIFIED tới UAT.
