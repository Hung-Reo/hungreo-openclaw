# HANDOVER PROMPT — phiên Claude Code mới (OpenClaw VPS + agents, từ 2026-10-27)

Phiên trước chạy 25/10 → 27/10/2026 (Claude Code). Mọi thay đổi Production có entry trong `SESSION_HANDOVER.md` (mục lục đầu file, entry mới nhất 27/10 10:00 + 26/10 21:40 + 26/10 20:40/21:00).

## Trạng thái (VERIFIED 27/10 ~10:30 trừ khi ghi khác)

| Hệ                      | Hiện trạng                                                                                                                                                                                                                                                                                                                                                                                                       |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Hungreo (Rùa) + Suckhoe | **OpenClaw 2026.9.34** (extended-stable) + **Node 24.22.1** — Antigravity nâng 26/10 19:23/19:42; LCM **1.2.0** (25/10). Config 0 khoá đổi; model `openai/gpt-6.1-sol`, fallback Muse; 0 drift (kiểm theo skill v0.2.1 §4b). `generation_mismatch` → resync toàn bộ ~mỗi lượt Rùa (Hưng chọn chỉ theo dõi, chưa báo upstream).                                                                                   |
| Suckhoe KB              | Gói `tools/openclaw-ops/suckhoe-kb-fix-20261027/` **DEPLOYED 27/10 10:19** (lệnh gõ tay `/kb_review`, nhắc 24h/hết hạn, Rotation V2, whitelist merge + `dalieu.vn`); UAT-0/UAT-1 PASS. Backup `~/backups/suckhoe-kb-fix-20261027-101911`. Routine Cowork cloud `trig_01Xwoas…` đã đúng `SKILL.md.v2`. Scheduled task Claude Code `suckhoe-kb-check-2026-11-02` (02/11 09:30, read-only) sẽ kiểm candidate 01/11. |
| Nemo                    | 10.5 + LCM 1.2.0, ổn (container tạo lại 23/10 sau đổi key OpenRouter).                                                                                                                                                                                                                                                                                                                                           |
| Hermes                  | v0.22.5; plugin `advanced-delegation` (official) route light=Luna / work=**Terra 6.1** / deep=Sol, `included` (gói ChatGPT); `skills.write_approval: true` (4 bản ghi skill đang chờ Hưng `/skills pending`); còn sót lcm-x (drop-in `70-lcm-x-default.conf`, `secrets.command` LCM\_\*).                                                                                                                        |
| Upstream                | Không có bản mới sau 24/10 (OpenClaw), 23/10 (Hermes), 20/10 (lossless-claw). OpenClaw 9.34 chưa biết `gpt-6.1-terra`.                                                                                                                                                                                                                                                                                           |
| Repo                    | Commit cuối `ff98076` (23/10). **128 thay đổi chưa commit** (34 M + 94 ??) — việc ưu tiên của phiên mới.                                                                                                                                                                                                                                                                                                         |

## Việc mở

1. **(Nên làm sớm) Quét secret + soạn commit docs/scripts** — chi tiết trong brief phiên mới.
2. P2 (cần GO riêng): dọn lcm-x Hermes; dọn 8 chỗ hardcode Telegram bot token CŨ trong workspace Rùa (không trùng token live; 1 token cũ bị lộ trong output phiên 27/10 — Hưng xác nhận đã thu hồi); dọn runtime 9.33/Node 24.21/backup cũ sau ~1 tuần 9.34 ổn (disk 20G trống); kiểm `check_token_expiry.py` lượt 02:00 28/10; soak RSS/LCM baseline từ 26/10 19:42.

## Cách làm đã chốt

- Tiếng Việt, kết luận câu đầu, nhãn VERIFIED/PRIOR-EVIDENCE/ASSUMPTION/UNVERIFIED. Chỉ ĐỌC tới khi Hưng GO từng việc. Commit/push chỉ khi Hưng nói rõ; repo PUBLIC.
- Production: Claude soạn script `tools/openclaw-ops/<việc>-<ngày>/` (00 check / 10 apply / 30 verify / 99 rollback, backup có hash, flock, tự rollback), review fresh-context (opus), mô phỏng rollback; Hưng scp + chạy (`setsid nohup … &`, bấm 1 lần).
- Skill `.claude/skills/openclaw-ops/SKILL.md` v0.2.1 (Hưng duyệt 26/10) — check 3 tầng sau restart + drift §4b cho 9.3x.
- Không in secret/chat ID/email; khi lọc output dùng mẫu chặt cho bot token `[0-9]{6,12}:AA[A-Za-z0-9_-]{30,}` (bài học 27/10: lọc `bot[0-9]+:` bị sót). Transcript Suckhoe có hồ sơ y tế — không trích.
