# OpenClaw Local Context (Hungreo)

Last updated: 2026-10-26 19:48 (+07; Cả Suckhoe & Hungreo đã nâng lên OpenClaw 2026.9.34 + Node v24.22.1 + LCM 1.2.0, 0 plugin drift, 0 service config issues)
Owner: Hung

> **Latest runtime verification 26/10 19:48 VNT:**
>
> - **Suckhoe (`:18795`):** `openclaw-gateway-suckhoe.service` active (`pid=2741236`), **Node.js `v24.22.1`** (`/home/hung/openclaw-node-24.22.1/node/bin/node`, `OpenSSL 3.5.9`), **Core `2026.9.34`** (`/home/hung/openclaw-upgrade-20261026-934/runtime`), `lossless-claw@1.2.0`, `codex@2026.9.34`, `brave@2026.9.34`, `deepseek@2026.9.34`, `NRestarts=0`, `readyz=200`, `VmRSS=1080 MiB`, `VmSwap=0 MiB`, `degraded_legacy=0`, `0 plugin drift, 0 service config issues`.
> - **Hungreo / Rùa (`:18789`):** `openclaw-gateway-hungreo.service` active (`pid=2749236`), **Node.js `v24.22.1`** (`/home/hung/openclaw-node-24.22.1/node/bin/node`, `OpenSSL 3.5.9`), **Core `2026.9.34`** (`/home/hung/openclaw-upgrade-20261026-934/runtime`), `lossless-claw@1.2.0`, `codex@2026.9.34`, `brave@2026.9.34`, `deepseek@2026.9.34`, `parallel@2026.9.34`, `typesafe@2026.9.34`, `NRestarts=0`, `readyz=200`, `VmRSS=1166 MiB`, `VmSwap=0 MiB`, `degraded_legacy=0`, `0 plugin drift, 0 service config issues`.
> - **Rollback Ready:** Backups `2026.9.33` tại `/home/hung/backups/openclaw-{suckhoe-pre934-20261026-192200,hungreo-pre934-20261026-193928}` (`98_rollback_934.sh`); runtime `2026.9.33` giữ tại `/home/hung/openclaw-upgrade-20261018-933/runtime`; Node `v24.21.0` giữ tại `/home/hung/openclaw-upgrade-20261003/node` (`99_rollback_node.sh`).

> **Latest resource/cleanup verification18/10 17:12 VNT:** H/S core9.33 staged `~/openclaw-upgrade-20261018-933/runtime`, PIDs329781/327653; Nemo core10.4 runtime-10.4, PID310335; Hermes268895. Sau GO thu hồi10.14GB: disk used74%,available27.65GB. Cả3readyz200, configs/PIDs/restart counters không đổi trong cleanup; Node/loader runtime cũ, backups mới18/10, rollback Nemo10.3+10.2 và captures giữ nguyên. Các snapshot13–14/10 bên dưới là lịch sử; xem SESSION_HANDOVER17:12.
> Policy: File này chỉ lưu topology/context. Không lưu secrets/tokens/private keys/PII.

> **GO Nemo mới nhất — 2026-10-14 21:43 VNT:** Nemo Docker đã lên core/Codex 2026.10.3 + LCM 1.1.1 (contextEngine/hook active), started21:26:13. Muse/fallbackSol6.1 + resource/ports/env giữ nguyên; live routes/LCM grep và isolated compaction/restart PASS. Backup `nemo-10.3-lcm-20261014-212310`, rollback container10.2 giữ. H/S PID3242117/3456950/NRestarts0 không đổi. User Telegram UAT/48–72h soak chưa chốt; xem SESSION_HANDOVER entry21:43. Các snapshot bên dưới là lịch sử.

> **Đính chính live 2026-10-13 15:08–15:12 VNT (Codex):** Hungreo/Suckhoe vẫn core 2026.9.9 + LCM 1.1.0, nhưng primary đúng là `openai/gpt-6.1-sol`, main fallback Muse; `gpt-6-luna` là sub-agent. Cấu hình và startup log xác nhận; các dòng Sol 6 trong snapshot 12:30 bên dưới đã cũ/sai. Nemo 10.2 running từ 11:38:44, readyz 200, RestartCount=0/OOMKilled=false; 42 cảnh báo RSS 1.26–1.59 GiB (threshold 1.25 GiB), chưa chứng minh memory leak hay ổn định dài hạn. Xem entry audit mới trong SESSION_HANDOVER.md; không đổi Production.

---

## Runtime snapshot — 2026-10-13 12:30 VNT (Nemo lên 2026.10.2 Canary; Hungreo & Suckhoe 2026.9.9 giữ nguyên)

- **Rà soát & Canary Cutover 13/10 (VERIFIED 11:41 VNT):**
  - **Nemo (Canary Docker):** Nâng cấp từ 2026.10.1 lên **OpenClaw 2026.10.2 (`b8952d4`)** qua bộ script `tools/openclaw-ops/nemo-upgrade-10.2-20261013/`. Container `nemo-sandbox` chạy runtime `/home/hung/sandbox-nemo/runtime-10.2`. Model chính `openrouter/meta/muse-spark-1.3-contributor`, fallback `openai/gpt-6.1-sol` qua codex plugin 2026.10.2. UAT 1 (Muse): `UAT_DEFAULT_OK` (5.2s, status 200); UAT 2 (ép fallback Sol 6.1): `UAT_SOL61_OK` (status ok, winnerModel `gpt-6.1-sol`). Backup an toàn: `/home/hung/backups/nemo-upgrade-10.2-20261013-113641` (594M tar config + workspace, SHA256 verified). Rollback container `nemo-sandbox-10.1` + runtime `runtime-10.1` giữ nguyên (chạy `99_rollback.sh`).
  - **Hưng Rẻo / Rùa (systemd user):** `openclaw-gateway-hungreo.service` giữ nguyên **OpenClaw 2026.9.9** (`~/openclaw-upgrade-20261008-99/`), Node v24.21.0, MainPID 3242117 (active từ 10/10 19:26 VNT, NRestarts=0). Context engine: `lossless-claw` (v1.1.0). Model chính `openai/gpt-6-sol`, sub-agents `openai/gpt-6-luna`.
  - **Sức Khoẻ (systemd user):** `openclaw-gateway-suckhoe.service` giữ nguyên **OpenClaw 2026.9.9** (`~/openclaw-upgrade-20261008-99/`), Node v24.21.0, MainPID 3456950 (active từ 11/10 14:27 VNT, NRestarts=0). Context engine: `lossless-claw` (v1.1.0). Model chính `openai/gpt-6-sol`, sub-agents `openai/gpt-6-luna`.
  - **LCM (lossless-claw) Assessment:** Hungreo và Suckhoe đang chạy `lossless-claw` 1.1.0 (Nemo không bật LCM). Upstream npm có bản 1.1.1 (hỗ trợ prompt-cache stability, session externalized tool grant boundary, và bounded context compaction). Khuyến nghị: Theo dõi Nemo 10.2 chạy ổn định trong 48–72h trước khi xem xét nâng Suckhoe lên 2026.10.2 + LCM 1.1.1, sau đó đến Hungreo.

- **Follow-up 03/10 20:35 VERIFIED (Hungreo Sol 6 confirmed & Sol 6.1 Root Cause):**
  - **Restart chẩn đoán Hungreo (GO Hưng):** Backup `/home/hung/backups/hungreo-prerestart-20261003-2030/`, restart `openclaw-gateway-hungreo.service` thành công (MainPID 1559593), `readyz` HTTP 200, legacy webhook 8787 HTTP 200.
  - **Kiểm chứng Sol 6:** Chạy CLI test turn với `openai/gpt-6-sol` PASS 100% (1 attempt, winnerModel `gpt-6-sol`, output "OK").
  - **Bản chất lỗi Sol 6.1 trên OpenClaw:** Chạy CLI test turn với `openai/gpt-6.1-sol` trả về lỗi chính thức từ OpenAI Codex binary: `{"type":"error","status":400,"error":{"type":"invalid_request_error","message":"The 'gpt-6.1-sol' model is not supported when using Codex with a ChatGPT account."}}`.
  - **Giải mã khác biệt giữa Hermes và OpenClaw:** Hermes gọi trực tiếp raw HTTP API của `/backend-api/codex/responses` nên không bị chặn; trong khi OpenClaw sử dụng runtime `@openai/codex` CLI app-server và binary này chủ động chặn model `gpt-6.1-sol` đối với các tài khoản ChatGPT subscription.
  - **Chốt cấu hình:** Đã gỡ sạch `openai/gpt-6.1-sol` khỏi `models` và `modelPolicy.allow` trong `openclaw.json` của Hungreo, giữ nguyên `openai/gpt-6-sol` cho cả Hungreo và Suckhoe theo đúng chỉ đạo của Hưng.
  - **Healthcheck:** Probe cả 2 profile Hungreo và Suckhoe đều PASS (exit code 0).

