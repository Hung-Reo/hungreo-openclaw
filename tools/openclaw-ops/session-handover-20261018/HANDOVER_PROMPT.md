# HANDOVER PROMPT — phiên Claude Code mới (OpenClaw VPS + agents, từ 2026-10-18)

Dán khối dưới vào phiên mới. Phiên trước (13/10 11:18 → 16/10 14:05) đã đóng; thay đổi Production có entry trong `SESSION_HANDOVER.md` (entry đầu: 2026-10-15 19:20 LCM 1.1.1).

```
Bạn tiếp quản vận hành OpenClaw VPS + các agent của Hưng (fork Hungreo). Tiếng Việt, kết luận ở câu đầu, gắn nhãn VERIFIED / PRIOR-EVIDENCE / ASSUMPTION / UNVERIFIED. Chỉ ĐỌC cho tới khi Hưng GO từng việc.

PHẠM VI: VPS OpenClaw tổng thể (Hungreo/Rùa, Suckhoe, Nemo, Hermes runtime, storage, upgrade, OAuth). vn-stock (Hung-Reo/vn-stock-agent) có phiên RIÊNG → ở đây chỉ ghi nhận + tư vấn.

BƯỚC 1 — đọc (repo /Users/hungdinh/Development/hungreo-openclaw):
1. ~/.claude/CLAUDE.md và CLAUDE.md của repo.
2. tools/openclaw-ops/session-handover-20261018/HANDOVER_PROMPT.md (file này — "Trạng thái", "Việc mở", "Cách làm").
3. SESSION_HANDOVER.md: mục lục + entry 15/10 19:20 (LCM 1.1.1) và 14/10 21:43 (Nemo 10.3, phiên Codex).
4. tools/openclaw-ops/lcm-111-20261015/README.md (script 00/10/20/99 dùng lại được cho lần nâng plugin sau).
5. kb/lessons-learned.index.md → kb/lessons/2026-10-1[1-4]-*.md.

BƯỚC 2 — health-check read-only (dùng lại tools/openclaw-ops/lcm-111-20261015/20_verify.sh cho từng bot):
- hungreo + suckhoe (systemd, core 2026.9.9, LCM 1.1.1), Nemo (docker nemo-sandbox, 2026.10.3 + LCM 1.1.1, readyz :18796), Hermes (systemd --user hermes-gateway).
- OAuth: Nemo hết hạn 17/10 13:12 (CHƯA kiểm sau hạn) → đã tự refresh chưa (`docker exec nemo-sandbox node /sandbox/runtime/node_modules/openclaw/dist/entry.js models auth list`). Hungreo hạn 20/10 16:33, Hermes 23/10 06:40, Suckhoe 25/10 17:26.
- RSS Hungreo (16/10: 1688 MiB, 227 cảnh báo rss_threshold/19h — gấp đôi trước nâng LCM) + swap VPS (16/10: 2025/2047 MiB).
- Nemo checkpoint soak 10.3: 16/10 + 17/10 21:26 đã qua, chưa ai kiểm.
Báo kết quả, rồi chờ Hưng nêu việc mới.

CÁCH LÀM ĐÃ CHỐT:
- Harness chặn Claude Code ghi Production. Claude soạn script trong tools/openclaw-ops/<việc>-<ngày>/ (kiểm điều kiện, backup khi đã stop, readback, idempotent, rollback 99_*), Hưng chạy: ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s <args>' < script. Claude verify bằng hash/grep/log/sqlite mode=ro.
- DRY-RUN PHẢI CHẠY THỬ TỪNG LỆNH GHI bằng chế độ không ghi của chính công cụ (`plugins update <spec> --dry-run`, `config set --dry-run`, `hermes update --check --channel x`) trước khi stop dịch vụ.
- Script Production: review fresh-context (subagent opus) trước khi giao Hưng — 15/10 vòng 1 bắt được 2 lỗi chặn ở rollback (`cmd && echo` không dừng khi set -e; quick_check sau SHA256 đổi file -shm). Không chép -shm khi backup SQLite; tránh `journalctl | grep -q` dưới pipefail (dùng here-string).
- Path config có model chứa dấu chấm: `agents.defaults.models["openai/gpt-6.1-sol"]...`.
- Không tự đổi model/auth/fallback — chỉ khi Hưng GO rõ.
- Sửa SOUL/AGENTS của bot → Hưng gửi /new rồi hỏi 1 câu kiểm. Hermes: file ngữ cảnh qua bộ quét injection của Hermes trước khi áp.
- Rùa (Hungreo) là admin Suckhoe: việc plugin/script/restart Suckhoe có thể giao Rùa kèm tiêu chí UAT; Claude review diff + log sau.
- CLI VPS: OPENCLAW_STATE_DIR=~/.openclaw-<p> OPENCLAW_CONFIG_PATH=~/.openclaw-<p>/openclaw.json, nạp `set -a; . ~/.openclaw-<p>/gateway.systemd.env; set +a`, /home/hung/bin/openclaw --profile <p>. Nemo: `docker exec nemo-sandbox node /sandbox/runtime/node_modules/openclaw/dist/entry.js ...`. Transcript 9.x+: agents/main/agent/openclaw-agent.sqlite (bảng transcript_events, mở mode=ro); bản ghi cài plugin: state/openclaw.sqlite bảng config_machine_state.
- Không in secret: chỉ đếm/tiền tố/hash 8 ký tự. Transcript Suckhoe chứa hồ sơ bệnh của gia đình — không trích vào chat/repo. Repo PUBLIC: trước commit quét chat ID, email, sk-, ey… (kể cả base64 trong script); commit/push chỉ khi Hưng nói rõ.
```

