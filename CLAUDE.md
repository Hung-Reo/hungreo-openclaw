# OpenClaw — Hungreo Fork

> **Agent instruction (PRIORITY):** Before any SSH / runtime / VPS / upgrade task, ALWAYS read `LOCAL_CONTEXT.md` first. It contains current VPS state, versions, and runbook.  
> For upstream coding guidelines (contributing to openclaw itself), read `AGENTS.md`.

This is Hưng's personal fork of [openclaw/openclaw](https://github.com/openclaw/openclaw).

## Quick orientation

| File                        | Dùng để                                                              |
| --------------------------- | -------------------------------------------------------------------- |
| `LOCAL_CONTEXT.md`          | VPS topology, current versions, SSH access, upgrade history, runbook |
| `AGENTS.md`                 | Upstream openclaw coding guidelines (không phải VPS context)         |
| `HUNGREO-GOVERNOR-NOTES.md` | Product/strategic notes                                              |
| `USER.md`                   | Owner profile                                                        |

## VPS — Quick facts (xem LOCAL_CONTEXT.md để biết thêm)

- **Host:** `hung@<VPS_IP>` | SSH key: `~/.ssh/hostinger_kvm2`
- **SSH command:** `ssh -o ConnectTimeout=10 -i ~/.ssh/hostinger_kvm2 hung@<VPS_IP>`
- **2 bots chính:** `openclaw-gateway-hungreo` + `openclaw-gateway-suckhoe` (systemd --user)
- **Bot thứ 3:** `openclaw-gateway-nemotron` → **KHÔNG TOUCH** trừ khi Hưng yêu cầu rõ ràng
- **Check nhanh:** `systemctl --user is-active openclaw-gateway-hungreo.service openclaw-gateway-suckhoe.service`
- **Log hungreo:** `journalctl --user -u openclaw-gateway-hungreo.service -n 30 --no-pager`
- **Log suckhoe:** `journalctl --user -u openclaw-gateway-suckhoe.service -n 30 --no-pager`

## Versions hiện tại (cập nhật: 2026-04-22)

| Component            | Version                    |
| -------------------- | -------------------------- |
| openclaw npm         | 2026.4.20 (stable, latest) |
| lossless-claw plugin | 0.9.2 (tất cả 3 locations) |

## Upgrade checklist (tóm tắt)

1. `npm view openclaw version` — kiểm latest stable trên npm
2. `npm view @martian-engineering/lossless-claw version` — kiểm plugin
3. Backup: `cp openclaw.json openclaw.json.bak-$(date +%Y%m%d-%H%M)-pre-upgrade`
4. `openclaw update --yes --no-restart` → upgrade openclaw
5. Plugin (nếu cần): `OPENCLAW_STATE_DIR=~/.openclaw-<profile> openclaw --profile <p> plugins install @martian-engineering/lossless-claw@X.Y.Z --pin --force` — chạy cho **cả 3**: hungreo, suckhoe, shared
6. Restart: suckhoe trước → hungreo sau → **bỏ qua nemotron**
7. Verify: `journalctl --user -u openclaw-gateway-hungreo.service -n 60 --no-pager | grep "ready"`

> **Note cho mobile:** SSH key cần có ở `~/.ssh/hostinger_kvm2` trên thiết bị. Nếu không có, dùng Termius hoặc SSH app để check thủ công rồi báo lại cho Claude Code.
