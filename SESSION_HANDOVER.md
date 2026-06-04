# Session Handover — OpenClaw VPS Ops

> **Cho session mới:** Đọc file này TRƯỚC, rồi đọc `LOCAL_CONTEXT.md` + `kb/lessons-learned.md` theo chỉ dẫn `CLAUDE.md`.
> Last session: 2026-05-29 | Nguyên tắc: **Simple · Safe · Effective** + workflow **PLAN → DO → CHECK → REVIEW → REPORT**

---

## 0. Cách làm việc Hưng kỳ vọng (QUAN TRỌNG NHẤT)

1. **Research read-only TRƯỚC → present plan → CHỜ Hưng duyệt → mới action.** Không tự ý execute khi chưa OK.
2. **PLAN phải có:** Risk/Edge cases + Cost impact + reference lessons-learned.
3. **CHECK 3 tầng:** gateway log + session state (`sessions.json`) + end-user UX (`/status` Telegram). Không chỉ nhìn 1 tầng.
4. **REPORT phải có "What could still be wrong"** — không tô vẽ "done ✅".
5. **TUYỆT ĐỐI không tự đổi** `agents.defaults.model.*`, `auth.profiles.*`, fallback list — hỏi Hưng trước.
6. Tiếng Việt cho hội thoại. Redact mọi secret/token trong output.
7. Khi user nói mơ hồ (vd "chưa utilize được") → **clarify intent trước**, đừng đoán (đã sai 1 lần: pause nhầm 5 jobs hữu ích).

---

## 1. Current state (verified 2026-06-04)

| Component | hungreo | suckhoe | nemotron |
|---|---|---|---|
| openclaw binary | **2026.6.1** | **2026.6.1** | **2026.6.1** |
| Binary path | `~/.npm-global/lib/...` | `~/.npm-global/lib/...` | `~/.npm-global/lib/...` |
| primary model | **openai/gpt-5.5** (+`models["openai/gpt-5.5"]={agentRuntime:{id:codex}}`) | **openai/gpt-5.5** (+agentRuntime codex) | deepseek/deepseek-v4-pro |
| fallback | deepseek/deepseek-v4-pro | deepseek/deepseek-v4-pro | custom/nvidia/nemotron-3-super-120b-a12b |
| codex auth | `openai:default [openai/oauth]` exp 2026-06-12 | `openai:hungreo2005@gmail.com [openai/oauth]` exp 2026-06-14 (re-auth 2026-06-04) | n/a |
| lossless-claw | 0.11.3 | 0.11.3 | 0.11.3 |
| streaming.mode | off | off | off |
| services | active | active | active |

**npm latest (2026-06-04):** openclaw `2026.6.1` (đang chạy, = latest) · lossless-claw `0.11.3` (= latest)

🔴 **QUAN TRỌNG — 6.1 BỎ provider `openai-codex`.** Form model ĐÚNG từ 6.1 = `primary:"openai/gpt-5.5"` + `models["openai/gpt-5.5"]={agentRuntime:{id:"codex"}}` (route Codex OAuth, $0). **ĐỪNG restore về `openai-codex/`** (rule 5.x cũ — đã đảo ngược). Lesson [2026-06-04].

⚠️ **Root cause stability suckhoe (chưa fix tận gốc):** hungreo + suckhoe **share OAuth account** `hungreo2005@gmail.com`. 6.1 cần auth profile `openai/oauth` (mới); suckhoe lúc upgrade chỉ có `openai-codex/oauth` (cũ) → 401 → deepseek. Đã **re-auth device-code 2026-06-04** (token mới exp 06-14) → suckhoe chạy gpt-5.5 OK. **Fix bền = tách OAuth account riêng** (chưa làm — mục 6).

**SSH:** `ssh -o ConnectTimeout=10 -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33`

---

## 2. ✅ RESOLVED — Nemo maintenance (đã được làm trước session 2026-05-29)

Khi verify đầu session 2026-05-29 phát hiện **Nemo đã được migrate xong** (bởi session/agent trước, sau handover 2026-05-28):

