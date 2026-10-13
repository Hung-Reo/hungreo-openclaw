# HANDOVER PROMPT — phiên Claude Code mới (OpenClaw VPS + agents, từ 2026-10-13)

Dán khối dưới vào phiên mới. Phiên trước (10/10 15:00 → 12/10 14:10) đã đóng; mọi thay đổi Production có entry trong `SESSION_HANDOVER.md` (3 entry đầu: 12/10 14:05, 11/10 14:50, 10/10 19:20).

```
Bạn tiếp quản vận hành OpenClaw VPS + các agent của Hưng (fork Hungreo). Tiếng Việt, kết luận ở câu đầu, gắn nhãn VERIFIED / PRIOR-EVIDENCE / ASSUMPTION / UNVERIFIED. Chỉ ĐỌC cho tới khi Hưng GO từng việc.

PHẠM VI: phiên này lo VPS OpenClaw tổng thể (Hungreo/Rùa, Suckhoe, Nemo, Hermes runtime, storage, upgrade, OAuth). Project vn-stock (repo Hung-Reo/vn-stock-agent, Hermes làm chính) có phiên Claude Code RIÊNG → ở đây chỉ ghi nhận + tư vấn, KHÔNG review/merge/push/đổi timer vn-stock trừ khi Hưng yêu cầu rõ trong lượt đó.

BƯỚC 1 — đọc (repo /Users/hungdinh/Development/hungreo-openclaw):
1. ~/.claude/CLAUDE.md và CLAUDE.md của repo.
2. tools/openclaw-ops/session-handover-20261013/HANDOVER_PROMPT.md (file này — "Trạng thái", "Việc mở", "Cách làm").
3. SESSION_HANDOVER.md: mục lục + 3 entry 10/10 19:20 → 12/10 14:05.
4. .claude/skills/openclaw-ops/SKILL.md (mục 3 health-check). Skill còn cũ: Nemo là docker `nemo-sandbox` (không phải systemd), 9.x không còn sessions.json, chưa có check Hermes.
5. kb/lessons-learned.index.md → lesson mới: kb/lessons/2026-10-11-*.md, 2026-10-12-*.md.

BƯỚC 2 — health-check read-only: hungreo + suckhoe (systemd), Nemo (docker nemo-sandbox, 2026.10.1, readyz :18796), Hermes (systemd --user hermes-gateway). Kiểm thêm:
- OAuth Hermes hết hạn 13/10 (hôm nay) → đã tự refresh chưa (Hermes là phần mềm khác, refresh riêng). Suckhoe 15/10, Nemo 17/10 (`models auth list`).
- RAM Nemo sau upgrade 10.1 (1,6–1,76/2,5 GiB, 9.8 rảnh ~0,94) và swap VPS.
Báo kết quả, rồi chờ Hưng nêu việc mới.

CÁCH LÀM ĐÃ CHỐT:
- Harness chặn Claude Code ghi Production. Claude soạn script trong tools/openclaw-ops/<việc>-<ngày>/ (kiểm điều kiện, backup tên rõ, readback, idempotent, rollback 99_*), Hưng chạy: ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s' < script. Claude verify bằng hash/grep/log.
- DRY-RUN PHẢI CHẠY THỬ TỪNG LỆNH GHI bằng chế độ không ghi của chính công cụ (`plugins update --dry-run`, `config set --dry-run`, `hermes update --check --channel x`) trước khi stop dịch vụ — không chỉ kiểm version/RAM (lesson 11/10 + 12/10: 3 lần dừng giữa chừng).
- Path config có model chứa dấu chấm: `agents.defaults.models["openai/gpt-6.1-sol"]...` (dạng a.b.c bị tách).
- Không tự đổi model/auth/fallback — chỉ khi Hưng GO rõ (12/10 Hưng GO fallback Nemo = openai/gpt-6.1-sol).
- Sửa SOUL/AGENTS của bot → Hưng gửi /new rồi hỏi 1 câu kiểm. Hermes: file ngữ cảnh qua bộ quét injection của Hermes trước khi áp.
- Rùa (Hungreo) là admin Suckhoe: giao việc plugin/script/restart Suckhoe cho Rùa kèm tiêu chí UAT; Claude review diff + log sau.
- CLI VPS: OPENCLAW_STATE_DIR=~/.openclaw-<p> OPENCLAW_CONFIG_PATH=~/.openclaw-<p>/openclaw.json, nạp `set -a; . ~/.openclaw-<p>/gateway.systemd.env; set +a`, dùng /home/hung/bin/openclaw --profile <p>. Nemo: `docker exec nemo-sandbox node /sandbox/runtime/node_modules/openclaw/dist/entry.js ...`.
- Không in secret: chỉ đếm/tiền tố/hash 8 ký tự. Repo PUBLIC: trước commit quét chat ID 10 chữ số, email, sk-, ey…; commit/push chỉ khi Hưng nói rõ.
```

## Trạng thái cuối phiên (VERIFIED trong phiên)

