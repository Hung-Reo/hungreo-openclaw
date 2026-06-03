---
name: openclaw-ops
version: 0.1.0
description: |
  OpenClaw VPS ops cho fork Hungreo — upgrade, audit, drift-check, health-check cho 3 bot
  (hungreo, suckhoe, nemotron) trên Hostinger VPS. Áp dụng workflow stop-first + verify 3 tầng +
  cost-safety hard rules đã trả giá qua nhiều incident. Dùng khi user nói tới: "upgrade openclaw",
  "audit bot", "check VPS", "drift", "sessions auto-pin", "model fallback", "restart gateway",
  "openclaw health", hoặc bất kỳ task runtime/deployment nào trên VPS openclaw.
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
---

# /openclaw-ops — OpenClaw VPS Ops (Hungreo fork)

Skill này gói SOP vận hành 3 bot OpenClaw để **không re-derive context mỗi session**.
Nguyên tắc: **Simple · Safe · Effective** + **PLAN → DO → CHECK → REVIEW → REPORT**.

## 0. BẮT BUỘC đọc trước khi action (thứ tự)

1. `SESSION_HANDOVER.md` — state mới nhất + follow-ups đang treo
2. `LOCAL_CONTEXT.md` — topology, ports, paths, SSH
3. `kb/lessons-learned.md` — incidents đã trả giá (grep pattern liên quan task)
4. `kb/openclaw-upgrade-runbook.md` — SOP upgrade đầy đủ

**Research read-only TRƯỚC → present plan → CHỜ Hưng duyệt → mới action.** Không tự execute khi chưa OK.

## 1. Hard rules cost-safety (TUYỆT ĐỐI)

- **KHÔNG tự đổi** `agents.defaults.model.*`, `auth.profiles.*`, fallback list → hỏi Hưng trước.
- **Upgrade = STOP services TRƯỚC `npm install`** (anti broken-window → silent fallback đốt tiền). Incident 2026-05-08: $3 Anthropic leak khi update lúc service LIVE.
- **Sau MỌI upgrade: DIFF backup vs current `openclaw.json`** — bắt auto-migrate `openai-codex/`→`openai/` (RECURRING ở 5.12/5.18/5.22/5.27, chỉ hungreo). Restore về `openai-codex/gpt-5.5` nếu bị.
- **Sau MỌI upgrade/restart: audit `sessions.json` GENERALIZED drift** — bất kỳ DM session nào `modelOverrideSource=auto` với `modelOverride != primary` → clear (KHÔNG hardcode tên model).
- **Verify model THẬT** qua `/status` Telegram hoặc gateway log `agent model:`, KHÔNG chỉ nhìn config.
- **`channels.telegram.streaming.mode = "off"`** mặc định cho bot user-facing.
- Redact mọi secret/token trong output. Tiếng Việt cho hội thoại.

## 2. SSH

```bash
ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33
```
CLI gateway probe phải set CẢ `OPENCLAW_STATE_DIR=~/.openclaw-<profile>` + `--profile <profile>` (token/port per-profile — lesson 2026-05-29). Binary: `~/.npm-global/bin/openclaw`.

## 3. Health-check nhanh (read-only, safe — chạy đầu mỗi session)

```bash
# Services + version THẬT (qua /proc, không tin --version)
for s in hungreo suckhoe nemotron; do
  PID=$(systemctl --user show openclaw-gateway-$s.service --property=MainPID --value)
  echo "$s: $(systemctl --user is-active openclaw-gateway-$s.service) env_VER=$(strings /proc/$PID/environ 2>/dev/null | grep ^OPENCLAW_SERVICE_VERSION= | cut -d= -f2)"
done
# Config: primary + fallback + streaming (3 profiles)
for p in hungreo suckhoe nemotron; do jq -c "{p:\"$p\",primary:.agents.defaults.model.primary,fb:.agents.defaults.model.fallbacks,stream:.channels.telegram.streaming.mode}" ~/.openclaw-$p/openclaw.json; done
# npm latest
npm view openclaw version; npm view @martian-engineering/lossless-claw version
```

## 4. Sessions drift detection (generalized — chạy sau mọi restart)