- ✅ `env_VER` label đúng `2026.5.27` (label sai `2026.4.12` đã hết).
- ✅ Nemo dùng `EnvironmentFile=%h/.openclaw-nemotron/credentials/gateway.systemd.env` — **không còn 7 inline secrets** trong systemd unit.
- ✅ `ExecStart` trỏ `~/.npm-global/lib/...` — **không còn `/usr/lib`** (system-wide). Arch đồng nhất với hungreo/suckhoe.
- ✅ Duplicate lossless-claw `extensions/` install: **doctor 5.27 đã tự dọn** (`installs.lossless-claw` block removed khỏi openclaw.json). Giờ chỉ còn 1 copy ở `npm/node_modules`.

→ Toàn bộ Option A/B/C đã được thực hiện. Còn lại chỉ là **rotate 7 Nemo secrets** (Hưng tự làm — xem mục 6).

---

## 3. Hard rules từ các incident (đã trả giá)

1. **Upgrade = STOP services TRƯỚC `npm install`** (anti broken-window → tránh silent fallback đốt tiền). Sự cố 2026-05-08: $3 Anthropic leak.
2. **Sau upgrade: DIFF backup vs current `openclaw.json`** — catch auto-migrate. Bug RECURRING: `openai-codex/` → `openai/` ở 5.12, 5.18, 5.22 (chỉ hungreo bị; nghi do hungreo có nhiều plugin entries openai/codex/anthropic/google).
3. **Sau upgrade/restart: audit `sessions.json` GENERALIZED drift** — bất kỳ DM session nào `modelOverrideSource=auto` với `modelOverride != primary` → clear. (Không hardcode tên model — đã miss deepseek pin vì chỉ check anthropic.)
4. **Verify model "thật"** qua `/status` Telegram, KHÔNG chỉ gateway log. Clue: Context size (1.0M = deepseek, 256K = gpt-5.5).
5. **Sau update override.conf phải `systemctl restart`** (không phải `start`) để load env mới. `openclaw update` đôi khi tự start service với env cũ.
6. **`channels.telegram.streaming.mode = "off"`** mặc định cho user-facing bots (tránh leak "Surfacing..."/"Session Status:" drafts vào DM). Hot-reloadable.
7. Patch 2 (`!embedded && messageTool`) + symlink workaround `@mariozechner→@earendil-works`: **ĐÃ OBSOLETE** từ 5.18 (upstream fixed) + lossless 0.11.1 (native). Không cần re-apply nữa.

**Chi tiết:** `kb/lessons-learned.md` — entries [2026-05-08], [2026-05-15], [2026-05-24], [2026-05-24 đêm].

---

## 4. Jobs / cron state (sau session này)

### ⏸️ PAUSED (cố ý)
- `overnight_research_pipeline.sh` (cron 01:00) — boilerplate failing (Gemini + OpenAI API đều fail, watchlist cạn). Giữ pause.
- `rua_cloud_relay.sh` (cron 04:00) — Hưng yêu cầu stop. Chỉ stop **delivery Telegram**; Anthropic Cloud Routine vẫn generate brief lên repo `Hung-Reo/rua-research-cloud`. Muốn stop hẳn generate → Hưng disable routine trong Anthropic dashboard.
- `hungreo-xfeed.timer` (07:00+19:00) — Hưng yêu cầu stop (X→Telegram scraper không hiệu quả). disabled + stopped. Apify ~$1.08/tháng saved.

### ✅ ACTIVE (đã revert đúng ý Hưng — KHÔNG pause)
`weekly_kickoff.sh`, `weekly_memory_digest.sh`, `night_system_report.sh`, `kb_research_handoff.sh`, `hungreo-vps-ops-report.timer`. **Tất cả KHÔNG dùng Claude tokens** (chỉ openclaw message send / system probe / openai-codex OAuth free).

### Backup locations
- `~/backups/research-jobs-pause-20260525-052851/`
- `~/backups/jobs-revert-and-pause-rua-20260525-054700/`
- `~/backups/xfeed-stop-20260526-080959/`

---

