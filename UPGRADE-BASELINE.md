# UPGRADE-BASELINE (2026-02-11)

Timestamp: `2026-02-11 14:40:20 +0700`

## Goal

Upgrade OpenClaw runtime for bot "Rùa" safely while preserving local WIP in this repository.

## Repository State

- Workspace root: `/Users/hungdinh/Development/hungreo-openclaw`
- Branch: `main` (tracking `hungreo/main`)
- HEAD: `dbaba47c7`
- `origin/main`: `841dbeee0` (latest tag: `v2026.2.9`)
- `hungreo/main`: `6261c790d`
- Divergence:
  - HEAD vs `origin/main`: ahead `3`, behind `354`
  - HEAD vs `hungreo/main`: ahead `1`, behind `0`
- Working tree: dirty (many uncommitted changes)

## Runtime/Tooling Baseline

- Local OpenClaw CLI (repo): `2026.2.4` (requires Node `>=22.12.0`)
- Node used for OpenClaw commands: `v22.16.0`
- Docker binary: `/usr/local/bin/docker`
- Active gateway containers:
  - `hungreo-openclaw-openclaw-gateway-1`
  - `openclaw-suckhoe-openclaw-gateway-1`
- Runtime version inside both containers: `2026.1.30`
- Current container image tag: `openclaw:local`
- Current image digest (both containers):
  - `sha256:867baf0be96d051d3f9c70d82f044c2a936e3a832cb80e0b1f0eaf2177987481`

## Stability Guardrails (already in place)

- Restart script: `/Users/hungdinh/bin/openclaw-restart-gateways.sh`
- LaunchAgent: `/Users/hungdinh/Library/LaunchAgents/com.hungreo.openclaw.restart-gateways.plist`
- Schedule: daily `06:35` (local time)
- Restart logs:
  - `/tmp/openclaw-restart-gateways.out.log`
  - `/tmp/openclaw-restart-gateways.err.log`
- LaunchAgent loaded in GUI domain:
  - `launchctl print gui/501/com.hungreo.openclaw.restart-gateways` => present

## Exec Approvals Baseline (allowlist patterns)

- Agent `hungreo-openclaw`:
  - `/usr/local/bin/docker`
  - `/bin/launchctl`
  - `/Users/hungdinh/bin/openclaw-restart-gateways.sh`
  - `/usr/bin/curl`
  - `/home/node/.openclaw/workspace/scripts/openclaw-docker-api.sh`

## Risk Summary

Direct `git pull/rebase` upgrade inside this repo is high risk due large upstream drift + dirty worktree.
Safer runtime upgrade path: build `openclaw:local` from clean upstream tag and restart containers.

## Upgrade Execution Result (completed)

- Source for build: clean clone of `openclaw` tag `v2026.2.9` in `/tmp/openclaw-upgrade-v2026.2.9`
- Built image tag: `openclaw:local`
- New image digest in running containers:
  - `sha256:17b0be1e43702b6fd83c9af9455b2f19274150aa0ad1aa02c9955596e32b544c`
- Runtime version after upgrade:
  - `hungreo-openclaw-openclaw-gateway-1` => `2026.2.9`
  - `openclaw-suckhoe-openclaw-gateway-1` => `2026.2.9`
- Token check (redacted, length only):
  - `hungreo-openclaw-openclaw-gateway-1` token length: `64`
  - `openclaw-suckhoe-openclaw-gateway-1` token length: `64`
- Post-upgrade restart script test: pass (containers restarted successfully).

## Notable Adjustment During Upgrade

- `.env.suckhoe` was missing `OPENCLAW_GATEWAY_TOKEN`.
- Added `OPENCLAW_GATEWAY_TOKEN` to `.env.suckhoe` using the existing token from `.env` (value not exposed).
