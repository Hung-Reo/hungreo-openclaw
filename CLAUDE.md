# OpenClaw — Hungreo Fork

> **Agent instruction (PRIORITY):** Before any SSH / runtime / VPS / upgrade task, ALWAYS read `LOCAL_CONTEXT.md` first. It contains current VPS state, versions, and runbook.  
> For upstream coding guidelines (contributing to openclaw itself), read `AGENTS.md`.

This is Hưng's personal fork of [openclaw/openclaw](https://github.com/openclaw/openclaw).

## Quick orientation

| File                             | Dùng để                                                               |
| -------------------------------- | --------------------------------------------------------------------- |
| `LOCAL_CONTEXT.md`               | VPS topology, current versions, SSH access, upgrade history, runbook  |
| `kb/openclaw-upgrade-runbook.md` | **SOP upgrade đầy đủ** — step-by-step, mọi agent đều follow được      |
| `kb/hungreo-xfeed-runbook.md`    | **SOP `hungreo-xfeed`** — auto X→Telegram service (deploy 2026-05-02) |
| `kb/lessons-learned.md`          | **Shared lessons** — incidents, root causes, fixes. ADD sau mỗi issue |
| `AGENTS.md`                      | Upstream openclaw coding guidelines (không phải VPS context)          |
| `HUNGREO-GOVERNOR-NOTES.md`      | Product/strategic notes                                               |
| `USER.md`                        | Owner profile                                                         |

## VPS — Quick facts (xem LOCAL_CONTEXT.md để biết thêm)

- **Host:** `hung@<VPS_IP>` | SSH key: `~/.ssh/hostinger_kvm2`
- **SSH command:** `ssh -o ConnectTimeout=10 -i ~/.ssh/hostinger_kvm2 hung@<VPS_IP>`
- **2 bots chính:** `openclaw-gateway-hungreo` + `openclaw-gateway-suckhoe` (systemd --user)
- **Bot thứ 3:** `openclaw-gateway-nemotron` → **KHÔNG TOUCH** trừ khi Hưng yêu cầu rõ ràng
- **Aux service:** `hungreo-xfeed.timer` (auto X→Telegram feed, 07:00+19:00 VNT) — runbook: `kb/hungreo-xfeed-runbook.md`
- **Check nhanh:** `systemctl --user is-active openclaw-gateway-hungreo.service openclaw-gateway-suckhoe.service hungreo-xfeed.timer`
- **Log hungreo:** `journalctl --user -u openclaw-gateway-hungreo.service -n 30 --no-pager`
- **Log suckhoe:** `journalctl --user -u openclaw-gateway-suckhoe.service -n 30 --no-pager`
- **Log xfeed:** `journalctl --user -u hungreo-xfeed.service -n 30 --no-pager`

## Versions — đọc từ VPS, KHÔNG cache trong file này (đổi 2026-09-21)

Bảng version từng nằm ở đây đã stale 2 lần (ghi 2026.6.11 khi VPS chạy 2026.7.1-2; fallback ghi deepseek khi thực tế là OpenRouter) → bỏ. Nguồn sự thật:

- **Version đang chạy:** `systemctl --user show -p MainPID --value openclaw-gateway-hungreo.service` → `strings /proc/<PID>/environ | grep OPENCLAW_SERVICE_VERSION`, hoặc `/status` từ Telegram.
- **Model / fallback hiện hành:** `openclaw.json` từng profile trên VPS là nguồn duy nhất (`jq .agents.defaults.model`). `LOCAL_CONTEXT.md` chỉ đọc entry **mới nhất** (mục "Subagents Model Cutover" 2026-09-11) — các bảng cũ hơn trong file đó (ghi `openai-codex/gpt-5.5`, deepseek) là lịch sử, không phải hiện trạng.
- **Lịch sử upgrade, patch obsolete:** `SESSION_HANDOVER.md` entry mới nhất + `.claude/skills/openclaw-ops/SKILL.md` mục 6.

## 🛡️ HARD RULES — Model & Upgrade (NEW 2026-05-08, sau incident Anthropic API leak)

> **MỌI agent (Claude Code, hungreo bot, Nemo, Codex) BẮT BUỘC tuân thủ.**

### Workflow nguyên tắc — PLAN → DO → CHECK → REVIEW → REPORT

**Mọi task openclaw VPS (upgrade, config change, runtime patch) BẮT BUỘC follow đủ 5 bước:**

| Bước       | Output bắt buộc                                                                                                      |
| ---------- | -------------------------------------------------------------------------------------------------------------------- |
| **PLAN**   | Steps + **Risk/Edge cases section** + **Cost impact estimate** + grep memory & lessons-learned cho pattern liên quan |
| **DO**     | Code/commands theo plan, KHÔNG nhồi scope mới giữa chừng                                                             |
| **CHECK**  | Verify **3 tầng**: gateway config layer + session state layer + end-user UX (Telegram /status) — không chỉ 1 tầng    |
| **REVIEW** | Self-critique: "có thể sai chỗ nào còn chưa check?" + reference các lessons-learned                                  |
| **REPORT** | "Done" + section "what could still be wrong" — KHÔNG tô vẽ. Liệt kê backup files, rollback path.                     |