## 5. Đã RESOLVED

### Session 2026-06-04 (mới nhất) — Upgrade 6.1 (Antigravity chạy + Claude review) + sửa breaking codex provider
- ✅ **Upgrade 5.28 → 6.1 cả 3** (Antigravity Opus 4.6 thực thi, Claude Code review độc lập). Backup đầy đủ + state DBs.
- 🔥 **6.1 BỎ provider `openai-codex`** → `openai-codex/gpt-5.5` = "model not found". Form đúng = `openai/gpt-5.5`+`agentRuntime:{id:codex}`. Claude Code **suýt sai** vì áp rule 5.x "restore openai-codex/" → đã đảo ngược + sửa docs/lessons/skill. hungreo + suckhoe đều chuyển sang form mới.
- 🔑 **suckhoe re-auth codex** (Hưng chạy device-code) tạo profile `openai/oauth` (exp 06-14) → restart load auth → UAT winner=openai/gpt-5.5 no-fallback ✅. Clear pin deepseek session Hưng.
- ⚠️ **Antigravity miss:** báo "hungreo không bị migrate" (sai — đã migrate) vì DIFF ở bước 4 trước restart; 6.1 migrate lúc gateway START. SSH review độc lập bắt được. Lesson [2026-06-04].
- Backups: `*-pre-upgrade-2026.6.1`, `*-pre-6.1`, `*-pre-fix-codex-6.1-form`, `sessions.json.bak-*-pre-clear-postauth`.

### Session 2026-06-03
- ✅ **Upgrade 5.27 → 5.28 cả 3 profiles** (stop-first, theo skill `openclaw-ops`). Lý do: cluster Codex auth-recovery + timeout fixes ("warm provider auth off main thread", "honor Codex response timeouts") + cron robustness.
  - **Auto-migrate hungreo `openai-codex/`→`openai/` LẶP LẠI** (giống 5.27) → DIFF bắt → restore + validate pass.
  - 🔥 **nemotron crash startup**: 5.28 bỏ legacy key `agents.defaults.embeddedPi` → `agents.defaults: Invalid input`. Fix: **rename `embeddedPi`→`embeddedAgent`** giữ nguyên `{executionContract:"strict-agentic"}` (guardrail Nemo). Lesson [2026-06-03]. Backup `openclaw.json.bak-20260603-*-pre-fix-embeddedPi`.
  - Verify 3 tầng: env_VER=5.28 cả 3 + 0 errors · 0 drift · UAT `agent model: openai-codex/gpt-5.5` no-fallback, `FINAL_ONLY_OK`.
  - **Backups:** `openclaw.json.bak-20260603-1731-pre-upgrade-2026.5.28` (3 profiles) + `override.conf.bak-20260603-1731-pre-2026.5.28` + nemotron service `.bak`.
- ✅ **Clear drift suckhoe** user `8288766754` (pinned deepseek do timeout storm 02/06) → về primary gpt-5.5. Backup `sessions.json.bak-20260603-*-pre-clear-drift-8288766754`. Vụ timeout chỉ transient 02/06 (18 lần), 03/06 sạch. Session Hưng (`7957776935`) chưa từng dính.

### Session 2026-05-29
- ✅ **Upgrade 5.26 → 5.27 cả 3 profiles** (stop-first, đúng quy trình). lossless giữ 0.11.3 (đã latest).
  - Khi vào session phát hiện binary thật là **5.26** (handover ghi 5.22) → upgrade 5.22→5.26 đã chạy LIVE bởi session trước (log có broken-window `Cannot find module` ở process cũ, transient, không hại lâu dài vì fallback deepseek rẻ + 0 drift).
  - **Auto-migrate hungreo `openai-codex/gpt-5.5` → `openai/gpt-5.5` LẶP LẠI** ở 5.27 (DIFF bắt được). Lần này 5.27 còn **thêm field mới** `agentRuntime:{id:"codex"}` vào model entry. Đã restore về `openai-codex/gpt-5.5` (proven-good, $0 Codex OAuth) + config validate pass.
  - Doctor 5.27 tự dọn duplicate lossless `extensions/` install + sửa `lastTouchedVersion` 2026.4.12→5.27.
  - Verify 3 tầng: env_VER=5.27 cả 3 + 0 errors · 0 session drift · UAT `agent model: openai-codex/gpt-5.5` no-fallback, toolSummary 1/0, payload `FINAL_ONLY_OK`.
  - **Backups:** `openclaw.json.bak-20260529-1436-pre-upgrade-2026.5.27` (3 profiles) + `override.conf.bak-20260529-1436-pre-2026.5.27` (hungreo/suckhoe) + nemotron service `.bak-20260529-1436-pre-2026.5.27` + hungreo `.bak-<ts>-pre-restore-codex-from-527`.