- **Follow-up 03/10 15:55 VERIFIED:** Hoàn tất nâng cấp toàn bộ 3 bot lên **OpenClaw 2026.9.8 (`fc23bc8`)** theo chu trình an toàn (Canary Nemo → UAT → Sức Khoẻ → UAT → Hưng Rẻo → UAT).
  - **Nemo (Canary Docker):** Container `nemo-sandbox` chạy 2026.9.8, mount runtime `/home/hung/sandbox-nemo/runtime-9.8`, model giữ nguyên `openrouter/meta/muse-spark-1.3-contributor`, resource cap 1 CPU / 2GiB. UAT Telegram `/status` + date tool-call PASS (~11.5s).
  - **Sức Khoẻ (systemd user):** `openclaw-gateway-suckhoe.service` chạy runtime 2026.9.8 (`~/openclaw-upgrade-20261003/`), SQLite schema 19 integrity_check ok, port 18795 readyz 200, legacy webhook 8788 healthz ok. Model chính giữ nguyên `openai/gpt-6-sol`, sub-agent giữ nguyên `openai/gpt-6-luna`. UAT Telegram PASS. Backup đầy đủ `/home/hung/backups/suckhoe-upgrade-pre-9.8-20261003-151311/` (936M, SHA256 verified).
  - **Hưng Rẻo / Rùa (systemd user):** `openclaw-gateway-hungreo.service` chạy runtime 2026.9.8 (`~/openclaw-upgrade-20261003/`), port 18789 readyz 200, legacy webhook 8787 healthz ok. Áp dụng in-memory loader hook `patch-binding-loader-hook.mjs` bảo vệ plugin bindings; tests 4/4 PASS. Model chính giữ nguyên `openai/gpt-6-sol`, sub-agent `openai/gpt-6-luna`. UAT Telegram `/status` + chat PASS. Backup `/home/hung/backups/hungreo-upgrade-pre-9.8-20261003-153600/` (1.5GB, SHA256 verified).
  - **Skills validation:** Bổ sung YAML frontmatter chuẩn (`name`, `description`) cho `canvas` và `failures-md` trong workspace Hưng Rẻo; OpenClaw nạp sạch sẽ 0 warning.
  - **Healthcheck & CLI:** `/home/hung/bin/openclaw` cập nhật symlink trỏ vào `~/openclaw-upgrade-20261003/runtime/bin/openclaw`. `openclaw-healthcheck.timer` active; probe cả 2 profile exit code 0.

- **Follow-up 01/10 08:01 VERIFIED, supersedes raw retention below:** Hưng GO storage cleanup → only two `/home/hung/backups/openclaw-upgrade-20260925/{hungreo,suckhoe}/state.precutover-7.1` raw copies deleted after full107,201file/hash/mode/link comparison,26SQLite PASS and networkisolated7.1-2 archivedstore boots. Compressed archives VPS/Mac, rollback7.1-2/live9.6/Nemo runtime, daily backups/state.failed-96/voice dependencies retained. Disk82→69%,free17.83→29.83GiB. Both ready/PIDs1056437/949179/restarts2/0/confighash/mainSol6 unchanged, no newunitOOM/restart duringcleanup; ownrestoredscratch/containers removed. Backup/health/restore timers unchanged/active; nextrestore04/10 03:00. Oldplugin/auth/channelrollback UAT notcertified, noProductionupgrade/model/service/cron/send. Report `live-vps-snapshot/2026-10-01-storage-cleanup/report.md`. Hưng reportsvoice nowusable both; latestuserUATsupersedes pendingnote below, not freshautomatedTelegramtest.

- **Follow-up30/09 17:17 VERIFIED (supersedesvoiceOFF):** Hưng requests bounded voice for Suckhoe and Hungreo, no LLM/model-module change. Applied17:15 shared local worker `/home/hung/bin/openclaw-bounded-voice`: base.pt existing,8MiB/30s,one shared lock,1792MiB available admission, separate1280MiB/no-swap/oneCPU/45s transient unit. Actual installed9.6 schema uses shared `tools.media.models`, rejectsaudio.models. BothDM preprocessing actualinstalledCLI one-attemptPASS; groupsdenied;10worker/12guardtestsPASS/reviewAPPROVE. Whisper console stilldenied whenaudioON. Onlymedia config +AGENTS Voiceblock +launcher/guard changed; mainSol6/subLuna/auth/fallback/runtime/cron/PIDs untouched, bothready. VNStock live requested/modelcommandSol6 verifiedreverted. Backup `/home/hung/backups/bounded-voice-20260930-165846/`. RealTelegramvoiceUAT and accuracypending (syntheticsampleonewordwrong); nativeSuckhoe exec-with-wait still90stimeout/noapprovalrecord.9.7released30/09 relevantcandidate, noProductionupgrade. Report `live-vps-snapshot/2026-09-30-bounded-voice/report.md`.

- **Follow-up30/09 16:42 VERIFIED, supersedes16:16 pending state:** latest Hưng “Ok go” → fresh official Hungreo OAuth `openai:default`/main completed; canonical failed fence cleared, fresh no-deliver Sol6 gateway `HUNGREO_AUTH_OK`, one attempt/no fallback/tools PASS. Reviewed Whisper console guard installed for both service PATHs;10 VPS tests + actual cgroup/live OFF fixtures PASS. Original preserved, backup `/home/hung/backups/auth-whisper-guard-20260930-162349/` with consistent SQLite quick_check=ok. Login auto-added empty Astra allow entry removed narrowly via official CLI; final both configs semantically match baseline, defaults Sol6/audioOFF, legacy native auth unchanged. No restart/upgrade/send/cron. Both active/ready/PIDs1056437 and949179 unchanged. **UNVERIFIED:** actual exec-child guard UAT (Suckhoe policy refusal, then native yielded-cell missing tool.result); self-support, voice and sustained RAM/catalog stability unresolved. Report `live-vps-snapshot/2026-09-30-auth-guard-production/report.md`.

- **Follow-up30/09 16:16:** Hungreo15:39 fallback is actual auth selection failure; canonical shared credentials live in `state/openclaw.sqlite`/`config_machine_state` (`authProfiles.store/state`), agent auth tables currently empty/inherited. Both OpenAI profiles failed refresh fences at12:33; legacy file import/expiry edit is not a verified repair. Muse15:38 still execWhisper tiny after policy patch. Suckhoe16:03 freshSol6/profile-auth/no-tools/no-fallback UATPASS; bothservicesready/PIDunchanged at audit. CLIguard10tests localcandidate +freshHungreo device-code plan, notdeployed; newauth/CLI GO pending. Report `live-vps-snapshot/2026-09-30-afternoon-auth-audit/report.md`.

- **Follow-up30/09 13:13 VERIFIED:** GO Production voice/policy applied12:44: Hungreo3docs/Suckhoe1doc, officialskills.entries.openai-whisper.enabled=falseboth, audioOFF giữnguyên;11VPStests/actualeligibilityPASS. Suckhoe freshgatewaySol6policyUAT xintext/no tools/fallback/sendPASS; Hungreo freshrun authfileguardBLOCKED. Bothactive/ready, Hungreo1056437/NRestarts2/Suckhoe949179/NRestarts0, eventLoopDegradedfalse. VNStockresearchconfig+actualadapter đãSol6.1/includedPASS (2fields only), Hermesgatewaylive5.6Sol/NemoMuse giữnguyên. H/S6.1gateschưaPASS: Hungreo legacyauthdirectCLI400, SuckhoegatewayETIMEDOUTtrongcatalogreload; tempregistry/allowrestored, defaultsSol6unchanged. Backup`/home/hung/backups/voice-policy-20260930-124051/`, reportProduction30/09. No restart/upgrade/auth/fallback/cron/send. SustainedRAM/catalog/authrootcause vàactualvoiceUAT chưaresolved.

- **Follow-up29/09 GO Production07:05/live07:08 VERIFIED:**3morningpatches đãapply: builderisolateinvalidlanguageitem/min2strict, SOULscheduleddevotionalexceptionJSONonly, Hungreo canonicalheartbeat scratchabsolute workspacepaths/CAS2→3. VPS8tests +GPT-6Solcontent-onlyUAT1attemptPASS/no tools/sender. Backup`/home/hung/backups/morning-reliability-20260929-070247/`0700. PID/config/allcrondefinitions giữnguyên; bothready, RAMavailable3145MiB. ExistingmonitorACTIVE, no schedulechanges. Nextrealmorningdelivery30/09 chưaverify; no send-bù29/09sau07:00. Entry06:53 dưới làhistorical.

- **Follow-up29/09 live06:53 VERIFIED:** cả hai active/ready, Hungreo943325/NRestarts1, Suckhoe949179/NRestarts0; RAMavailable3353MiB, realintervalsteal0%. Businessfailure độc lập: Brief06:28/06:50 fail languagegate AIitem3; devotional06:00 health-onlyrefusal→exit76,06:20 deliveredboth; Hungreo falseunitnamealert đượcbot sửa scratch06:40 nhưng DM hit180sbudget.3 localcandidatepatches/testsPASS, chưaProduction; report `live-vps-snapshot/2026-09-29-morning-reliability/report.md`.9.6 heartbeatinstruction nằmcanonicalSQLite `cron_job_scratch`, không còn workspaceHEARTBEAT.md; agenttranscript nằm`agents/main/agent/openclaw-agent.sqlite`/`transcript_events` cho cácsessionsđãcheck, khôngJSONL. Giữ runtime/model/auth/service/cron; no send-bù sau07:00.

- **Follow-up28/09 11:16 VERIFIED:** healthcheck alert wrapper + Python helper đã Production theo GO,28VPStests + systemdservice thật16.32s PASS. Timer30phút giữ nguyên/active; statev2/fail0/pending0/0600, cảnh báo lỗi tự động bật; không testTelegram hoặc restartgateway. Hungreo943325/NRestarts1, Suckhoe949179/NRestarts0 active/ready, RAM available4022MiB lúc11:15. Backup `/home/hung/backups/healthcheck-alert-20260928-111115/`; repo source `tools/openclaw-ops/`, report Production trong live-vps-snapshot. Root causeOOM vẫn chưa chốt; không đổi OOMPolicy/model/auth.

- **Follow-up28/09:** delivery/Finance/backup audit PASS như handover07:20; restore-check là WEEKLY Sunday03:00, next04/10. Codex heartbeat đổi sang bounded monitor07:15 ngày29/09–04/10, ACTIVE, tự PAUSE cuối04/10; gắn chat cũ, không phải daemon VPS. Không kiểm runtime lại trong turn viết handover.

