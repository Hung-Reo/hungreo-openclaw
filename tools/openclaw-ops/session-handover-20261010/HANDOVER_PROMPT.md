# HANDOVER PROMPT — phiên Claude Code mới (OpenClaw VPS + agents, từ 2026-10-10)

Dán khối dưới vào phiên mới. Phiên trước (09/10 12:00 → 10/10 15:00) đã đóng; mọi thay đổi Production có entry trong `SESSION_HANDOVER.md` (mục lục đầu file). **Chưa commit** — xem mục "Repo".

```
Bạn tiếp quản vận hành OpenClaw VPS + các agent của Hưng (fork Hungreo). Tiếng Việt, kết luận ở câu đầu, gắn nhãn VERIFIED / PRIOR-EVIDENCE / ASSUMPTION / UNVERIFIED. Chỉ ĐỌC cho tới khi Hưng GO từng việc.

BƯỚC 1 — đọc (repo /Users/hungdinh/Development/hungreo-openclaw):
1. ~/.claude/CLAUDE.md (có khối "🧭 Văn hoá nền — 4 nguyên tắc" bản final) và CLAUDE.md của repo.
2. tools/openclaw-ops/session-handover-20261010/HANDOVER_PROMPT.md (file này — "Trạng thái", "Việc mở", "Cách làm").
3. SESSION_HANDOVER.md: mục lục + các dòng 2026-10-09 → 2026-10-10.
4. .claude/skills/openclaw-ops/SKILL.md (mục 3 health-check + khối Env key). Lưu ý: skill còn coi nemotron là systemd — Nemo thực tế là docker `nemo-sandbox`.
5. kb/lessons-learned.index.md → đọc lesson theo tag khi cần (mới: kb/lessons/2026-10-09-*.md).

BƯỚC 2 — health-check read-only: hungreo + suckhoe (systemd), Nemo (docker nemo-sandbox), Hermes (systemd --user hermes-gateway). Kiểm thêm: OAuth Hungreo đã tự refresh sau 16:37 10/10 chưa (models auth list: openai:default expires phải sang ~20/10); tĩnh nguyện sáng nay đã gửi chưa (guard data/send-guard/devotional-morning/<ngày>.json, sentTargets=2). Báo kết quả, rồi chờ Hưng nêu việc mới.

CÁCH LÀM ĐÃ CHỐT:
- Harness chặn Claude Code ghi Production. Claude soạn script trong tools/openclaw-ops/<việc>-<ngày>/ (kiểm base hash, backup tên rõ, sửa đúng-1-lần, readback, idempotent, rollback 99_*), CHẠY THỬ trong sandbox /tmp trên VPS trước, rồi Hưng chạy: ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < script. Claude verify lại bằng hash/grep/log. File trên Mac (~/.claude, ~/.codex, ~/.gemini) Claude sửa trực tiếp sau GO, có backup.
- Sửa SOUL/AGENTS của bot nào → Hưng gửi /new cho bot đó rồi hỏi 1 câu kiểm.
- Hermes: file ngữ cảnh phải qua bộ quét injection của chính Hermes (~/.hermes/hermes-agent/venv/bin/python, agent.prompt_builder._scan_context_content) trước khi áp.
- Rùa (Hungreo) là admin hệ thống Suckhoe (AGENTS.md mục "Quản trị hệ thống Suckhoe"): giao việc plugin/script/skill/restart Suckhoe cho Rùa bằng tin nhắn có tiêu chí UAT; Claude review diff + log sau.
- CLI trên VPS: OPENCLAW_STATE_DIR=~/.openclaw-<p> OPENCLAW_CONFIG_PATH=~/.openclaw-<p>/openclaw.json, nạp `set -a; . ~/.openclaw-<p>/gateway.systemd.env; set +a`, dùng /home/hung/bin/openclaw --profile <p>.
- Không in secret: chỉ đếm/tiền tố/hash 8 ký tự. Repo PUBLIC: trước commit quét chat ID 10 chữ số, email, sk-, ey… Commit/push chỉ khi Hưng nói rõ.
```

## Trạng thái cuối phiên (VERIFIED trong phiên)