### Session trước (2026-05-28 và sớm hơn)
- ✅ Upgrade 2026.5.22 + lossless 0.11.2 (caught + restored auto-migrate hungreo).
- ✅ suckhoe OAuth `refresh_token_reused` (shared account `hungreo2005@gmail.com` → single-use refresh token bị hungreo invalidate). Fix verified: re-auth device-code (KHÔNG copy token). Lesson [2026-05-24 đêm] đã ghi.
- ✅ Telegram streaming leak → streaming.mode=off cả 3.
- ✅ Lesson `chub`/`get-api-docs` skill = wrong tool cho openclaw VPS ops (khác domain; openclaw context-load đã có qua CLAUDE.md + lessons-learned markdown).

---

## 6. Open follow-ups (chưa làm, low priority)

- **[Hoãn theo ý Hưng 2026-05-29]** Xóa orphan entry `plugins.entries."memory-lancedb"` ở suckhoe (đang `enabled:false`, plugin chưa cài → validate warn). Zero-risk, cần restart suckhoe → gộp vào lần restart sau. Lesson [2026-05-29].
- **[Giữ nguyên theo ý Hưng 2026-05-29]** Gemini API key plaintext trong `memorySearch.remote.apiKey` của hungreo — tradeoff biết trước (lesson [2026-05-17], chuyển key khỏi env để chặn Google web-search routing). Không rotate lúc này.
- Rotate 7 Nemo secrets (sau khi migrate EnvironmentFile — migrate đã xong, chỉ còn rotate).
- Rotate xfeed `APIFY_TOKEN` + `TELEGRAM_BOT_TOKEN` (@hungreo_scrapper_bot) — pending từ 2026-05-02.
- Audit lossless-claw 0.11.3 breaking changes (pull tarball) TRƯỚC nếu chọn Option D.
- ✅ **[DONE 2026-05-29]** Project skill `openclaw-ops` đã build tại `.claude/skills/openclaw-ops/SKILL.md` (gói health-check + drift-detection + upgrade SOP stop-first + hard rules). Gõ `/openclaw-ops`. Auto-load nhờ CC ≥ 2.1.157 (Hưng đang 2.1.150 → cần update CC để load). CHƯA commit.
- Optional còn lại: weekly cron tự chạy audit (DIFF config + sessions drift). Defense-in-depth. Hưng chưa duyệt.
- Optional: ghi note vào `LOCAL_CONTEXT.md` rằng `hungreo-xfeed.timer` + `rua_cloud_relay.sh` đã stopped (để session sau không nhầm đang chạy).

---

## 7. Verify commands cheat-sheet

```bash
# Services + version thật
for s in hungreo suckhoe nemotron; do
  PID=$(systemctl --user show openclaw-gateway-$s.service --property=MainPID --value)
  echo "$s: $(systemctl --user is-active openclaw-gateway-$s.service) env=$(strings /proc/$PID/environ 2>/dev/null | grep ^OPENCLAW_SERVICE_VERSION= | cut -d= -f2)"
done

# DIFF config vs backup (auto-migrate catch)
# So sánh agents.defaults.model.primary + fallbacks + auth.profiles keys

# Sessions drift (generalized)
# DM session nào modelOverrideSource=auto & modelOverride != primary → clear

# npm latest
npm view openclaw version; npm view @martian-engineering/lossless-claw version
```
