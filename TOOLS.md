# TOOLS.md - Local Notes

Skills define _how_ tools work. This file is for setup-specific operational facts.

## OpenClaw Runtime (macOS + Docker)

- Docker binary: `/usr/local/bin/docker`
- Main gateway container: `hungreo-openclaw-openclaw-gateway-1`
- Suckhoe gateway container: `openclaw-suckhoe-openclaw-gateway-1`
- Image tag in use: `openclaw:local`

## Auto-Restart Job (stability before morning brief)

- Script: `/Users/hungdinh/bin/openclaw-restart-gateways.sh`
- LaunchAgent: `/Users/hungdinh/Library/LaunchAgents/com.hungreo.openclaw.restart-gateways.plist`
- Schedule: every day `06:35` local time (Asia/Ho_Chi_Minh)
- Logs:
  - stdout: `/tmp/openclaw-restart-gateways.out.log`
  - stderr: `/tmp/openclaw-restart-gateways.err.log`

## Quick Verify Commands

```bash
which docker
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "openclaw|suckhoe"
launchctl print gui/$(id -u)/com.hungreo.openclaw.restart-gateways
tail -n 30 /tmp/openclaw-restart-gateways.out.log
tail -n 30 /tmp/openclaw-restart-gateways.err.log
```

## Guardrails

- Do not modify firewall/SSH/billing settings during routine maintenance.
- For risky changes: make a baseline snapshot first, then change, then verify.
- Always provide rollback commands when touching runtime behavior.
- Keep `OPENCLAW_GATEWAY_TOKEN` present in both `.env` and `.env.suckhoe`.
