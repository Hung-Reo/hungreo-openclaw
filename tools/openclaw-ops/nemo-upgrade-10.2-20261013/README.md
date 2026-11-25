# Nemo Canary Upgrade 2026.10.1 → 2026.10.2 (2026-10-13)

- **Target**: Nemo sandbox container (`nemo-sandbox`), port 18796 (loopback), 8789 (Telegram webhook via Caddy).
- **Host**: Hostinger VPS (`srv1367812`, 72.61.123.33).
- **Baseline**: OpenClaw 2026.10.1, node:24.21.0-bookworm-slim.
- **Upgraded**: OpenClaw **2026.10.2 (`b8952d4`)**, runtime mount `/home/hung/sandbox-nemo/runtime-10.2`.
- **Plugin codex**: Cập nhật từ `2026.10.1` lên `2026.10.2`.
- **Model config**: Giữ nguyên 100% (Primary: `openrouter/meta/muse-spark-1.3-contributor`, Fallback: `openai/gpt-6.1-sol` via codex OAuth).
- **Backup**: `/home/hung/backups/nemo-upgrade-10.2-20261013-113641` (594M tar config + workspace, sha256 verified).
- **Rollback container**: `nemo-sandbox-10.1` (Exited 0) + runtime `/home/hung/sandbox-nemo/runtime-10.1`.
- **Rollback command**: `ssh -i ~/.ssh/hostinger_kvm2 hung@72.61.123.33 'bash -s -- /home/hung/backups/nemo-upgrade-10.2-20261013-113641' < 99_rollback.sh`.

## Verification / UAT (2026-10-13 11:41 VNT)

1. Readyz: HTTP 200 (~55s).
2. Gateway probe: Reachable.
3. UAT 1 (Default Muse model): `UAT_DEFAULT_OK openrouter/meta/muse-spark-1.3-contributor`, status 200.
4. UAT 2 (Forced Sol 6.1 fallback): `UAT_SOL61_OK`, winnerModel `gpt-6.1-sol`, status ok.
5. Production instances `hungreo` (PID 3242117) và `suckhoe` (PID 3456950) giữ nguyên an toàn tuyệt đối, NRestarts=0.