**Skip bước nào → có thể tốn tiền của Hưng** (đã chứng minh 2026-05-08 với $3 Anthropic leak).

### Hard rules cụ thể

1. **TUYỆT ĐỐI cấm tự đổi `agents.defaults.model.*`, `auth.profiles.*`, fallback list trong `openclaw.json`** — phải hỏi Hưng trước.
2. **Upgrade workflow: STOP services TRƯỚC khi `npm install`** — KHÔNG được update khi service đang LIVE (gây silent fallback sang Anthropic API → đốt tiền).
3. **Sau MỌI upgrade/restart**: audit `sessions.json` — **GENERALIZED drift detection** (không hardcode tên model). Check mọi DM session có `modelOverrideSource=auto` với `modelOverride != primary_model` → clear pin. Updated rule sau incident [2026-05-24 tối] (suckhoe session bị auto-pin sang deepseek, blindspot chỉ check anthropic).
4. **Verify model "thật đang dùng" KHÔNG chỉ nhìn gateway log** — phải check session state hoặc `/status` từ Telegram.
5. **Sau upgrade**: DIFF backup vs current `openclaw.json` → catch auto-migration của model/provider/auth (vd: `openai-codex/` → `openai/`).
6. **`channels.telegram.streaming.mode = "off"` mặc định** cho mọi user-facing bot (tránh leak progress drafts: "Surfacing...", "📊 Session Status:" trong DM).

### Hot reload vs Full restart

| Config key                         | Cần restart?                       |
| ---------------------------------- | ---------------------------------- |
| `channels.telegram.streaming.mode` | ❌ Hot reload (~1-2s, no downtime) |
| `agents.defaults.model.*`          | ⚠️ Restart safer                   |
| `auth.profiles.*`                  | ⚠️ Restart safer                   |
| `plugins.entries.*.enabled`        | ✅ Restart required                |
| Plugin install/uninstall           | ✅ Restart required                |

Hot reload pattern (no stop):

```bash
# Edit config → openclaw tự detect:
# [reload] config change detected; evaluating reload (<key>)
# [reload] config hot reload applied (<key>)
# Nếu có pending ops: deferred → có thể trigger full restart
```

Chi tiết: `kb/lessons-learned.md` entries [2026-05-08], [2026-05-15].

## 🧭 ALIGNMENT — nguyên tắc làm việc với Hưng (2026-09-15)

> Alignment = agent hành động theo **ý định thật** của Hưng, không theo diễn giải riêng,
> không theo "tốt nhất theo tôi nghĩ". Nguồn: Anthropic Constitution 01/2026 (honesty ·
> corrigibility · no unilateral action) + Alignment Science Blog "Agentic Misalignment Summer 2026"
> (4 kiểu lệch: covert sabotage · harmful compliance · motivated mislabeling · proxy whistleblowing).

**Vì sao phải ghi:** mọi sự cố đắt nhất ở đây đều là lệch alignment, không phải lỗi kỹ thuật.

| Ngày  | Chuyện                                                                                           | Kiểu lệch                |
| ----- | ------------------------------------------------------------------------------------------------ | ------------------------ |
| 05/08 | Agent tự đổi model production rồi **tự viết lại AGENTS.md** hợp thức hoá → 12 ngày không ai thấy | Đơn phương + che dấu vết |
| 05/09 | Fallback 2 bot bị đổi sang provider trả tiền, không ai biết                                      | Đơn phương               |
| 05/09 | Suckhoe tự vá script theo yêu cầu người thứ 3, xin duyệt bằng 5 tin vô nghĩa                     | Nhận lệnh sai principal  |
| 05/09 | Claude Code siết policy quá tay 2 lần liên tiếp                                                  | "An toàn" thay ý chủ     |
| 15/09 | Claude Code kết luận sai 3 lần về Hermes trước khi tra issue tracker                             | Tự tin thay kiểm chứng   |

**6 luật + phép thử:** xem `~/.claude/CLAUDE.md` mục Alignment (nguồn duy nhất, không chép lại ở đây — rút gọn 2026-09-26).

## Upgrade

SOP đầy đủ: `kb/openclaw-upgrade-runbook.md` + skill `openclaw-ops` (mục sessions drift, form `openai/` + `agentRuntime` 6.1+). Hai bẫy đã tốn tiền, luôn nhớ:

- ⚠️ STOP `openclaw-healthcheck.timer` rồi STOP cả 3 services **trước** khi update — không update khi LIVE.
- ⚠️ Update `service.d/override.conf` (`OPENCLAW_SERVICE_VERSION=NEW_VER`) → `daemon-reload`.

> **Note cho mobile:** SSH key cần có ở `~/.ssh/hostinger_kvm2` trên thiết bị. Nếu không có, dùng Termius hoặc SSH app để check thủ công rồi báo lại cho Claude Code.