- **Follow-up27/09 15:30 VERIFIED:** Finance cron dùng CLI9.6, devotional source/transport patches theo GO, snapshot Hungreo đã refresh; không restart. Backup02:15/restore03:00 ngày27 PASS split archives + restore thật. Đã xoá ~6GB rehearsal trash theo GO (>48h), disk79%/~21GB available. Raw precutover12.2GB + rollback/runtime/SQLite/plugin-captures giữ nguyên. Heartbeat07:10 ngày28 ACTIVE để kiểm receipts sau patch, sau đó PAUSE; xem handover15:30.

- **Follow-up 15:46:** Hưng GO ngoại lệ Morning Brief trong Suckhoe SOUL.md; đã apply, model GPT-6 Sol biên tập + pipeline dry-run trên copy PASS, không gửi thật. Cron canonical SQLite còn enabled 27/09 06:28/06:50. Disk 85% (~15GiB available); cleanup mới là proposal, chưa xoá. Chi tiết entry audit đầu `SESSION_HANDOVER.md`.
- Đã kiểm đúng **một Hostinger VPS KVM2, 2 vCPU/8GiB** qua `ssh vps` và hPanel. CPU limitation của Hostinger đã gỡ; mẫu cuối CPU 1–11%, steal 0–4%. Đây là snapshot, cần đo lại khi điều tra.
- Hưng Rẻo + Sức Khoẻ: systemd user services `openclaw-gateway-{hungreo,suckhoe}.service`, OpenClaw 2026.9.6; main GPT-6 Sol, sub GPT-6 Luna. Catalog Codex OFF, voice OFF. Healthcheck timer đã bật lại, cả hai probe PASS.
- Nemo: Docker **`nemo-sandbox`**, 2026.9.6, main Muse Spark 1.3 contributor; fallback `[]` theo GO Hưng. Giới hạn **1 CPU / 2GiB** đã khôi phục, phải giữ khi recreate.
- Production main runtime: `~/openclaw-upgrade-20260924/` (**không xoá**); CLI `/home/hung/bin/openclaw`. Nemo runtime mount `/home/hung/sandbox-nemo/runtime-9.6` → `/sandbox/runtime` read-only. Config/state Nemo dưới `/home/hung/sandbox-nemo/config`, file projection `openclaw.json` mount read-only trong gateway; config mutation dùng official CLI khi gateway dừng.
- Hưng xác nhận cả ba Telegram trả lời; model smoke main PASS. Recovery artifacts `/home/hung/backups/cpu-recovery-20260926/`. Backup mới 27/09 02:15 + restore-check 03:00 **chưa verify lượt thật**. Chi tiết/giới hạn: entry đầu `SESSION_HANDOVER.md`.

---

## ✅ Runtime patch OBSOLETE — đã merge upstream (2026-05-04)

**openclaw 2026.5.3-1 đã bao gồm upstream fix cho context-engine startup bug.** Runtime patch do Codex apply cho 2026.5.2 KHÔNG còn cần thiết nữa.

Backup artifacts vẫn còn trên VPS (tham khảo nếu cần rollback về 2026.5.2):

- `/home/hung/backups/openclaw-runtime-patch-20260503-154350/` — pre-patch full state
- `/tmp/openclaw-runtime-patch-20260503/openclaw-2026.5.2.tgz` — patched tarball

---

## ⚡ Session Handoff — 2026-09-21 14:22 +07 (MỚI NHẤT — ĐỌC PHẦN NÀY TRƯỚC)

### 1. Nâng cấp Pipeline Nghiên cứu & Khử trùng Tin tức AI cho Hermes — Issue `VPS-20260921-001`

- **Hiện tượng**: Bản tin sáng 21/09 của Hermes chỉ gửi 1 tin AI (CodeQL).
- **Root cause 4 điểm**:
  1. _Dedupe window quá dài_: Áp luật `NEWS_HISTORY_7D` gây mâu thuẫn với cửa sổ 72h và kìm hãm vendor năng động.
  2. _Nguồn candidate quá hẹp_: Chỉ theo dõi 8 repo cố định, bỏ sót TypeSafe Jev model và tooling agentic.
  3. _Prompt tự mâu thuẫn_: Liệt kê (5) lane nhưng câu kiểm tra chốt chặn vẫn ghi "sau khi đã quét đủ bốn lane".
  4. _Show HN query thiếu filter ngữ cảnh_: Lọt các ứng dụng không thuộc mảng AI (như Meetup Radius).
- **Giải pháp đã triển khai & Verify**:
  1. _`daily_news_ai_history.py`_: Cắt dedupe xuống 3 ngày (`NEWS_HISTORY_3D`); mở rộng 12 GitHub repos (+`PydanticAI`, `Ollama`, `LiteLLM`, `vLLM`); tích hợp radar OpenRouter models 72h + Hacker News FrontPage (>60 pts) + Show HN (>=30 pts có regex lọc từ khóa AI).
  2. _`jobs.json`_: Sửa prompt đồng bộ `NEWS_HISTORY_3D`, đổi luật tần suất vendor thành 3 ngày, sửa validation thành "quét đủ cả năm lane".
- **Verification**: Đã test live bắt thành công release PydanticAI (tích hợp TypeSafe Jev), OpenRouter GLM-5.3-FlashX, Show HN CUA-S1; loại bỏ thành công Meetup Radius. Validate syntax `jobs.json`.
- **Registry & Backup**: Đã đăng ký `VPS-20260921-001` trạng thái `resolved` trong VPS Ops Issue Registry; rebuild `ISSUE_LOG.md`. Backup tại `/home/hung/backups/hermes-showhn-filter-20260921-142005/`.

---

## ⚡ Session Handoff — 2026-09-19 07:45 +07

### 1. Sửa dứt điểm sự cố Morning Brief trùng tin (`similar_title`) — Issue `VPS-20260919-001`

- **Triệu chứng sáng 19/09**: Pipeline bản tin sáng của `suckhoe` bị sập ở cả 2 lượt 06:28 và 06:50 VNT với lỗi `world: item 2 trùng/na ná item trước (similar_title)`.
- **Root cause 2 tầng**:
  1. _Upstream (06:28 VNT)_: Hàm `title_similarity` dùng `set(split())` không tách dấu phẩy (`"us,"` $\neq$ `"us"`), khiến 2 tin cùng về thỏa thuận Mỹ – Đan Mạch tại Greenland (France 24 và BBC) chỉ có similarity 0.4545 ($< 0.50$), bị lọt vào `items.json`.
  2. _Downstream_: Bản dịch tiếng Việt cô đọng lại làm trùng 8/9 từ (similarity 0.8888 $> 0.58$). `validate_section_news_quality` nằm ngoài try/catch của từng item ném `RuntimeError` làm sập việc tạo file.
- **Giải pháp 2 tầng đã triển khai (`bsy_morning_brief.py`)**:
  1. _Upstream Hardening_: `title_similarity` strip toàn bộ punctuation trước khi so sánh (`0.4545 → 0.5454 > 0.50`), giúp `pick_top` loại bỏ tin trùng ngay từ lượt 06:28 và bốc candidate tiếp theo. Bổ sung `deal` action và `denmark`, `greenland` vào `directed_event_key`.
  2. _Downstream Graceful Handling (Chỉ đạo của Hưng)_: `write_editorial_sections` rà soát dedup nội bộ sau dịch. Nếu phát hiện tin trùng mà không có tin thay thế, tự động loại bỏ tin trùng thứ 2, ghi warning vào manifest, và xuất bản an toàn **2/3 tin** (`✨ 2 điểm đáng chú ý sáng nay:`). `validate_rendered_news_files` nới lỏng guardrail thành `2 <= len(items) <= 3`.
- **Verification & Test Suites**:
  - Regression test `test_incident_20260919.py`: RED (2 failures, 1 error) $\rightarrow$ GREEN (3/3 PASS).
  - Full test suite: **75/75 tests PASS**.
  - Nghiệm thu thực tế ngày 19/09: `manifest.status` = `ready`, đã gửi thành công vào Telegram của Hưng (Msg ID `5065`).
  - Đã đăng ký và phân loại `resolved` trong VPS Ops Issue Registry (`/home/hung/openclaw-shared/ops-issues/bin/ops_issue show VPS-20260919-001`) và rebuild `ISSUE_LOG.md`.
  - Backup: `/home/hung/backups/morning-brief-similar-title-fix-20260919-0731/`.
- **Kế hoạch Monitoring**: Quan sát lượt chạy tự động 06:28 VNT sáng mai (20/09/2026) để xác nhận pipeline chạy mượt mà ngay lần đầu.

---

## ⚡ Session Handoff — 2026-09-18 07:12 +07

### 1. Nguyên tắc Timeline VNT (Bắt buộc tuân thủ cho mọi Bots & Agents)

- **Timezone chuẩn**: `Asia/Ho_Chi_Minh` (UTC+7 / VNT) **ALWAYS**.
- **Khung giờ Morning Brief (Bsy Rùa)**:
  - **06:28 VNT**: Pipeline tự động khởi chạy (tổng hợp thời tiết, tin tức, biên tập).
  - **06:40 VNT**: Mốc giao tin chuẩn (Golden delivery target trước khi Hưng & gia đình sinh hoạt).
  - **06:50 VNT**: Hạn chót cứu vãn (Final catch-up retry).
  - **> 06:50 VNT**: Hard cutoff / Fail-closed. Nếu lỗi sau lần thử lại, gửi thông báo fail-safe và dừng.
  - **CẤM TUYỆT ĐỐI**: Không tự tiện bắn bản tin sáng sau **07:00 VNT** vì người nhận đã bắt đầu nhịp làm việc/đi làm, tin dài sẽ trở thành nhiễu (noise/distraction).

### 2. Sửa dứt điểm lỗi tái diễn `ProtectedFactError` (Morning Brief Pipeline)