| Hệ                      | Hiện trạng                                                                                                                                                                                                                                                                                                                                                                                                    |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Hungreo (Rùa) :18789    | 2026.9.9, `openai/gpt-6.1-sol`, fallback Muse. Restart 10/10 19:26 vì RAM → nền ~1,45–1,6 GiB, chưa thấy tăng dần (theo dõi). OAuth tự refresh 10/10 16:33 (sớm ~4 phút trước hạn), hạn mới 20/10. Job `skill-collection-review-main` 12/10 04:33 ok                                                                                                                                                          |
| Suckhoe :18795          | 2026.9.9. Rùa thêm lệnh `renew` cho plugin kb-weekly (11/10 14:27 restart, Claude review PASS, backup `~/.openclaw-suckhoe/backups/hbv-renew-7932-20261011-142738`). KB: mental-health 11/10 + viêm gan B 27/09 đã approved. **Lỗi mở:** `/kb-review approve` dạng text (nút Duyệt) rơi xuống AI 3/3 lần; `show`/`renew` text và `/kb_review approve` gõ tay OK → hướng dẫn Hưng gõ `/kb_review approve <mã>` |
| Nemo (docker)           | **2026.10.1** (từ 12/10 13:55), primary Muse, **fallback `openai/gpt-6.1-sol`** (runtime codex, plugin codex 2026.10.1). UAT Muse + Sol 6.1 PASS, không OpenRouter cho Sol. 16 plugin y 9.8 (anthropic có sẵn, không credential). Rollback giữ `nemo-sandbox-9.8` + `runtime-9.8` (`tools/openclaw-ops/nemo-upgrade-10.1-20261012/99_rollback.sh ~/backups/nemo-upgrade-10.1-20261012-134648`)                |
| Hermes                  | **Vẫn 819cc3c (2026.9.24)**. Upgrade v0.21.6 ngày 11/10 thất bại an toàn (`releases/channels/stable.json` không có, updater cũ không fallback GitHub) → Hưng hoãn tới v0.22.0. Claude CLI trên VPS 401, Codex VPS chưa login                                                                                                                                                                                  |
| VPS                     | Disk 65/96G, **31G trống** sau dọn 12/10 (log `~/cleanup-logs/`). Swap 2GB gần đầy thường trực                                                                                                                                                                                                                                                                                                                |
| vn-stock (chỉ ghi nhận) | Production `3aeaeeb`, AI trưa bật từ 12/10 (drop-in `vnstock-daily-midday.service.d/zz-midday-ai.conf`). 09:30 12/10 RESEARCH_CONTRACT_REJECTED do model chép sai evidence id GAS/PLX — phiên vn-stock xử lý                                                                                                                                                                                                  |

## Việc mở (theo ưu tiên)

1. **OAuth**: Hermes 13/10 (hôm nay), Suckhoe 15/10, Nemo 17/10 — kiểm tự refresh; không refresh → soạn script login lại (mẫu `tools/openclaw-ops/nemo-sol-fallback-20261007/11_login.sh`).
2. **RAM**: Nemo 10.1 cao hơn 9.8; swap VPS đầy. Phương án tăng swap 4GB chưa GO. `~/.local/lib/python3.12` có 6,7G torch/CUDA trên VPS không GPU — điều tra voice có dùng không trước khi đề xuất bỏ.
3. **Suckhoe kb-review**: tìm cơ chế vì sao `approve` dạng text rơi xuống AI (log luôn kèm `context-engine … session-rebound`); sửa tin duyệt ghi sẵn `/kb_review approve <mã>`; luật AGENTS Suckhoe: lệnh plugin rơi xuống AI → báo "lỗi hệ thống", không nói "chưa tìm thấy". Cả 3 giao Rùa theo quy trình, cần Hưng GO. Có thể thử trên Nemo 10.1 (fix "lending" upstream #167982).
4. **Khoảng 14–15/10**: Nemo ổn → xoá `nemo-sandbox-9.8` + `runtime-9.8` (~0,8G), cần GO.
5. Từ handover 10/10 còn treo: tĩnh nguyện cảnh báo cả exit 76 (chưa GO); Hungreo `SessionTranscriptReadFenceError` tra upstream; Suckhoe nhắc thuốc nói tự nhiên có thể không vào handoff; Anthropic token `sk-ant-oat01` chưa revoke ở claude.ai (Hưng chấp nhận rủi ro; còn trong lcm.db/transcript); Rotation v2 KB Suckhoe trước 08/11; cập nhật skill `openclaw-ops`.
6. Hermes upgrade: chờ v0.22.0 (cron báo cáo tuần tự báo). Lần sau thêm `hermes update --check --channel <x>` vào dry-run.

## Repo

Commit `chore(ops)` 13/10 trên nhánh `codex/sync-origin-main-20260222` (chưa push): SESSION_HANDOVER, kb/lessons + index, tools/openclaw-ops của 2 phiên gần nhất. **Không commit:** `tools/openclaw-ops/devotional-validation-20261009/` (chat ID thật), `kb/medical/`, các file `src/` và AGENTS/CLAUDE/.gitignore đang sửa dở không thuộc 2 phiên này.

## What could still be wrong

- Cơ chế lỗi `/kb-review approve` chưa tìm ra; mới có tương quan.
- RAM Nemo 10.1 mới đo trong 15 phút đầu.
- OAuth Hermes/Suckhoe/Nemo refresh chưa chứng minh bằng lần chạy thật.
- Plugin `perplexity`/`typesafe` của Nemo (2026.9.6) chạy trên core 10.1 — chưa có UAT dùng thật.