| Hệ                   | Hiện trạng                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Hungreo (Rùa) :18789 | 2026.9.9, primary `openai/gpt-6.1-sol`, fallback Muse, timeout 600. AGENTS.md 13:54 09/10: thêm mục "Quản trị hệ thống Suckhoe", GO hợp lệ chỉ DM Telegram sender_id Hưng, luật "Bước tiếp:". SOUL: khối Văn hoá nền final (`7ebc0d3a`). Anthropic đã gỡ (config + kho auth cấp máy).                                                                                                                                                                                                                                                                                                                                                                                               |
| Suckhoe :18795       | 2026.9.9, `gpt-6.1-sol`, timeout 180. Plugin `suckhoe-technical-handoff` sửa 14:01 09/10 (khoá chỉ theo runId + giải phóng cuối lượt; bỏ wrapper file/media khi phân loại). `document-extract` bật 17:01 09/10 (tool `pdf` đọc PDF gốc OK, ảnh trang qua `gpt-6-astra` OAuth). Skills A (18:49 09/10): mới `doc-ho-so-y-te`, `thuoc-gia-dinh`; sửa `hungreo-family-kb`, `symptom-checker`, `hungreo-source-governance`; tắt `medication-reminder`, `sleep-tracker` (backup `~/.openclaw-suckhoe/backups/health-A-7890-20261009-184939/`). SOUL bản gia đình (`3e13dff5`). Tĩnh nguyện: validator retry 1 lần (`devotional_content.py` sha `a7aa953a`) — 10/10 gửi 05:45 đủ 2 người. |
| Nemo (docker)        | Muse primary, fallback `openai/gpt-6-sol`. SOUL: đoạn Văn hoá Gia Đình → 4 nguyên tắc rút gọn (`1bb155e8`).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| Hermes               | SOUL mới (`4ed6c341`, profile `vnstock` dùng chung), `~/.hermes/AGENTS.md` mới (luật vận hành; không đụng OpenClaw; model/auth/.env không sửa qua chat). Gateway cwd `~/.hermes`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Mac                  | `~/.claude/CLAUDE.md`, `~/.claude/soul.md` (khối chuẩn ở đầu), `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md` — cùng khối "Văn hoá nền — 4 nguyên tắc" (backup `*.bak-20261010-pre-*`).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| OAuth                | 3 bot cùng 1 tài khoản ChatGPT nhưng refresh token riêng. Runtime chỉ refresh khi đã hết hạn (`model-registry`: `Date.now() >= cred.expires`). Hungreo hết hạn 16:37 10/10 → CẦN kiểm đã tự refresh. Suckhoe hạn 15/10, Hermes 13/10, Nemo 17/10.                                                                                                                                                                                                                                                                                                                                                                                                                                   |

## Việc mở (theo ưu tiên)

1. ~~Kiểm OAuth Hungreo sau 16:37 10/10~~ — **ĐÃ XONG (VERIFIED 17:55 10/10):** `openai:default` tự refresh, hạn mới 2026-10-20 16:33 VNT; UAT `gpt-6.1-sol` attempts=1, 0 lỗi 401/403/candidate_failed. Lần sau tương tự: không cần làm gì, chỉ kiểm sau mốc hết hạn.
2. **Tĩnh nguyện:** sender chỉ cảnh báo Hưng khi exit 75; exit 76 (validator từ chối) im lặng → đề xuất cảnh báo cả 76 (chưa GO). Nit: log ghi `reason=validation rejected` cả cho JSONDecodeError; theo dõi thời gian slot (worst-case có thể >360s).
3. **RAM/swap VPS:** swap ~1.9–2.0/2.0 GiB, Hungreo RSS 1.46–1.77 GiB (cảnh báo rss_threshold). Điều tra read-only: tiến trình nào, có tăng dần không.
4. **Hungreo `SessionTranscriptReadFenceError`** ("admission identity changed", 4 lần từ 08/10, lượt 11:58 09/10 rơi Muse) — tra issue tracker upstream 9.9 trước khi kết luận.
5. **Suckhoe:** câu nhắc thuốc nói tự nhiên ("nhắc Ba tiêm insulin 7h") có thể không vào handoff Hungreo — Rùa tách việc riêng, chưa sửa. Suckhoe từng thử `exec cat skills/...` (exec allowlist ask=always) — kết quả UNVERIFIED, rà khi xem exec policy.
6. **Anthropic token `sk-ant-oat01`:** đã gỡ khỏi runtime 2 bot + xoá 13 file rác; còn plaintext trong `lcm.db`, transcript 03/2026, backup upgrade/daily. Hưng chưa revoke ở claude.ai (chấp nhận rủi ro) — nhắc khi phù hợp.
7. **12/10 04:33** job `skill-collection-review-main` (Hungreo) phải chạy OK. **~14/10** dọn container Nemo cũ (`nemo-sandbox-pre-ca`, `-9.6`, `-9.1`) — cần GO. **Trước 08/11** Rotation v2 KB Suckhoe.
8. **Skill `openclaw-ops`** cần cập nhật: Nemo là docker; sessions drift check của 9.x không còn `sessions.json`; thêm check Hermes.

## Repo (chưa commit)

Mới/đổi trong phiên: `SESSION_HANDOVER.md`, `kb/lessons-learned.index.md`, `kb/lessons/2026-10-09-anthropic-token-sprawl.md`, `tools/openclaw-ops/{devotional-validation-20261009 (thêm 10/11/99), rua-agents-soul-proposal-20261009, anthropic-removal-20261009, hermes-agents-soul-20261009, soul4-20261009, soul-final-20261010, session-handover-20261010}/`.
⚠️ `devotional-validation-20261009/` (do Codex tạo) có `devotional-morning-send.sh` + test chứa **chat ID thật** — không commit nguyên trạng. Repo còn nhiều untracked cũ không thuộc phiên này.

## What could still be wrong

- RSS gateway Hungreo 1.63–1.83 GiB (cảnh báo mỗi 30 phút) — việc mở số 3.
- Luật trong AGENTS/SOUL là luật mềm: Hungreo/Hermes có exec rộng và quyền ghi file của bot khác.
- Rollout Suckhoe không ghi lại SOUL nên cơ chế nạp SOUL Suckhoe chỉ suy từ câu trả lời.
- Hermes AGENTS.md không nạp cho cron có `workdir` riêng (theo docs, UNVERIFIED).