- **Root cause tái diễn**: LLM tự suy diễn các cụm từ thời gian tương đối (vd: "tối qua" $\rightarrow$ "tối 16-9") hoặc làm tròn số/đơn vị. Validator `validate_protected_facts` phát hiện số mới chưa từng có trong bài báo gốc nên kích hoạt fail-closed. Trước đây các bản vá chỉ chữa triệu chứng bằng regex trong validator thay vì chặn từ prompt và có cơ chế fallback.
- **Giải pháp 2 tầng đã triển khai**:
  1. _Upstream Prompt Hardening (`bsy_morning_brief_pipeline.py`)_: Thêm luật cấm LLM tự suy diễn ngày số từ từ ngữ tương đối ("tối qua", "hôm qua" phải giữ nguyên chữ). Mọi con số trong bản tóm tắt phải xuất hiện nguyên văn trong nguồn.
  2. _Downstream Graceful Fallback (`bsy_morning_brief.py`)_: Trong `write_editorial_sections`, nếu một tin vi phạm `ProtectedFactError`, tự động giáng cấp (fallback) tin đó về bản gốc đã sanitize/polish (`fallback_item`) thay vì raise lỗi giết chết cả pipeline. Bản tin vẫn được giao đúng giờ 06:40 với dữ liệu trung thực 100%.
- **Regression test**: Đã thêm `test_incident_20260918.py` (RED trước khi sửa $\rightarrow$ GREEN sau khi sửa). All test suites PASS.

---

## ⚡ Session Handoff — 2026-09-11 08:56 +07

### Subagents Model Cutover: DeepSeek → OpenRouter Meta Muse Spark 1.3

- **Lý do**: Ngừng nạp credits DeepSeek, gom toàn bộ về OpenRouter.
- **`hungreo`**: `subagents.model.fallbacks` $\rightarrow$ `["openai/gpt-5.6-sol", "openrouter/meta/muse-spark-1.3-contributor"]`.
- **`suckhoe`**: `subagents.model.fallbacks` $\rightarrow$ `["openrouter/meta/muse-spark-1.3-contributor"]`.
- **`nemotron` (legacy inactive)**: cả `primary` và `subagents.model.primary` $\rightarrow$ `openrouter/meta/muse-spark-1.3-contributor`.
- **Policy `AGENTS.md` (hungreo)**: cập nhật đồng bộ model fallback.
- **Verification**: `systemctl --user is-active` cả 2 gateway đều active; channel status probe `@hungreo_openbot` và `@hungreo_suckhoe_bot` đều pass 100%.

---

## ⚡ Session Handoff — 2026-09-05 05:43 +07

### Sandbox Nemo Containerized — OpenClaw 2026.9.1 + Meta Muse Spark 1.3

| Component           | Version / Target                                            | Ghi chú                                                                |
| :------------------ | :---------------------------------------------------------- | :--------------------------------------------------------------------- |
| **Container**       | `nemo-sandbox` (`node:22-bookworm-slim`)                    | User `1001:1001`, RAM max 1.2G, CPU max 1.0, Mount isolated `/sandbox` |
| **OpenClaw**        | **2026.9.1**                                                | Isolated install tại `/home/hung/sandbox-nemo/runtime/`                |
| **Primary Model**   | `openrouter/meta/muse-spark-1.3`                            | Active ✅ (18+ confirmed, thinking=off)                                |
| **Fallback Model**  | `openrouter/meta-llama/llama-4-scout`                       | Active ✅                                                              |
| **Telegram Bot**    | `@hungreo_bot` (port 8789 via Caddy)                        | Active ✅                                                              |
| **Gateway Port**    | `18796` (loopback publish)                                  | Active ✅                                                              |
| **Snapshot Backup** | `/home/hung/backups/sandbox-nemo-2026-09-05.tar.gz` (129MB) | Đã lưu an toàn                                                         |
| **Production Bots** | `hungreo` (port 18789) + `suckhoe` (port 18795)             | **AN TOÀN TUYỆT ĐỐI**, PID 2689028 / 2688243 giữ nguyên từ 24/08       |
| **Hermes**          | `@hungreo_bds_bot` (PID 2659659)                            | Giữ nguyên vẹn, không chạm                                             |

**Negative Check Isolation Verified (2026-09-05):**

- Trong container: `ls /home/hung/.openclaw-hungreo` $\rightarrow$ `No such file or directory` ✅
- Trong container: `ls /home/hung/.openclaw-suckhoe` $\rightarrow$ `No such file or directory` ✅
- Trong container: `ls /var/run/docker.sock` $\rightarrow$ `No such file or directory` ✅
- User: `uid=1001 gid=1001` (Unprivileged) ✅

---

## ⚡ Session Handoff — 2026-05-08 15:21 +07

| openclaw VPS | **2026.5.7** | ✅ Patch 2 re-applied. Patch 1 upstream-fixed. |
| openclaw npm | **2026.5.7** | Latest stable |
| lossless-claw | **0.9.4** | ✅ Unchanged (already latest). Symlinks intact. |
| hungreo model | **openai-codex/gpt-5.5** | active ✅ |
| suckhoe model | **openai-codex/gpt-5.5** | active ✅ |
| nemotron | VER=**2026.5.7** | active ✅, model: deepseek/deepseek-v4-pro |

**Services (verified 15:21 +07):**

- `openclaw-gateway-hungreo` → active, `OPENCLAW_SERVICE_VERSION=2026.5.7` ✅
- `openclaw-gateway-suckhoe` → active, `OPENCLAW_SERVICE_VERSION=2026.5.7` ✅
- `openclaw-gateway-nemotron` → active, `OPENCLAW_SERVICE_VERSION=2026.5.7` ✅

**UAT (2026-05-08 CLI):** 1 payload `FINAL_ONLY_OK`, `toolSummary.calls=1`, `failures=0` ✅

**⚠️ Active runtime patch — Patch 2 (cần biết cho lần upgrade tiếp):**

- File: `dist/openclaw-tools-0ftkmYS3.js`
- Fix: `...!embedded && messageTool` → `...messageTool` (message tool luôn available trong embedded mode)
- Upstream chưa fix trong 2026.5.7. Backup: `dist/openclaw-tools-0ftkmYS3.js.bak-20260508-1521-pre-patch2`
- **Khi upgrade openclaw tiếp**: grep file dist mới cho `!embedded && messageTool` — nếu còn → re-apply
- **Sed command**: `sed -i 's/\.\.\.!embedded && messageTool ? \[messageTool\] : \[\]/...messageTool ? [messageTool] : []/g' $TARGET`

**Patch 1 (final-only payload):** KHÔNG còn cần re-apply — upstream đã fix từ 2026.5.4.

**`google` plugin trong hungreo:** xuất hiện vì openclaw activate plugin entry đã có sẵn trong config. Bình thường.

**⚠️ Persistent gotchas (vẫn còn):**

- `plugins install --pin --force` reset `installs.json startup.memory → false` → re-patch sau đó
- `@mariozechner` symlinks **có thể bị xóa** sau mỗi lần upgrade binary (`npm/node_modules/@mariozechner/` bị tái tạo fresh). **Kiểm tra cả 3 profiles** sau upgrade — nemotron hay bị nhất.
- "Duplicate plugin id detected" warning là HARMLESS
- `toolSummary` nằm ở `result.meta.toolSummary` (không phải top-level) trong `agent --json` output

### Backup files (2026-05-08)

- `~/.openclaw-{hungreo,suckhoe,nemotron}/openclaw.json.bak-20260508-1521-pre-upgrade-2026.5.7`
- `~/.config/systemd/user/openclaw-gateway-{hungreo,suckhoe}.service.d/override.conf.bak-20260508-1521-pre-2026.5.7`
- `~/.config/systemd/user/openclaw-gateway-nemotron.service.bak-20260508-1521-pre-2026.5.7`
- `~/.npm-global/lib/node_modules/openclaw/dist/openclaw-tools-0ftkmYS3.js.bak-20260508-1521-pre-patch2`

---

## ⚡ Session Handoff — 2026-05-07 11:29 +07

### Upgrade → openclaw 2026.5.6 + Patch 2 re-applied

| Component     | Version      | Ghi chú                                    |
| ------------- | ------------ | ------------------------------------------ |
| openclaw VPS  | **2026.5.6** | Patch 2 file: `openclaw-tools-BDIFP6nv.js` |
| lossless-claw | **0.9.4**    | Symlinks intact                            |

**UAT (2026-05-07):** PASS ✅

### Backup files (2026-05-07)

- `~/.openclaw-{hungreo,suckhoe,nemotron}/openclaw.json.bak-20260507-1129-pre-upgrade-2026.5.6`
- `dist/openclaw-tools-BDIFP6nv.js.bak-20260507-1129-pre-patch2`

---

## ⚡ Session Handoff — 2026-05-06 10:01 +07

### Upgrade → openclaw 2026.5.4 + lossless-claw 0.9.4 + Patch 2 re-applied

| Component     | Version                  | Ghi chú                                                           |
| ------------- | ------------------------ | ----------------------------------------------------------------- |
| openclaw VPS  | **2026.5.4**             | ✅ Upstream fix final-only payload (Patch 1). Patch 2 re-applied. |
| openclaw npm  | **2026.5.4**             | Latest stable                                                     |
| lossless-claw | **0.9.4**                | ✅ context assembly fixes, tools guard. Symlinks intact.          |
| hungreo model | **openai-codex/gpt-5.5** | active ✅                                                         |
| suckhoe model | **openai-codex/gpt-5.5** | active ✅                                                         |
| nemotron      | VER=**2026.5.4**         | active ✅, model: deepseek/deepseek-v4-pro                        |

**UAT (2026-05-06 CLI):** 1 payload `FINAL_ONLY_OK`, `toolSummary.calls=1`, no fallback ✅

**⚠️ Patch 2 file (2026.5.4):** `dist/openclaw-tools-Lbc6zzNy.js`
Backup: `/home/hung/backups/openclaw-runtime-pre-254-20260506-095326/`

