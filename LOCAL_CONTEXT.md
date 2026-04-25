# OpenClaw Local Context (Hungreo)

Last updated: 2026-04-24 11:00 (+07)
Owner: Hung
Policy: File này chỉ lưu topology/context. Không lưu secrets/tokens/private keys/PII.

---

## ⚡ Session Handoff — 2026-04-24 (MỚI NHẤT — ĐỌC PHẦN NÀY TRƯỚC)

### 🚀 Actions session tiếp theo (theo thứ tự)

> **GPT-5.5 sẵn sàng:** Bạn đã plug Plus OAuth. Nhưng phải upgrade .23 TRƯỚC.

#### Step 1 — Upgrade openclaw 2026.4.22 → 2026.4.23 (làm trước)

- npm `latest` = **2026.4.23** (stable, hôm nay)
- **Lý do bắt buộc:** .23 có fix "synthesize gpt-5.5 OAuth catalog row" — thiếu bản này gpt-5.5 vẫn lỗi `Unknown model`
- Command: `openclaw update --yes --no-restart` → restart suckhoe → hungreo
- Sau đó: fix `override.conf` `2026.4.22` → `2026.4.23` → `daemon-reload`
- lossless-claw 0.9.2 = không cần đổi

#### Step 2 — Switch hungreo primary → openai-codex/gpt-5.5 (sau Step 1)

- Config: `~/.openclaw-hungreo/openclaw.json` → `agents.defaults.model.primary`
- Backup trước: `cp openclaw.json openclaw.json.bak-$(date +%Y%m%d-%H%M)-pre-gpt55`
- Verify: `journalctl --user -u openclaw-gateway-hungreo.service -n 50 | grep -E "agent model|warmup|fallback"`
- Expected: `[gateway] agent model: openai-codex/gpt-5.5` — không có fallback line
- suckhoe giữ gpt-5.4

### Versions hiện tại (verified 09:47 +07)

| Component     | Version                  | Ghi chú                             |
| ------------- | ------------------------ | ----------------------------------- |
| openclaw VPS  | **2026.4.22**            | Cần upgrade → 2026.4.23             |
| openclaw npm  | **2026.4.23**            | Latest stable — vừa release hôm nay |
| lossless-claw | **0.9.2**                | 3 locations OK, không cần đổi       |
| hungreo model | **openai-codex/gpt-5.4** | Đổi → gpt-5.5 SAU khi upgrade .23   |
| suckhoe model | **openai-codex/gpt-5.4** | Giữ nguyên                          |

### Services (verified 09:47 +07)

- `openclaw-gateway-hungreo` → active, `OPENCLAW_SERVICE_VERSION=2026.4.22` ✅
- `openclaw-gateway-suckhoe` → active, `OPENCLAW_SERVICE_VERSION=2026.4.22` ✅
- `openclaw-gateway-nemotron` → active, **KHÔNG TOUCH**

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
