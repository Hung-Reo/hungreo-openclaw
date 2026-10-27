# HANDOVER PROMPT — phiên Claude Code mới (OpenClaw VPS + agents, từ 2026-10-25)

Dán khối dưới vào phiên mới. Phiên trước chạy 18/10 → 25/10/2026. Mọi thay đổi Production đều có entry trong `SESSION_HANDOVER.md` (entry mới nhất: 25/10 16:10 — Antigravity nâng LCM 1.2.0 cho Suckhoe/Hungreo 14:17–14:31, Claude Code ghi bù).

```
Bạn tiếp quản vận hành OpenClaw VPS + các agent của Hưng (fork Hungreo). Trả lời tiếng Việt, kết luận ở câu đầu, gắn nhãn VERIFIED / PRIOR-EVIDENCE / ASSUMPTION / UNVERIFIED. Chỉ ĐỌC cho tới khi Hưng GO từng việc.

PHẠM VI: VPS OpenClaw tổng thể (Hungreo/Rùa, Suckhoe, Nemo, Hermes runtime, storage, upgrade, OAuth). vn-stock (Hung-Reo/vn-stock-agent) có phiên RIÊNG → ở đây chỉ ghi nhận + tư vấn.

BƯỚC 1 — đọc (repo /Users/hungdinh/Development/hungreo-openclaw):
1. ~/.claude/CLAUDE.md và CLAUDE.md của repo.
2. tools/openclaw-ops/session-handover-20261025/HANDOVER_PROMPT.md (file này: "Trạng thái", "Việc mở", "Cách làm").
3. SESSION_HANDOVER.md: bảng mục lục từ 2026-10-18 + các entry 21/10 20:56 (Nemo 10.5), 22/10 06:45 (Nemo LCM 1.2.0), 22/10 09:51 (dọn Nemo), 25/10 14:55 (Hermes gỡ lcm-x), 25/10 16:10 (Suckhoe + Hungreo LCM 1.2.0 — Antigravity).
4. tools/openclaw-ops/lcm-120-plan-20261021/{PLAN.md,PHASE0.md}; README của nemo-upgrade-10.5-20261021, nemo-lcm-120-20261022, hermes-lcmx-remove-20261025, lcm-120-20261025 (H/S, có 30_soak.sh).
5. kb/lessons-learned.index.md → kb/lessons/2026-10-21-nemo-105-dryrun-missed-schema-migration.md, 2026-10-25-hermes-self-installs-community-plugin.md.

BƯỚC 2 — health-check read-only, báo kết quả rồi chờ Hưng nêu việc:
- Hungreo + Suckhoe (systemd, core 2026.9.33, LCM 1.2.0 từ 25/10 14:24/14:28): chạy tools/openclaw-ops/lcm-120-20261025/30_soak.sh (active, NRestarts, readyz, RSS, rss_threshold/ngày, cursors/gaps/dup, capability_error, OAuth Suckhoe — đã quá hạn 17:26 25/10, refresh ở lượt model đầu) + so baseline bằng lcm-120-plan-20261021/00_baseline.sh.
- Nemo (docker nemo-sandbox, core 2026.10.5 + LCM 1.2.0): tools/openclaw-ops/nemo-lcm-120-20261022/30_verify.sh — soak sau nâng LCM CHƯA ai kiểm (đáng lẽ 23/10): restarts/OOM, app-server (đếm qua /proc, không dùng ps), cursors/dup/gaps, capability_error=0, session-rebound.
- Hermes (systemd --user hermes-gateway, v0.22.5): active, có task treo / tiến trình con hermes_kernel kéo dài không, plugin chỉ còn homeassistant + news-format-guard, config không còn context/lcm.
- OAuth (models auth list / Hermes auth.json chỉ in hạn): Suckhoe hạn 25/10 17:26, Nemo 27/10 07:48Z, Hungreo 30/10, Hermes hạn cũ 23/10 06:40 — kiểm đã tự refresh chưa.
- VPS: RAM available, swap 4G, disk (25/10 sau dọn ~27G trống).

CÁCH LÀM ĐÃ CHỐT:
- Harness chặn Claude ghi Production. Claude soạn script trong tools/openclaw-ops/<việc>-<ngày>/ (00/10 check|apply, 99 rollback, 30 verify; kiểm điều kiện, backup có hash, readback, idempotent), Hưng chạy: scp lên rồi `ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash …'` hoặc 'bash -s <args>' < script. Lệnh chạy lâu: `setsid nohup … &` và dặn Hưng CHỈ BẤM 1 LẦN (đã bị chạy chồng 3 lần; script phải có flock/kiểm thư mục sót). Claude kiểm hash file sau scp và tự theo dõi log read-only.
- Mỗi script Production: review fresh-context (subagent opus) trước khi giao; mô phỏng rollback bằng docker/CLI giả.
- DRY-RUN phải chạy thử từng lệnh ghi bằng chế độ không ghi của công cụ; nâng core phải có REHEARSAL boot gateway trên bản sao (cách ly: bỏ channels.telegram, cron OFF, bind loopback, env không token, không cổng host, CÙNG giới hạn RAM với live). CLI không có --dry-run (Hermes) → chạy trên bản sao HERMES_HOME + so hash live trước/sau.
- OpenClaw 10.5: CLI ở container khác bị từ chối khi lease gateway-owner < 90s → chờ ≥100s; nâng 10.4→10.5 bắt `doctor --fix` (migrate agent DB v24→v25, kéo theo bật plugin openai/perplexity); readyz 200 ≠ agent sẵn sàng (~25–40s).
- Không tự đổi model/auth/fallback; mọi thay đổi ngoài phạm vi cần GO riêng. Đọc file trạng thái bằng cat (đừng suy từ kích thước). Không tin lời bot tự báo — kiểm log/DB.
- CLI VPS: OPENCLAW_STATE_DIR=~/.openclaw-<p> OPENCLAW_CONFIG_PATH=~/.openclaw-<p>/openclaw.json, nạp `set -a; . ~/.openclaw-<p>/gateway.systemd.env; set +a`, /home/hung/bin/openclaw --profile <p>. Nemo: `docker exec nemo-sandbox node /sandbox/runtime/node_modules/openclaw/dist/entry.js …` (image không có ps). Hermes CLI: /home/hung/.local/bin/hermes. Transcript: agents/main/agent/openclaw-agent.sqlite (transcript_events, mode=ro); bản ghi cài plugin: state/openclaw.sqlite → config_machine_state.
- Không in secret (chỉ đếm/tiền tố/hash 8 ký tự). Transcript Suckhoe có hồ sơ bệnh — không trích. Repo PUBLIC: trước commit quét chat ID, email, sk-, token; commit/push chỉ khi Hưng nói rõ.
```

## Trạng thái cuối phiên (PRIOR-EVIDENCE — mốc ghi bên cạnh)

| Hệ            | Hiện trạng                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Hungreo (Rùa) | core 2026.9.33 (Antigravity nâng 18/10), **LCM 1.2.0 từ 25/10 14:28** (Antigravity, GO Hưng 13:48; backup `~/backups/lcm-120-hungreo-20261025-142747`). Kiểm 16:05: cursor_v1 = 1, gaps 8, dup 0, capability_error 0; RSS 1811 MiB, 19 rss_threshold từ 14:24 (chưa thấy đỡ). 18/10: AGENTS.md thêm ghi chú kiểm version plugin (`plugins inspect`); `channels.telegram.commands.nativeSkills=false` để `/lossless` hiện trên menu (64 lệnh). 21/10: RSS 1,5–1,8 GiB, ~250 rss_threshold/ngày (9.33 không chữa). |
| Suckhoe       | core 9.33, **LCM 1.2.0 từ 25/10 14:24** (Antigravity; backup `~/backups/lcm-120-suckhoe-20261025-142410`). Kiểm 16:05: **cursors 0 — chưa có lượt agent nào, migrate live chưa chạy** (cron 19:30 gửi thẳng `message.action`, không qua agent/LCM). OAuth **quá hạn 17:26 25/10, chưa refresh** vì chưa dùng model (0 lỗi 401) — kiểm sau lượt agent đầu.                                                                                                                                                        |
| Nemo          | core **2026.10.5** (21/10 20:42, doctor --fix migrate DB v25) + **LCM 1.2.0** (22/10 06:24; DM chuyển `cursor_v1/legacy-migration`, dup 0, gaps 0, UAT PASS). RAM đỉnh chạm 2560 MiB nhưng OOM 0; app-server 2. Rollback còn: container `nemo-sandbox-10.4` + `runtime-10.4` + backup `nemo-10.5-20261021-203858`; backup `nemo-lcm120-20261022-062251`. Đã dọn 7,6 GB (22/10).                                                                                                                                  |
| Hermes        | v0.22.5 (Hermes tự update 25/10 10:42 — hoàn tất). Tự cài `hermes-lcm-x` (community, lệch SHA catalog) → Claude soạn script gỡ, Hưng chạy 25/10 14:54 (backup `~/.hermes/backups/lcmx-remove-20261025-145414`). **Quyết định Hưng: Hermes không dùng LCM**, dùng memory + compression tích hợp. UAT 15:44 trả lời bình thường.                                                                                                                                                                                   |
| VPS           | swap 4 GiB (Hưng chạy script 18/10), disk ~27G trống (25/10), reboot gần nhất 17/10.                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Repo          | Commit cuối `abcace43cd` (16/10). Toàn bộ docs/tools/lessons 18→25/10 **chưa commit** (cần GO + quét secret).                                                                                                                                                                                                                                                                                                                                                                                                    |

## Việc mở (theo ưu tiên)

1. **Soak LCM 1.2.0 Suckhoe + Rùa** (`lcm-120-20261025/30_soak.sh`; lần chạy 25/10 20:30 FAIL 0): sau lượt agent đầu của Suckhoe (migrate cursor + OAuth refresh), +24h, +48h (so rss_threshold/RSS Rùa với baseline 96–261/ngày; 25/10 sau nâng: 71 trong ~6h). Tìm hiểu 8 gaps `generation_mismatch` (5.457 entry, conv DM chính Rùa) — rehearsal báo 0. Rollback: `lcm-120-20261025/99_rollback.sh`.
2. ~~Soak Nemo LCM 1.2.0~~ — kiểm 25/10 16:00 PASS (restarts/OOM 0, app-server 2, cursors 1, gaps 0, dup 0, capability_error 0) nhưng chỉ 3 inbound từ khi container tạo lại 23/10 12:47 (nemo.env đổi `OPENROUTER_API_KEY` 11:44 — Hưng xác nhận có xoay key không). ~~Hermes OAuth~~ đã refresh 23/10 06:40 (exp 02/11).
3. **Hermes còn sót từ lcm-x** (cần GO): drop-in `hermes-gateway.service.d/70-lcm-x-default.conf` (UMask=0077) + `secrets.command` in 6 biến `LCM_*` trong `config.yaml`.
4. **Dọn tiếp Nemo** (cần GO, sau khi soak LCM ổn): `nemo-sandbox-10.4`, `runtime-10.4`, backup `nemo-10.5-20261021-203858`, `ops-10.5-20261021`; sau đó backup `nemo-lcm120-…`. Hermes: 3 zip pre-update 18/10 (~720M) + backup lcmx-remove.
5. **Hermes**: Hưng nên nhắn luật "không tự cài plugin/update/restart"; nếu muốn ghi vào SOUL/AGENTS Hermes → soạn bản đề xuất, qua bộ quét injection của Hermes, Hưng duyệt.
6. Commit docs phiên 18→25/10 (cần GO, quét secret trước).
7. Treo/theo dõi: RSS Rùa (nguyên nhân chưa rõ; LCM 1.2.0 là ứng viên); Nemo nói `exec` cần duyệt (21/10 tự chạy được) — chưa tra; 1 lần boot rehearsal fail ngay sau khi dừng Nemo — chưa rõ; upstream #178804 (codex app-server tích tụ), #178608 (session-rebound), lossless-claw #1255 (ngưỡng compaction theo contextWindow — chú ý khi chạy fallback Muse); Suckhoe 2 OAuth profile hạn 1970 thừa + Hungreo 1.

## What could still be wrong

- Số liệu trên là mốc cuối từng việc; health-check gần nhất 25/10 16:00–16:10.
- Handover này viết lúc 15:56 khi Claude Code chưa biết Antigravity đã nâng LCM H/S → đã sửa 16:10. Nhiều agent (Claude Code, Antigravity, Codex, Hermes) cùng đụng VPS: health-check đầu phiên luôn tìm backup/thư mục ops mới (`find ~/backups -newer …`) thay vì tin handover.
- Soak Nemo sau LCM 1.2.0 chưa có số liệu ≥24h.
- Hermes đã tự update core không có backup riêng — nếu v0.22.5 có lỗi thì rollback chỉ còn zip 18/10 (v0.22.2).
