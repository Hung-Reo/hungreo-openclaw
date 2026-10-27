# Nemo 10.3 + LCM 1.1.1 — deployed 2026-10-14

**Result: VERIFIED deployed.** Nemo `nemo-sandbox` runs OpenClaw **2026.10.3** (`59cb447`) and **lossless-claw 1.1.1**, contextEngine selected and conversation hook granted. Final container started **14/10 21:26:13 VNT**. Hungreo/Suckhoe retain PIDs **3242117/3456950**, active and NRestarts=0.

## Authorization and scope

Hưng explicitly requested upgrading Nemo to 10.3 and installing LCM for further testing. Only Nemo was changed: separately staged runtime, Codex plugin 10.3, pinned LCM 1.1.1, LCM slot/hook, and a small new workspace TOOLS.md explaining deferred LCM tool discovery. Model/auth configuration, env file, Docker user, loopback published ports, CPU, RAM/swap limits, other plugins, and other profiles were preserved. No repository commit/push or unrelated cleanup/upgrade.

## Verified behavior

- Core/package integrity/lifecycle stage PASS; actual CLI flags/schema were inspected before applying. LCM package peer requirement accepts core >=2026.9.2.
- Transport-disabled isolated clone: LCM installed/registered, real Muse model-backed compaction created one summary, isolated gateway restart preserved recall. Actual `tool_call` id `openclaw:lossless-claw:lcm_grep` and a tool result containing the synthetic marker verified retrieval. Isolated Telegram token blank, no host ports, cron disabled only in the clone.
- Serving Nemo: `readyz` 200; Telegram channel probe reachable/enabled/running/works; actual package and SQLite installed index both confirm LCM 1.1.1 and Codex 2026.10.3. Startup contains LCM registration, with no ERROR-level match in the sampled startup log.
- Fresh no-deliver gateway turns: Muse marker PASS **5737ms**, Sol 6.1 marker PASS **8588ms**. Execution traces each report one successful attempt, correct winner and no fallback. These test separate routes, not automatic failover.
- Live LCM: stores synthetic messages, SQLite quick_check=ok, real grep dispatch and matching tool result PASS. First direct request named the tool but the model claimed it was absent; explicit deferred-tool discovery passed. A short TOOLS.md then taught discovery before declaring absence; a subsequent ordinary `lcm_grep` request also produced a real dispatch/result. No persona/model change. Readback found two grep dispatches and two matching tool results.
- Resource/environment/config invariants PASS; unaffected systemd service readback exactly matches baseline. Serving cap remains 1 CPU / **2.5 GiB**, total memory+swap **4.5 GiB**, ports only 127.0.0.1:18796/8789.
- Snapshot **21:34:35 VNT**: Docker RAM **1.583/2.5 GiB**, CPU 2.80%; RestartCount=0, OOMKilled=false; VPS available RAM 2124MiB, swap used 1684/2047MiB. Two RSS-threshold warnings remain in the new container log. This is an early snapshot, not a memory-leak or performance conclusion.

## Incidents and recovery

- SSH initially failed in BatchMode: server accepted the public key, but the encrypted private key was not unlocked in ssh-agent. The operator unlocked it locally. No key/passphrase was displayed or placed in chat; no server access/auth changes.
- First cutover incorrectly triggered ERR rollback on Doctor's warning-only exit 1 despite `set +e`. The tested rollback restored config/workspace + serving 10.2 and passed readiness. The script was corrected to call Doctor in an `if` condition, parse findings and reject actual errors; a regression proved exit 1 did not trigger ERR. Retry used a fresh backup, preserving all older artifacts.
- Doctor reports **0 errors / 2 warnings** for existing plaintext gateway-auth configuration and container-internal LAN binding. The serving host port exposure remains loopback as before. No blanket Doctor --fix or credential migration was run.

## Backup and rollback

Final pre-cutover backup (both tar archives SHA256 PASS):

`/home/hung/backups/nemo-10.3-lcm-20261014-212310`

Preserved previous backup: `/home/hung/backups/nemo-10.3-lcm-20261014-211052`.

Rollback container: **nemo-sandbox-10.2**, stopped, restart=no; its runtime **runtime-10.2** remains intact. Earlier 10.1/9.8 rollback containers also remain. Failed candidate config/workspace from the first attempt were retained privately on the VPS. The isolated rehearsal container is stopped.

The target-specific `99_rollback.sh` verifies backup hashes, retains failed state, restores both config and workspace (including DB schema/state), then returns the 10.2 container and verifies readiness. It is available on the VPS at `/home/hung/sandbox-nemo/ops-10.3-lcm-20261014/99_rollback.sh`. Rolling back later loses live changes after the snapshot from the active view; failed/current state is retained for reconciliation. Future rollback remains an operator decision, not automatic canary monitoring.

## Trial limits and next

Owner Telegram UAT and **48–72h soak are pending**. New checkpoints: **16/10 21:26** and **17/10 21:26** from the final cutover. No automation was created. Native `/lossless` is available for the owner to inspect LCM; continue ordinary chat and observe recall. Live default freshTail/compaction thresholds were kept; low freshTail/fanout used to force the isolated test did not reach serving config. No bulk historical import was performed.

Nemo now tests core + LCM together, but its Muse summarization route is not complete proof for production Sol 6.1 summarization, every grant/expansion path, custom plugins or cron workloads. No guaranteed token savings or fix for every RSS warning is claimed.

Raw backups/DB/env/agent receipts stay private on the VPS. Local `verified-summary.json` contains only sanitized status/model/count/resource metadata. Shell syntax and scoped diff whitespace checks passed.

Sources: https://docs.openclaw.ai/releases/2026.10.3 ; https://github.com/Martian-Engineering/lossless-claw/blob/v1.1.1/README.md ; https://github.com/Martian-Engineering/lossless-claw/releases/tag/v1.1.1 ; https://docs.openclaw.ai/cli/sessions