```bash
for p in hungreo suckhoe nemotron; do
  F=~/.openclaw-$p/agents/main/sessions/sessions.json; [ -f "$F" ] || continue
  PRIM=$(jq -r .agents.defaults.model.primary ~/.openclaw-$p/openclaw.json | cut -d/ -f2-)
  D=$(jq -r --arg prim "$PRIM" 'to_entries[]|select(.key|startswith("agent:main:telegram:direct:"))|select(.value.modelOverrideSource=="auto" and .value.modelOverride!=null and (.value.modelOverride|split("/")|last)!=$prim)|"  DRIFT \(.key) -> \(.value.modelOverride)"' "$F")
  [ -z "$D" ] && echo "$p: ✅ no drift (primary=$PRIM)" || echo "$p: ⚠️$D"
done
```
Nếu có drift → stop service → backup sessions.json → xóa các field override của session đó → start → verify.

## 5. Upgrade SOP (stop-first) — tóm tắt

> Đầy đủ: `kb/openclaw-upgrade-runbook.md`. Phải có PLAN với Risk + Cost trước.

1. **Backup**: `openclaw.json` ×3 (suffix `pre-upgrade-<VER>`) + `override.conf` hungreo/suckhoe + nemotron `.service` file.
2. **STOP cả 3**: `systemctl --user stop openclaw-gateway-{hungreo,suckhoe,nemotron}.service` → confirm không còn gateway process.
3. **Update từng profile**: `OPENCLAW_STATE_DIR=~/.openclaw-<p> ~/.npm-global/bin/openclaw update --yes --no-restart` (chạy `openclaw doctor` tự động — đây là chỗ auto-migrate).
4. **DIFF config** vs backup: verify `model.primary` không bị migrate. Restore `openai-codex/gpt-5.5` nếu lệch → `openclaw --profile <p> config validate`.
5. **Verify** lossless-claw version + `@earendil-works` deps (0.11.x native, không cần symlink `@mariozechner` nữa).
6. **Bump version** trong `override.conf`/service file (`sed 's/<OLD>/<NEW>/g'`) → `systemctl --user daemon-reload`.
7. **Restart** (KHÔNG `start`) theo thứ tự suckhoe → hungreo → nemotron, chờ `http server listening` từng cái.
8. **CHECK 3 tầng**:
   - (a) Gateway log: plugins đủ (`lossless-claw` có mặt) + `env_VER` đúng + 0 `Cannot find module`.
   - (b) `sessions.json` drift = 0 (mục 4).
   - (c) UAT: `OPENCLAW_STATE_DIR=~/.openclaw-hungreo openclaw --profile hungreo agent --json --timeout 180 --session-id uat-<VER> --message "Use exec to run: printf tool-ok. Then reply exactly FINAL_ONLY_OK."` → expect gateway log `agent model: openai-codex/gpt-5.5`, toolSummary 1/0, payload `FINAL_ONLY_OK`.
9. **REPORT** + update `SESSION_HANDOVER.md` + `kb/lessons-learned.md`. Phải có section **"What could still be wrong"** — không tô vẽ. Liệt kê backup + rollback path.

## 6. Patches / gotchas hiện tại (cập nhật khi đổi)

- Patch 1 + Patch 2 (`!embedded && messageTool`) + symlink `@mariozechner→@earendil-works`: **OBSOLETE** từ 5.18 + lossless 0.11.1. Không re-apply.
- Auto-migrate `openai-codex/`→`openai/`: **vẫn recurring tới 5.28** (5.27 thêm shape `agentRuntime:{id:codex}`). DIFF bắt buộc mỗi upgrade.
- **Breaking schema (5.28):** bỏ legacy `agents.defaults.embeddedPi` → đổi tên `embeddedAgent`. nemotron crash startup `agents.defaults: Invalid input`. Nếu profile nào `failed` sau restart với lỗi này → **so keys `agents.defaults` giữa 3 profiles** tìm key legacy → rename giữ value (KHÔNG `doctor --fix` mù). Lesson [2026-06-03].
- **Root cause stability suckhoe:** hungreo+suckhoe share 1 OAuth account → Codex token contention → fallback. Fix bền = tách account riêng (chưa làm).
- `nemotron` đã migrate `EnvironmentFile` + `~/.npm-global` (không còn `/usr/lib`, không còn inline secrets) từ ~2026-05-29.

## 7. Nhắc cuối

Verify bằng grep/read, KHÔNG bằng "trust". "Done" phải kèm bằng chứng file/line + "what could still be wrong". Mỗi incident mới → ADD entry vào `kb/lessons-learned.md`.