## Trạng thái cuối phiên

| Hệ                   | Hiện trạng (mốc kiểm cuối)                                                                                                                                                                                                                               |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Hungreo (Rùa) :18789 | 2026.9.9 + **LCM 1.1.1** (15/10 18:29). Sol 6.1 / fallback Muse. UAT 5/5 PASS. 16/10 14:05: NRestarts=0, job 06:00/07:00 ok, **RSS 1688 MiB, 227 cảnh báo/19h** (trước nâng 111/24h) — có thể do LCM hoặc phiên DM dài (context 231k token) — UNVERIFIED |
| Suckhoe :18795       | 2026.9.9 + **LCM 1.1.1** (15/10 17:24). UAT PASS. 16/10: nhắc thuốc 19:30 ok, tĩnh nguyện ok, RSS 1131 MiB, 0 cảnh báo. OAuth tự refresh 15/10 → hạn 25/10                                                                                               |
| Nemo (docker)        | **2026.10.3 + LCM 1.1.1** từ 14/10 21:26 (phiên Codex, không phải 10.1 như handover 13/10). 16/10: 1,45/2,5 GiB. Rollback giữ `nemo-sandbox-10.2` + 10.1 + 9.8 (Exited)                                                                                  |
| Hermes               | 819cc3c (2026.9.24), OAuth tự refresh 13/10 → hạn 23/10. Chờ v0.22.0                                                                                                                                                                                     |
| VPS                  | Disk 72/96G (**25G trống**, 13/10 còn 31G — có lẽ backup/rehearsal Nemo, ASSUMPTION). **Swap 2025/2047 MiB** (16/10)                                                                                                                                     |
| Repo                 | Commit `abcace43cd` đã push `origin/codex/sync-origin-main-20260222` (16/10)                                                                                                                                                                             |

## Việc mở (theo ưu tiên)

1. **Swap 2GB → 4GB**: Claude đề xuất làm sớm (rủi ro OOM cả 3 bot), **chưa GO**. Soạn script khi Hưng GO.
2. **RSS Hungreo** sau LCM 1.1.1: so lại 17–18/10; nếu vẫn ~2× → thử `/new` phiên DM Rùa trước, rồi mới xét `99_rollback.sh hungreo soft`.
3. **OAuth Nemo** hạn 17/10 13:12 — kiểm tự refresh; không được → soạn script login lại (mẫu `tools/openclaw-ops/nemo-sol-fallback-20261007/11_login.sh`).
4. **Core version**: Claude tư vấn giữ Hungreo/Suckhoe 2026.9.9, KHÔNG lên 10.3 (P1 mở: #171446 update 9.9→10.3 kẹt vòng lặp, #172605 gateway treo khi agent chạy; #167982 kb-review chưa sửa). Nhắm **2026.9.33 extended-stable** (dòng 9.x chỉ vá; 7.33 ra 18/09, 8.33 ra 28/09 → ước cuối 10, ASSUMPTION) → rehearsal → Suckhoe → Hungreo → ghim kênh. Kiểm `npm view openclaw dist-tags`.
5. **Dọn**: 2 backup LCM (`~/backups/lcm-111-{suckhoe-20261015-172413,hungreo-20261015-182918}`, ~700M) sau ~1 tuần ổn; Nemo rollback containers/runtime cũ — cần GO.
6. **Rùa đang dựng bản tin AI từ X qua Apify** (15/10 tối): đã nhắc Hưng xfeed X bị dừng 05/2026 vì scrape chập chờn — nên trần chi phí + trial 1 tuần. Theo dõi chi phí Apify.
7. Còn treo từ trước: Suckhoe `/kb-review approve` text rơi xuống AI (dùng `/kb_review approve <mã>`); Suckhoe 2 profile OAuth thừa hạn 1970 (`openai:default`, `openai:chatgpt-…`) + Hungreo 1; `brave`/`deepseek` bật trong config Hungreo nhưng không có trong dòng plugin khởi động (cả 10/10 và 15/10) — chưa tra; `~/.local/lib/python3.12` 6,7G torch/CUDA; cập nhật skill `openclaw-ops` (Nemo docker, LCM, 9.x không sessions.json, Hermes); Rotation v2 KB Suckhoe trước 08/11; lesson/tools của phiên Codex 13–14/10 (`nemo-10.3-lcm-20261014/`, `nemo-upgrade-10.2-20261013/`, `kb/lessons/2026-10-13*`, `2026-10-14*`) chưa commit.

## Đánh giá Nemo/Muse (15/10, cho tham khảo)

Muse trả lời đúng dữ kiện (10.3, LCM 1.1.1, tính năng khớp README) nhưng **tự nhận "ổn định hơn rõ" không có số liệu**, phóng đại "trước compact là mất hẳn". Dùng được cho hỏi đáp/tra cứu; không dùng câu tự đánh giá của bot làm căn cứ nâng cấp.

## What could still be wrong

- Từ 16/10 14:05 tới nay chưa kiểm VPS — mọi số liệu trên là mốc đó.
- Rollback LCM (soft/hard) chưa từng chạy thật; hard đã hết hạn 180 phút → chỉ còn soft.
- Nguyên nhân RSS Hungreo tăng chưa xác định.
- Ngày ra 2026.9.33 và đường nâng 9.9 → 9.33 (migration DB?) chưa kiểm.
