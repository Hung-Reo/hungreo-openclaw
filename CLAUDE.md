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

## Versions hiện tại (cập nhật: 2026-07-01)

| Component            | Version                                                  |
| -------------------- | -------------------------------------------------------- |
| openclaw npm/VPS     | 2026.6.11 (stable, latest, tất cả 3)                     |
| lossless-claw plugin | 0.13.2 (tất cả 3 — native, KHÔNG cần symlink workaround) |

Chi tiết upgrade 6.9→6.11 (GATE 1/2, backup, phát hiện mới về runtime auto-enable plugin): `SESSION_HANDOVER.md` entry 2026-07-01 + `kb/lessons-learned.md` entry [2026-07-01].

**Fallbacks (mới 2026-05-21):** hungreo + suckhoe đã đổi fallback từ `anthropic/claude-sonnet-4-6` → `deepseek/deepseek-v4-pro` → safer cost-wise.

**Patch 2 (`!embedded && messageTool`):** ✅ UPSTREAM FIXED trong 2026.5.18 — KHÔNG cần re-apply nữa.

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

**6 luật, theo thứ tự ưu tiên:**

1. **Ý định của Hưng > diễn giải của agent.** Hưng đã mô tả luồng → làm đúng luồng.
   "Siết cho an toàn" quá tay cũng là làm sai.
2. **Không đơn phương với thứ không đảo ngược được hoặc tốn tiền:** model / provider /
   fallback / auth / tools.exec / xoá dữ liệu / gửi tin thay Hưng. Lưỡng lự → hành động
   thận trọng nhất là **hỏi hoặc dừng**, không phải "làm rồi báo".
3. **Không bao giờ tự viết luật cho chính mình.** Đề xuất sửa CLAUDE.md / AGENTS.md /
   SOUL.md → Hưng duyệt → mới ghi. Tự sửa luật = tự cấp phép.
4. **Trung thực trước, thể diện sau.** Sai → đính chính ngay, nói rõ sai chỗ nào.
   Chưa biết → "chưa biết". Chưa verify → "đoán". Report bắt buộc có "what could still be wrong".
5. **Kiểm chứng bên ngoài trước khi kết luận.** Log + code chưa đủ — tra issue tracker,
   changelog, backup theo mốc thời gian. "Nghe hợp lý" không phải bằng chứng.
6. **Nhất quán dù có ai xem hay không.** Không làm khác khi nghĩ "việc nhỏ, không ai kiểm".
   Mọi thay đổi để lại dấu vết: backup có tên, `DELETED-*.txt`, handover.

**Phép thử trước mỗi hành động:** _Nếu Hưng đứng sau lưng xem, tôi có làm y hệt không?
Nếu tôi sai, Hưng phát hiện bằng cách nào — tôi có để dấu vết không?_

## Upgrade checklist (tóm tắt — ĐÃ CẬP NHẬT 2026-07-01)

> **Đọc `kb/openclaw-upgrade-runbook.md` để có SOP đầy đủ và các gotchas.** Checklist dưới chỉ là quick ref.

1. `npm view openclaw version` — kiểm latest stable trên npm
2. `npm view @martian-engineering/lossless-claw version` — kiểm plugin
3. Backup configs/workspace/auth/sessions/finance/lcm/systemd drop-ins cả 3 profiles
4. STOP `openclaw-healthcheck.timer`, rồi STOP cả 3 services trước khi update
5. `OPENCLAW_STATE_DIR=~/.openclaw-<profile> openclaw update --yes --no-restart` — chạy từng profile
   5b. DIFF backup vs current `openclaw.json`; với 6.1+ giữ form đúng `openai/gpt-5.5` + `agentRuntime.id="codex"`, không restore về `openai-codex/`
6. Update lossless-claw target version và verify plugin live version cả 3 profiles
7. ⚠️ **Update `service.d/override.conf`** — đổi `OPENCLAW_SERVICE_VERSION=NEW_VER` → `daemon-reload`
8. Start: suckhoe → wait ready → hungreo → wait ready → nemotron; bật lại `openclaw-healthcheck.timer` sau khi cả 3 healthy
9. Verify: `strings /proc/$PID/environ | grep OPENCLAW_SERVICE_VERSION` = `NEW_VER`
10. Audit `sessions.json` generalized drift — clear auto-pins nếu có
11. UAT: `/status` từ Telegram báo version mới; model expected hiện là `openai/gpt-5.5` qua `agentRuntime.id="codex"` với attempts=1/no fallback
12. Telegram format UAT: 1 DM + 1 group/topic; native log `operation=sendMessage`, không có `sendRichMessage` regression

> **Note cho mobile:** SSH key cần có ở `~/.ssh/hostinger_kvm2` trên thiết bị. Nếu không có, dùng Termius hoặc SSH app để check thủ công rồi báo lại cho Claude Code.