**hungreo-xfeed poll.mjs:** ĐÃ được patch riêng (2026-05-06 sáng). Không liên quan openclaw upgrade.
Backup: `/home/hung/backups/hungreo-xfeed-20260506/poll.mjs.bak-20260506-092109-pre-format`

### Backup files (2026-05-06)

- `~/.openclaw-{hungreo,suckhoe,nemotron}/openclaw.json.bak-20260506-*-pre-upgrade-2026.5.4`
- `/home/hung/backups/openclaw-runtime-pre-254-20260506-095326/` (patched dist files trước upgrade)

---

## ⚡ Session Handoff — 2026-05-02 (ĐỌC PHẦN NÀY TRƯỚC)

### Service mới deploy: `hungreo-xfeed` (auto X→Telegram feed)

**Mục đích**: Tự động poll 5 X accounts và forward tweet mới vào Telegram group `learning-research` (topic). Replacement cho RSS.app/IFTTT (free tier 2026 không đủ cho use case này).

**Topology mới (verified 2026-05-02 16:40 +07):**

| Component       | Path / ID                                                                                  |
| --------------- | ------------------------------------------------------------------------------------------ |
| Project dir     | `/home/hung/Development/hungreo-xfeed/`                                                    |
| Script          | `poll.mjs` (Node 22+ ESM, native fetch, ~150 dòng)                                         |
| Secrets         | `.env` (chmod 600) — bot token, chat_id, topic_id, Apify token                             |
| Accounts list   | `accounts.txt` — 5 usernames: `steipete`, `sama`, `AnthropicAI`, `claudeai`, `openclaw`    |
| Dedup state     | `state.json` — array `seen[]` cap 5000 IDs                                                 |
| systemd service | `~/.config/systemd/user/hungreo-xfeed.service` (oneshot)                                   |
| systemd timer   | `~/.config/systemd/user/hungreo-xfeed.timer` — `OnCalendar=07:00 + 19:00 Asia/Ho_Chi_Minh` |
| Telegram bot    | `@hungreo_scrapper_bot` (token in `.env`, NOT in this file)                                |
| Telegram target | Group `Hung & 🐢 Rùa` (`chat_id=<R>`), topic `learning-research` (`message_thread_id=2`)   |
| Apify actor     | `dead00/twitter-profile-scraper-no-cookies` ($0.0036/profile)                              |
| Cost forecast   | ~$1.08/tháng (60 polls × 5 profiles × $0.0036) — fits $5 free tier                         |

**Pending action cho Hưng**: rotate cả `TELEGRAM_BOT_TOKEN` + `APIFY_TOKEN` (đã share trong chat history setup → không an toàn lâu dài). SOP rotate xem `kb/hungreo-xfeed-runbook.md` mục "Rotate secrets".

**Runbook đầy đủ**: `kb/hungreo-xfeed-runbook.md`
**Lesson về Apify Twitter scraping 2026**: `kb/lessons-learned.md` entry 2026-05-02

**Service state**: `systemctl --user is-active hungreo-xfeed.timer` → `active (waiting)`. Lần post tin thật đầu tiên: 19:00 VNT 2026-05-02.

---

## ⚡ Session Handoff — 2026-05-01

### State tổng hợp (verified 2026-05-01 07:15 +07)

| Component     | Version                  | Ghi chú                                    |
| ------------- | ------------------------ | ------------------------------------------ |
| openclaw VPS  | **2026.4.29**            | ✅ Upgraded từ 2026.4.27 hôm nay           |
| openclaw npm  | **2026.4.29**            | Latest stable                              |
| lossless-claw | **0.9.2**                | OK, không drift                            |
| hungreo model | **openai-codex/gpt-5.5** | active ✅                                  |
| suckhoe model | **openai-codex/gpt-5.5** | active ✅                                  |
| nemotron      | VER=**2026.4.29**        | active ✅, model: deepseek/deepseek-v4-pro |

**Services (verified 07:15 +07):**

- `openclaw-gateway-hungreo` → active, `OPENCLAW_SERVICE_VERSION=2026.4.29` ✅
- `openclaw-gateway-suckhoe` → active, `OPENCLAW_SERVICE_VERSION=2026.4.29` ✅
- `openclaw-gateway-nemotron` → active, `OPENCLAW_SERVICE_VERSION=2026.4.29` ✅

### Backup files (2026-05-01)

- `~/.openclaw-hungreo/openclaw.json.bak-20260501-0702-pre-upgrade-2026.4.29`
- `~/.openclaw-suckhoe/openclaw.json.bak-20260501-0702-pre-upgrade-2026.4.29`
- `~/.openclaw-nemotron/openclaw.json.bak-20260501-0702-pre-upgrade-2026.4.29`
- `~/.config/systemd/user/openclaw-gateway-{hungreo,suckhoe}.service.d/override.conf.bak-20260501-0702-pre-2026.4.29`

### ⏳ Pending decisions (cần Hưng quyết định)

1. **Nemo version-check cron — cutover DONE:**
   - Claude Code scheduled job (job gốc trên hungreo) đã bị **Hưng remove** qua Claude Code app (2026-05-02)
   - Chỉ còn **Nemo cron `9c696250`** (6:30 AM VNT) là version check duy nhất
   - Monitoring phase kết thúc — không cần cutover thêm gì nữa

### Caddy incident + fix (2026-04-30 ~18:30 +07)

**Root cause:** Sau reboot CVE patch, Caddy start với `--config /etc/caddy/Caddyfile` nhưng `/etc/caddy/` không tồn tại → Caddy load từ persisted memory (thiếu Nemo route).

**Symptoms:**

- Nemo webhook 404 (Caddyfile không có `/telegram-webhook-nemotron` route)
- Hungreo 500 (model warmup timeout ngay sau reboot, tự hết sau ~5 phút)

**Fix đã apply:**

1. Thêm `/telegram-webhook-nemotron → 127.0.0.1:8789` vào `/home/hung/n8n-edge/Caddyfile`
2. Reload Caddy qua Admin API (`POST localhost:2019/load`)
3. Tạo symlink cố định: `mkdir -p /etc/caddy && ln -sf /home/hung/n8n-edge/Caddyfile /etc/caddy/Caddyfile`

**Caddy topology (verified):**

- Config file: `/home/hung/n8n-edge/Caddyfile` (symlinked từ `/etc/caddy/Caddyfile`)
- Routes: `bot.hungreo.com` → hungreo:8787, suckhoe:8788, **nemotron:8789** ✅
- Sau reboot tiếp theo: Caddy sẽ load đúng Caddyfile qua symlink

---

## ⚡ Session Handoff — 2026-04-30

### Upgrade cả 3 services → 2026.4.27 (verified 13:30 +07)

| Component     | Version                  | Ghi chú                             |
| ------------- | ------------------------ | ----------------------------------- |
| openclaw VPS  | **2026.4.27**            | ✅ Upgraded từ 2026.4.26 2026-04-30 |
| openclaw npm  | **2026.4.27**            | Latest stable                       |
| lossless-claw | **0.9.2**                | OK, không drift                     |
| hungreo model | **openai-codex/gpt-5.5** | Giữ nguyên                          |
| suckhoe model | **openai-codex/gpt-5.5** | Giữ nguyên                          |
| nemotron      | VER=**2026.4.27**        | ✅ Upgraded 2026-04-30              |

- `openclaw-gateway-hungreo` → active, `OPENCLAW_SERVICE_VERSION=2026.4.27`, model: openai-codex/gpt-5.5 ✅
- `openclaw-gateway-suckhoe` → active, `OPENCLAW_SERVICE_VERSION=2026.4.27`, model: openai-codex/gpt-5.5 ✅
- `openclaw-gateway-nemotron` → active, `OPENCLAW_SERVICE_VERSION=2026.4.27`, model: deepseek/deepseek-v4-pro ✅

### Backup files (2026-04-30)

- `~/.openclaw-hungreo/openclaw.json.bak-20260430-1327-pre-upgrade-2026.4.27`
- `~/.openclaw-suckhoe/openclaw.json.bak-20260430-1327-pre-upgrade-2026.4.27`
- `~/.config/systemd/user/openclaw-gateway-{hungreo,suckhoe}.service.d/override.conf.bak-20260430-1327-pre-2026.4.27`
- `~/.config/systemd/user/openclaw-gateway-nemotron.service.bak-20260430-1313-pre-2026.4.27` (main service file — Nemo không dùng override.conf pattern)

### Lesson mới ghi nhận (2026-04-28)

- Lần này `openclaw update` **KHÔNG** ghi đè ExecStart về fallback path (khác 2026-04-23). ExecStart vẫn trỏ npm-global đúng. Nhưng `OPENCLAW_SERVICE_VERSION` string vẫn bị giữ nguyên version cũ → vẫn phải update override.conf thủ công sau mỗi upgrade.
- Nemo không nên tự đề xuất upgrade plan cho chính mình — conflict of interest. Nemo chỉ nên phát hiện + report, để Claude Code hoặc Hưng quyết định.

### Suckhoe mental safety refresh (verified 13:50 +07)

- Patched `suckhoe` workspace mental support guardrails and approved KB:
  - `/home/hung/.openclaw-suckhoe/workspace/SOUL.md`
  - `/home/hung/.openclaw-suckhoe/workspace/skills/mental-wellness-support/SKILL.md`
  - `/home/hung/.openclaw-suckhoe/workspace/skills/mental-wellness-support/references/{red-flags,handoff,source-map}.md`
  - `/home/hung/.openclaw-suckhoe/workspace/skills/hungreo-source-governance/references/whitelist.md`
  - `/home/hung/openclaw-shared/kb/medical/approved/mental_wellness_low_mood_red_flags_2026-03-08.md`
