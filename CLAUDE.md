# OpenClaw — Hungreo Fork

> **Agent instruction (PRIORITY):** Before any SSH / runtime / VPS / upgrade task, ALWAYS read `LOCAL_CONTEXT.md` first. It contains current VPS state, versions, and runbook.  
> For upstream coding guidelines (contributing to openclaw itself), read `AGENTS.md`.

This is Hưng's personal fork of [openclaw/openclaw](https://github.com/openclaw/openclaw).

## Quick orientation

| File                             | Dùng để                                                               |
| -------------------------------- | --------------------------------------------------------------------- |
| `LOCAL_CONTEXT.md`               | VPS topology, current versions, SSH access, upgrade history, runbook  |
| `kb/openclaw-upgrade-runbook.md` | **SOP upgrade đầy đủ** — step-by-step, mọi agent đều follow được      |
| `kb/lessons-learned.md`          | **Shared lessons** — incidents, root causes, fixes. ADD sau mỗi issue |
| `AGENTS.md`                      | Upstream openclaw coding guidelines (không phải VPS context)          |
| `HUNGREO-GOVERNOR-NOTES.md`      | Product/strategic notes                                               |
| `USER.md`                        | Owner profile                                                         |

## VPS — Quick facts (xem LOCAL_CONTEXT.md để biết thêm)

- **Host:** `hung@<VPS_IP>` | SSH key: `~/.ssh/hostinger_kvm2`
- **SSH command:** `ssh -o ConnectTimeout=10 -i ~/.ssh/hostinger_kvm2 hung@<VPS_IP>`
- **2 bots chính:** `openclaw-gateway-hungreo` + `openclaw-gateway-suckhoe` (systemd --user)
- **Bot thứ 3:** `openclaw-gateway-nemotron` → **KHÔNG TOUCH** trừ khi Hưng yêu cầu rõ ràng
- **Check nhanh:** `systemctl --user is-active openclaw-gateway-hungreo.service openclaw-gateway-suckhoe.service`
- **Log hungreo:** `journalctl --user -u openclaw-gateway-hungreo.service -n 30 --no-pager`
- **Log suckhoe:** `journalctl --user -u openclaw-gateway-suckhoe.service -n 30 --no-pager`

## Versions hiện tại (cập nhật: 2026-04-24)

| Component            | Version                    |
| -------------------- | -------------------------- |
| openclaw npm         | 2026.4.22 (stable, latest) |
| lossless-claw plugin | 0.9.2 (tất cả 3 locations) |

## Upgrade checklist (tóm tắt)

> **Đọc `kb/openclaw-upgrade-runbook.md` để có SOP đầy đủ và các gotchas.** Checklist dưới chỉ là quick ref.

1. `npm view openclaw version` — kiểm latest stable trên npm
2. `npm view @martian-engineering/lossless-claw version` — kiểm plugin
3. Backup configs cả 3 profiles
4. `OPENCLAW_STATE_DIR=~/.openclaw-<profile> openclaw update --yes --no-restart` — chạy từng profile
5. Plugin: force-pin `lossless-claw@0.9.2` cho cả 3 profiles (`--pin --force`)
6. ⚠️ **Update `service.d/override.conf`** — đổi ExecStart về npm-global path + `OPENCLAW_SERVICE_VERSION=NEW_VER` → `daemon-reload`
7. Restart: suckhoe → hungreo → (nemotron nếu được yêu cầu)
8. Verify: `strings /proc/$PID/environ | grep OPENCLAW_SERVICE_VERSION` = `NEW_VER` (không có `+fallback-note`)

> **Note cho mobile:** SSH key cần có ở `~/.ssh/hostinger_kvm2` trên thiết bị. Nếu không có, dùng Termius hoặc SSH app để check thủ công rồi báo lại cho Claude Code.