- Backups suffix: `.bak-20260428-134955-mental-safety`.
- Source safety change: added `samhsa.gov` to whitelist, added SAMHSA/988, NIMH warning signs, CDC stress, and WHO Psychological First Aid as preferred mental-health safety sources.
- Behavior guardrail added: mental and physical health influence each other, but `suckhoe` must not say physical illness is "just stress" or imply symptoms are the user's fault.
- Crisis routing added: Viet Nam/unknown family context → `115` + nearest emergency care + trusted nearby person; US context → `988` for mental-health crisis and `911` for immediate danger.
- Verification: `openclaw --profile suckhoe config validate` passed; service remained active/reachable on `ws://127.0.0.1:18795`.

### Cron job migration (2026-04-28) — version check

- **Nemo** có cron `openclaw-version-check-daily` (ID: `9c696250`) chạy **6:30 AM VNT** (parallel với hungreo 7:00)
- Model: `deepseek/deepseek-v4-pro` | Delivery: `telegram:<R>`
- Giai đoạn: **monitoring** — chạy song song hungreo để so sánh output trước khi cutover
- Nemo `web_fetch.maxChars` tăng 6000 → 10000 để đủ đọc CHANGELOG

---

### Nemo DeepSeek trial audit (verified 10:05 +07)

- `openclaw-gateway-nemotron.service` → active, gateway reachable on `ws://127.0.0.1:18796`, local Telegram webhook listener on `127.0.0.1:8789`.
- Service runtime: `OPENCLAW_SERVICE_VERSION=2026.4.24`; use `/home/hung/.npm-global/bin/openclaw --profile nemotron ...` for CLI checks. The default `openclaw` binary can still print the older `2026.4.12` CLI version.
- Primary model remains `deepseek/deepseek-v4-pro` via DeepSeek direct API; fallback remains `custom/nvidia/nemotron-3-super-120b-a12b`.
- Plugins loaded after restart: `lossless-claw`, `memory-core`, `telegram`.
- `memory-core` startup note: first restart installed missing runtime dependency `chokidar` in ~4.2s, then created the managed dreaming cron job. No follow-up error seen.
- Since restart at 09:00, no new `stuck session`, `FailoverError`, `model-fallback`, or timeout was observed in Nemo logs.

### Nemo guardrails now live

- Workspace files with guardrail sections:
  - `/home/hung/.openclaw-nemotron/workspace/SOUL.md`
  - `/home/hung/.openclaw-nemotron/workspace/AGENTS.md`
  - `/home/hung/.openclaw-nemotron/workspace/TOOLS.md`
- Rule of thumb for Rèo:
  - Nemo + DeepSeek: public, low-risk, non-sensitive tasks only.
  - Hungreo/OpenAI/Claude: sensitive, personal, health/family, financial, secrets, business-critical, or irreversible actions.
  - When unsure, redact first or route away from DeepSeek.

### Controlled tests run on 2026-04-28

- Short workflow test via Gateway, non-delivered CLI call:
  - Command shape: `/home/hung/.npm-global/bin/openclaw --profile nemotron agent --json --timeout 180 --session-id main --message ...`
  - Result: success in ~41s wall time, agent duration ~26s.
  - Tools used: `exec`, `session_status`, `gateway`; no subagent, no fallback, no tool failure.
  - Output used `Verified` evidence and correctly identified active service/model.
- Long progress test via Gateway, non-delivered CLI call:
  - Task: progress payload before `sleep 95 && echo PROGRESS_TEST_DONE`.
  - Result: success in ~116s wall time, agent duration ~107s.
  - Tools used: `exec`, `process`; no subagent, no fallback.
  - Nemo emitted progress payloads in the agent result, but CLI did not stream them live to the terminal. For real Telegram "not missing" behavior, test via Telegram delivery or implement a runtime interim-status wrapper.

### Telegram reply footer decision

- Do not enable `telegram-reply-footer` for Nemo yet.
- Existing plugin in `hungreo` appends `Model used: ...` to normal Telegram replies, not just fallback replies, so it is likely noisy for Nemo.
- If fallback visibility is needed, prefer a fallback-only footer/plugin or a runtime event note instead of enabling the current footer as-is.

---

## ⚡ Session Handoff — 2026-04-27

### Nemo config thay đổi (verified 05:25 +07)

- **Primary model:** `deepseek/deepseek-v4-pro` — **direct API** (không qua OpenRouter)
- **Provider:** custom `deepseek` với `baseUrl: https://api.deepseek.com/v1`
- **Key:** `DEEPSEEK_API_KEY` trong `~/.openclaw-nemotron/.env`
- **Fallback:** `custom/nvidia/nemotron-3-super-120b-a12b`
- **Tốc độ:** ~7s/reply (trước: ~35s do OpenRouter shared pool 429)
- **Backup:** `~/.openclaw-nemotron/openclaw.json.bak-20260427-pre-deepseek-direct`

### Services (verified 05:25 +07)

- `openclaw-gateway-hungreo` → active, `OPENCLAW_SERVICE_VERSION=2026.4.24` ✅
- `openclaw-gateway-suckhoe` → active, `OPENCLAW_SERVICE_VERSION=2026.4.24` ✅
- `openclaw-gateway-nemotron` → active, model: `deepseek/deepseek-v4-pro` (direct) ✅

### Done trong session 2026-04-27

- ✅ Setup DeepSeek V4 Pro trực tiếp cho Nemo (bypass OpenRouter)
- ✅ Verified: `/status` xác nhận `deepseek/deepseek-v4-pro · api-key (env: DEEPSEEK_API_KEY)`
- ✅ Tốc độ ổn định ~7s, không còn 429

---

## ⚡ Session Handoff — 2026-04-26 (MỚI NHẤT — ĐỌC PHẦN NÀY TRƯỚC)

### Versions hiện tại (verified 11:40 +07)

| Component     | Version                  | Ghi chú                          |
| ------------- | ------------------------ | -------------------------------- |
| openclaw VPS  | **2026.4.24**            | ✅ Upgraded từ 2026.4.23 hôm nay |
| openclaw npm  | **2026.4.24**            | Latest stable                    |
| lossless-claw | **0.9.2**                | OK, không cần đổi                |
| hungreo model | **openai-codex/gpt-5.5** | Giữ nguyên từ 2026-04-25         |
| suckhoe model | **openai-codex/gpt-5.4** | Giữ nguyên                       |

### Services (verified 11:40 +07)

- `openclaw-gateway-hungreo` → active, `OPENCLAW_SERVICE_VERSION=2026.4.24` ✅
- `openclaw-gateway-suckhoe` → active, `OPENCLAW_SERVICE_VERSION=2026.4.24` ✅
- `openclaw-gateway-nemotron` → active, **KHÔNG TOUCH**

### Done trong session 2026-04-26

- ✅ Upgrade openclaw 2026.4.23 → 2026.4.24 (hungreo + suckhoe)
- ✅ lossless-claw@0.9.2 confirmed OK (không cần force-pin)
- ✅ override.conf updated → 2026.4.24, daemon-reload, restart sạch
- ✅ Verify: VER=2026.4.24, active, không có fallback-note

### Backup files (2026-04-26)

- `~/.openclaw-hungreo/openclaw.json.bak-20260426-1140-pre-upgrade-2026.4.24`
- `~/.openclaw-suckhoe/openclaw.json.bak-20260426-1140-pre-upgrade-2026.4.24`
- `~/.config/systemd/user/openclaw-gateway-{hungreo,suckhoe}.service.d/override.conf.bak-20260426-*`

---

## ⚡ Session Handoff — 2026-04-25 (ĐỌC PHẦN NÀY TRƯỚC)

### Versions hiện tại (verified 08:00 +07)

| Component     | Version                  | Ghi chú                  |
| ------------- | ------------------------ | ------------------------ |
| openclaw VPS  | **2026.4.23**            | ✅ Upgraded từ 2026.4.22 |
| lossless-claw | **0.9.2**                | OK                       |
| hungreo model | **openai-codex/gpt-5.5** | ✅ Switched từ gpt-5.4   |
| suckhoe model | **openai-codex/gpt-5.4** | Giữ nguyên               |

### Done trong session 2026-04-25

- ✅ Upgrade openclaw 2026.4.22 → 2026.4.23 (hungreo + suckhoe)
- ✅ override.conf updated → 2026.4.23, daemon-reload, restart sạch
- ✅ Switch hungreo primary → openai-codex/gpt-5.5
- ✅ Log verified: `[gateway] agent model: openai-codex/gpt-5.5`, không có fallback line

---

## ⚡ Session Handoff — 2026-04-24 (ĐỌC PHẦN NÀY TRƯỚC)

### Done trong session 2026-04-24

- ✅ Upgrade openclaw 2026.4.21 → 2026.4.22 + fix override.conf SERVICE_VERSION
- ✅ Thử GPT-5.5 → fail → rollback gpt-5.4 (lúc đó chưa có .23 + chưa plug OAuth)
- ✅ Add Fallback Alert + System Alert rules vào AGENTS.md workspace hungreo
- ✅ Night report script: fix binary path + shell errors (hungreo bot tự fix lúc 10:30)
- ✅ Research brief format: cải thiện output (hungreo bot tự fix lúc 10:30)
- 📝 Termius mobile SSH key: chưa tạo — pending Hưng action

### ✅ Issues đã fix (hungreo bot tự làm 10:30)

#### Issue 1 — Night report script dùng binary cũ → FIXED

- Backup: `night_system_report.sh.bak-20260424-issue1`
- `OPENCLAW_BIN` → `/home/hung/.npm-global/bin/openclaw` (2026.4.22)
- `XDG_RUNTIME_DIR` export → `systemctl --user` hoạt động đúng từ cron
- Version lấy từ `OPENCLAW_SERVICE_VERSION` env của process (không dùng `--version`)
- Service fail → `probe_failed` thay vì `unknown`
- Verified: `version=2026.4.22`, `hungreo_active=active`, `suckhoe_active=active`

#### Issue 2 — Research brief format + Phase 3 mapping → FIXED

- Backup: `overnight_research_pipeline.sh.bak-20260424-issue2` (format) + `bak-20260424-phase3fix` (mapping)
- `OPENCLAW_BIN` → `.npm-global` (cùng fix như Issue 1)
- Brief format mới: `📊 Scan: X/Y OK`, `🔑 Top picks numbered`, `⏭️ Cần làm tiếp`, `❌ Fetch failed: URL — reason`
- `_smart_trunc`: cắt đúng ranh giới câu thay vì cắt giữa chừng
- **Phase 3 mapping fix:** bỏ re-parse watchlist (hardcoded MAX=5, ignore dedup) → đọc từ `ITEMS_TSV` của Phase 1
- `mode` truyền vào Python argv → `last_mode` không còn literal `$MODE`
- Edge case verified: 5 URL đã processed → Phase 1 skip đúng, Phase 3 mapping đúng 2 items mới

---

## ⚡ Session Handoff — 2026-04-23 (ĐỌC PHẦN NÀY TRƯỚC)

### Versions hiện tại (verified SSH, 2026-04-23)

| Component     | Version       | Ghi chú                                     |
| ------------- | ------------- | ------------------------------------------- |
| openclaw npm  | **2026.4.21** | Upgraded từ 4.20 sáng 2026-04-23            |
| lossless-claw | **0.9.2**     | Cả 3 profiles: hungreo + suckhoe + nemotron |

### Services (verified 2026-04-23 ~10:35 +07)

- `openclaw-gateway-hungreo.service` → **active**, ready (4 plugins; ~28s), model: gpt-5.4
- `openclaw-gateway-suckhoe.service` → **active**, ready (5 plugins; ~20s), model: gpt-5.4
- `openclaw-gateway-nemotron.service` → **active**, ready (2 plugins; ~24s), model: gemini-2.5-flash

### Upgrade history

| Date       | Component     | From → To             |
| ---------- | ------------- | --------------------- |
| 2026-04-23 | openclaw      | 2026.4.20 → 2026.4.21 |
| 2026-04-22 | openclaw      | 2026.4.15 → 2026.4.20 |
| 2026-04-21 | lossless-claw | 0.9.1 → 0.9.2         |

### ⚠️ CRITICAL upgrade gotcha (discovered 2026-04-23)

`openclaw update --no-restart` tạo local fallback runtime và update `service.d/override.conf` để ExecStart trỏ vào runtime cũ. Services sau khi restart vẫn chạy binary cũ, `/status` báo version cũ.

**Sau mỗi upgrade, LUÔN phải:**

```bash
# 1. Check override.conf
cat ~/.config/systemd/user/openclaw-gateway-{hungreo,suckhoe}.service.d/override.conf

# 2. Update ExecStart về npm-global path + version mới
# Xem SOP đầy đủ: kb/openclaw-upgrade-runbook.md Bước 5

# 3. daemon-reload + restart
systemctl --user daemon-reload
systemctl --user restart openclaw-gateway-suckhoe.service
systemctl --user restart openclaw-gateway-hungreo.service

# 4. Verify
PID=$(systemctl --user show openclaw-gateway-hungreo.service --property=MainPID --value)
strings /proc/$PID/environ | grep OPENCLAW_SERVICE_VERSION
# Expected: OPENCLAW_SERVICE_VERSION=2026.4.21 (không có +fallback-note)
```

**SOP đầy đủ:** `kb/openclaw-upgrade-runbook.md`  
**Lessons log:** `kb/lessons-learned.md`

### Backup files (2026-04-23)

- `~/.openclaw-hungreo/openclaw.json.bak-20260423-*-pre-upgrade`
- `~/.openclaw-suckhoe/openclaw.json.bak-20260423-*-pre-upgrade`
- `~/.openclaw-nemotron/openclaw.json.bak-20260423-*-pre-upgrade`
- `~/.config/systemd/user/openclaw-gateway-{hungreo,suckhoe}.service.d/override.conf.bak-20260423-*`

---

## ⚡ Session Handoff — 2026-04-22 (ĐỌC PHẦN NÀY TRƯỚC)

### Versions hiện tại (verified SSH, 2026-04-22)

| Component       | Version             | Ghi chú                                                |
| --------------- | ------------------- | ------------------------------------------------------ |
| openclaw npm    | **2026.4.22**       | Latest stable; upgrade từ 2026.4.21                    |
| lossless-claw   | **0.9.2**           | Cả 3 locations: hungreo + suckhoe + shared             |
| openclaw binary | 2026.4.12 (1c0672b) | Binary report cũ — services chạy npm package 2026.4.20 |

### Services (verified 2026-04-24 09:28 +07)

- `openclaw-gateway-hungreo.service` → **active**, ready (4 plugins; 4.1s), `OPENCLAW_SERVICE_VERSION=2026.4.22`, model: **openai-codex/gpt-5.5** 🆕
- `openclaw-gateway-suckhoe.service` → **active**, ready (5 plugins; 3.9s), `OPENCLAW_SERVICE_VERSION=2026.4.22`, model: openai-codex/gpt-5.4 (giữ nguyên)
- `openclaw-gateway-nemotron.service` → active (JANGAN DISENTUH / DO NOT TOUCH — nemotron trial riêng)

### Highlights upgrade 2026.4.20

- Cron: `jobs-state.json` tách biệt, fix `delivery.mode: "none"` không còn ghi failure giả
- Security: block `OPENCLAW_*` từ workspace `.env`, siết pairing scope, WebSocket cần `operator.read`
- Breaking change cũ (context-engine ID strict từ 2026.4.14) đã **revert** → lossless-claw 0.9.2 càng stable
- Kimi K2.6 support (chưa bật)

### Upgrade history tóm tắt

| Date       | Component     | From → To             |
| ---------- | ------------- | --------------------- |
| 2026-04-21 | lossless-claw | 0.9.1 → 0.9.2         |
| 2026-04-22 | openclaw      | 2026.4.15 → 2026.4.20 |
| 2026-04-24 | openclaw      | 2026.4.21 → 2026.4.22 |

### Backup files hiện có

- `~/.openclaw-hungreo/openclaw.json.bak-20260422-0838-pre-oc-2026.4.20`
- `~/.openclaw-suckhoe/openclaw.json.bak-20260422-0838-pre-oc-2026.4.20`
- `~/.openclaw-hungreo/openclaw.json.bak-20260421-0549-pre-lcm-0.9.2`
- `~/.openclaw-suckhoe/openclaw.json.bak-20260421-0549-pre-lcm-0.9.2`

### SSH access

```bash
ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i ~/.ssh/hostinger_kvm2 hung@<VPS_IP>
```

> **Mobile note:** Key cần có ở `~/.ssh/hostinger_kvm2`. Nếu dùng mobile mà không có key, dùng Termius để SSH thủ công, rồi paste output vào Claude Code.

### Quick VPS health check (read-only, safe)

```bash
# Chạy trên VPS:
systemctl --user is-active openclaw-gateway-hungreo.service openclaw-gateway-suckhoe.service openclaw-gateway-nemotron.service
npm ls -g openclaw --depth=0 2>/dev/null | grep openclaw
grep '"version"' ~/.openclaw-hungreo/extensions/lossless-claw/package.json
journalctl --user -u openclaw-gateway-hungreo.service -n 5 --no-pager | tail -3
journalctl --user -u openclaw-gateway-suckhoe.service -n 5 --no-pager | tail -3
```

### Plugin install paths (3 locations, upgrade TẤT CẢ)

```bash
# 1. Per-profile hungreo
OPENCLAW_STATE_DIR=/home/hung/.openclaw-hungreo openclaw --profile hungreo plugins install @martian-engineering/lossless-claw@VERSION --pin --force
# 2. Per-profile suckhoe
OPENCLAW_STATE_DIR=/home/hung/.openclaw-suckhoe openclaw --profile suckhoe plugins install @martian-engineering/lossless-claw@VERSION --pin --force
# 3. Shared
openclaw plugins install @martian-engineering/lossless-claw@VERSION --pin --force
```

### Restart order (LUÔN theo thứ tự này)

```bash
systemctl --user restart openclaw-gateway-suckhoe.service
# chờ ~5s
systemctl --user restart openclaw-gateway-hungreo.service
# KHÔNG restart nemotron trừ khi Hưng yêu cầu
```

---

## ⚡ Session Handoff — 2026-04-14 (đọc phần này trước)

### Overnight Research Pipeline — Phase 0 fix completed (2026-04-14 18:05)

**Problem:** Pipeline im lặng 6 ngày (09/04 → 14/04). Watchlist cạn, silent dry-run chỉ log "Dry-run — reminder NOT sent" không báo Hưng.

**Root cause:**

- Watchlist (`memory/research-watchlist.md`) chỉ có 3 URLs cũ từ 02/04, tất cả dedup 7-day window
- Script `overnight_research_pipeline.sh` line 150: khi hết items + dry-run mode → chỉ log, không ghi brief file → `summary_send` 04:40 không có gì gửi

**Fix applied:**

- **Patch line 150** của `scripts/overnight_research_pipeline.sh`:
  - OLD: `log "Dry-run — reminder NOT sent."` (silent)
  - NEW: Ghi reminder vào `logs/overnight-brief-${DATE_VN}.txt` → `summary_send` 04:40 tự deliver qua kênh bình thường
  - Preserve dry-run safety (không auto-send research results)
- **Topup watchlist** +5 URLs (Karpathy LLM Wiki, Karpathy skills, autoresearch, claude-obsidian, ambient programming)
- **Backups:** `bak-20260414-1739-pre-reminder-patch` + `bak-20260414-1739-pre-topup`

**Verification end-to-end:**

- Manual dry-run xử lý 5 URLs OK, brief file generated
- Manual `summary_send` → Telegram Message ID 5659 delivered
- Tonight 2026-04-15 01:00: pipeline auto-run, remaining URLs processed
- Tonight 2026-04-15 04:40: `summary_send` auto-delivers brief

**Pending (reminders cho next sessions):**

- Observe đêm nay 01:00/04:40 có chạy đúng không
- Bơm thêm watchlist sau 1 tuần (thói quen 2-3 URLs/tuần)
- Phase 2 (tùy chọn): Watchlist tự sinh từ chat context analysis — MVP 4-6 giờ dev
- Tech debt: `last_mode: "$MODE"` literal bug trong state file (line 483, cosmetic)

### Overnight Pipeline topology

- **Type:** Linux user crontab (NOT OpenClaw cron — không xuất hiện trong `openclaw cron list`)
- **Schedule:**
  - `0 1 * * *` — `scripts/overnight_research_pipeline.sh --dry-run` (research + brief generation)
  - `40 4 * * *` — `scripts/overnight_summary_send.sh` (Telegram delivery)
- **Paths:**
  - Scripts: `/home/hung/.openclaw-hungreo/workspace/scripts/overnight_*.sh`
  - Watchlist: `/home/hung/.openclaw-hungreo/workspace/memory/research-watchlist.md`
  - Notes output: `/home/hung/.openclaw-hungreo/workspace/memory/overnight-notes/YYYY-MM-DD-research.md`
  - Brief (for send): `/home/hung/.openclaw-hungreo/workspace/logs/overnight-brief-YYYY-MM-DD.txt`
  - State: `/home/hung/.openclaw-hungreo/workspace/memory/overnight-research-state.json`
  - Log: `/home/hung/.openclaw-hungreo/workspace/logs/overnight-research.log`
  - Sent flag: `/home/hung/.openclaw-hungreo/workspace/logs/.overnight-brief-sent-YYYY-MM-DD`
- **Target Telegram:** chat_id `<HUNG_TG_CHAT_ID>` (Hưng DM)
- **Dedup:** 7-day window via `processed_urls` in state.json
- **Trigger manual:** `bash scripts/overnight_research_pipeline.sh --dry-run [--force] [--max-items N]`
- **Plan docs:** Local `~/.claude/plans/vectorized-orbiting-kite.md` + `phase2-actions-log.md`

### Troubleshooting runbook

| Symptom                            | Check                                                           | Fix                                                       |
| ---------------------------------- | --------------------------------------------------------------- | --------------------------------------------------------- |
| Không thấy brief ở Telegram sáng   | `tail -30 logs/overnight-research.log`                          | Check "already processed within 7 days" → topup watchlist |
| Brief file tồn tại nhưng không gửi | `ls -la logs/.overnight-brief-sent-$(date +%F)`                 | Nếu flag exists → xóa để re-send                          |
| Pipeline crashed                   | `journalctl -u cron` hoặc `tail logs/overnight-research.log`    | Check Python/bash errors, restore backup nếu cần          |
| Muốn force-run                     | `bash scripts/overnight_research_pipeline.sh --dry-run --force` | --force bypass RUN_FLAG guard                             |

---

## ⚡ Session Handoff — 2026-04-06

### OpenClaw upgraded to 2026.4.5 (2026-04-06 11:45)

- Upgraded from 2026.4.2 (d74a122) to **2026.4.5 (3e72c03)**
- Method: `sudo npm install -g openclaw@2026.4.5`
- Both services restarted and verified: hungreo (port 18789) + suckhoe (port 18795)
- Telegram webhooks reconnected: `@hungreo_openbot` on 8787, `@hungreo_suckhoe_bot` on 8788
- Config auto-migrated on startup (sha changed, backup created by openclaw at `.bak`)
- Pre-upgrade backup: `openclaw.json.bak-20260406-pre-upgrade-4.5` (both profiles)
- Breaking change in 4.5: legacy config aliases removed (talk.voiceId, agents.\*.sandbox.perSession, etc.) — not affected, load-time compat preserved
- Notable new features: video_generate, music_generate tools, MCP loopback bridge, memory dreaming (experimental), contextVisibility per channel, new providers (Qwen, Fireworks, StepFun)

### Post-upgrade tuning (2026-04-06 18:55)

- **Dreaming enabled:** `plugins.entries.memory-core.config.dreaming` = `{enabled: true, frequency: "0 */6 * * *"}`. Recall store starts at 0 — will populate as conversations accumulate. Thresholds are built-in defaults (minRecallCount=3, minScore=0.8), not overridable via plugin config.
- **Heartbeat tuned:** Added `activeHours` (06:00–23:00 Asia/Ho_Chi_Minh), `lightContext: true`, `suppressToolErrorWarnings: true`
- **Overnight research pipeline fixed** (root cause: stale outputs):
  - Added URL dedup — skip URLs processed within 7 days, auto-send reminder when watchlist exhausted
  - Added prior context injection — synthesis prompt now includes last night's headline/signal to avoid repeating
  - Added GPT-5.4 refiner pass — after Perplexity synthesis, GPT refines with comparison to prior night
  - State now tracks `processed_urls`, `last_headline`, `last_founder_signal`
  - Backup: `overnight_research_pipeline.sh.bak-20260406`
- **SOUL.md Emotional Awareness:** Section already added by Rùa (on VPS) — includes mood detection, celebrate wins, honest pushback, no fake emotions

### Hungreo model config (reverted 2026-04-06)

Gemma 4 trial đã kết thúc. Reverted về:

- **Primary:** `openai-codex/gpt-5.4`
- **Fallback:** `anthropic/claude-sonnet-4-6`
- **Gemma 4 / google provider:** removed khỏi config hoàn toàn
- Backup trước revert: `openclaw.json.bak-20260406-revert-gemma4`

### Gemini API vẫn dùng cho

- `GEMINI_API_KEY` trong `.env` — vẫn giữ, dùng cho:
  - **Skill `gemini`** (CLI binary `/usr/bin/gemini` v0.29.0) — one-shot Q&A
  - **Skill `nano-banana-pro`** — image gen via `gemini-3-pro-image-preview`
  - **memorySearch** — embedding provider (restored to `"gemini"`)

### Plugins

- **Perplexity:** FIXED — added to `plugins.allow`, stock plugin `loaded` (verified via `openclaw plugins list`)
  - Config: `perplexity/sonar-pro`, `PERPLEXITY_API_KEY` in `.env`
- **Lossless-claw:** loaded, contextEngine slot active
- **Telegram-reply-footer:** loaded

### Security hardening (2026-04-06)

- `chmod 600` applied to both config files (hungreo + suckhoe)
- Note: `botToken`, `webhookSecret`, `gateway.auth.token` vẫn plaintext trong config — OpenClaw chưa support env var refs cho các fields này. Mitigation: file perms + no git commit.

### Gemma 4 trial kết luận (lưu để tham khảo)

- Persona/voice: tốt. Memory recall: tốt. Fetch real-time data (BTC): tốt (dùng curl).
- Vẫn confabulate outcomes ("fix xong" khi chưa verify). Thinking leak ra output. Tool call malformed (199 lần/24h `read tool without path`). HTTP 500 từ Google API intermittent.
- Kết luận: không phù hợp làm ops/runtime agent, có thể dùng làm conversational front nếu thử lại.

---

## Mục đích

Dùng file này để không phải nhắc lại vị trí hạ tầng giữa các session.
Agent phải đọc file này trước khi thao tác runtime/deployment.

## Runtime Topology (Đã xác minh)

Verified on: 2026-04-06 11:45 (+07) — OpenClaw 2026.4.5 (3e72c03)

1. Profile: hungreo

- Config: `~/.openclaw-hungreo/openclaw.json`
- Gateway: `mode=local`, `bind=loopback`, `port=18789`
- Workspace: `~/.openclaw-hungreo/workspace`
- Channel plugin(s): `telegram` enabled
- Primary: `openai-codex/gpt-5.4`, Fallback: `anthropic/claude-sonnet-4-6`
- Plugins: lossless-claw, perplexity, telegram-reply-footer

2. Profile: suckhoe

- Config: `~/.openclaw-suckhoe/openclaw.json`
- Gateway: `mode=local`, `bind=loopback`, `port=18795`
- Workspace: `~/.openclaw-suckhoe/workspace`
- Channel plugin(s): `telegram` enabled

## VPS Mapping (Điền và luôn cập nhật)

- Provider: Hostinger VPS
- Hostname: `srv1367812`
- SSH entrypoint: `ssh -i ~/.ssh/hostinger_kvm2 hung@<VPS_IP>`
- Production runtime host(s):
  - `srv1367812`: chạy 2 OpenClaw instance (`hungreo`, `suckhoe`)
- Runtime map (verified):
  - `hungreo` -> config `/home/hung/.openclaw-hungreo/openclaw.json` -> port `18789`
  - `suckhoe` -> config `/home/hung/.openclaw-suckhoe/openclaw.json` -> port `18795`
- Telegram mode: `webhook` (via `bot.hungreo.com`, Caddy auto-TLS)
  - `hungreo` webhook port: `8787`
  - `suckhoe` webhook port: `8788`
- Ghi chú:
  - Lưu hostname/alias/mapping tại đây.
  - Secrets chỉ lưu trong secret manager (không lưu ở file này).

## Lệnh xác minh an toàn (Read-only)

Chạy ở đúng host/profile tương ứng:

```bash
openclaw channels status --probe
ss -ltnp | rg '18789|18795|8787|8788'
```

Tóm tắt config (không in secret):

```bash
jq '{gateway:{mode:.gateway.mode,bind:.gateway.bind,port:.gateway.port},channels:(.channels|keys)}' ~/.openclaw/openclaw.json
jq '{gateway:{mode:.gateway.mode,bind:.gateway.bind,port:.gateway.port},channels:(.channels|keys)}' ~/.openclaw-suckhoe/openclaw.json
```

## Checklist cập nhật

Khi topology thay đổi, cập nhật file này trong cùng change set:

- host alias / vm name
- profile path
- gateway mode/bind/port
- active channels/plugins
- ngày ở `Last updated`
