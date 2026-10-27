# Nemo: OpenClaw 2026.10.3 + lossless-claw 1.1.1

Status: COMPLETE — Nemo cutover to OpenClaw 2026.10.3 + lossless-claw 1.1.1 at 14/10 21:26:13 VNT. Live Muse, Sol 6.1 and LCM grep gates passed; isolated model-backed compaction/restart/recall passed. Operator Telegram UAT and 48–72h soak remain. See REPORT.md and verified-summary.json.

## Authorization and baseline

- User: “lên 10.3 và cài lcm cho Nemo luôn … thử nghiệm tiếp”. This supersedes the earlier recommendation to wait for the 10.2 canary; it does not authorize upgrading the other profiles.
- Intended target: VPS srv1367812, Docker nemo-sandbox, core pinned to 2026.10.3, LCM pinned to 1.1.1. Live topology/config must be verified before mutation.
- PRIOR-EVIDENCE 13/10: 10.2, Muse primary, Sol 6.1 fallback, Node 24.21.0, 1 CPU / 2.5 GiB, loopback published gateway/webhook, no LCM. Preserve effective model/auth/resources/ports from fresh baseline.
- Local branch codex/sync-origin-main-20260222, HEAD 4bf5f4d926; keep unrelated WIP, no commit/push.

## Access prerequisite

Read-only SSH diagnostics: the server accepts the configured public key; ssh-agent has no identities, and a no-passphrase decrypt probe fails with incorrect passphrase. Keychain mode also failed. Do not change server authorized_keys or request a passphrase in chat. Operator unlocks the existing key locally with ssh-add, then the agent retries authentication.

## Deployment sequence after access is restored

1. Verify hostname, running version/mounts/config, available RAM/disk, restart/OOM baseline and unaffected profile PIDs. Read only allowlisted config fields; never print env or credentials.
2. Stage core 10.3 separately from the serving 10.2 installation using the existing Node image. Verify npm package integrity and lifecycle completion, actual installed CLI/schema, and pinned LCM dependency compatibility.
3. Prepare and test a transport-disabled isolated candidate. Use supported plugin install/config commands; verify dry-run support from the installed CLI. Rehearsal must not mount writable live state. Confirm LCM plugin loads and contextEngine slot is selected; test ingest/recall, compaction, and restart persistence with synthetic data.
4. Stop only Nemo. Make a timestamped private VPS backup of config/state/workspace plus container definition and required rollback metadata; verify checksums and SQLite integrity. Keep all existing rollback containers/backups. Snapshot configuration/model/auth/resource invariants without exposing values.
5. Install the pinned LCM through OpenClaw's official installer under Nemo's state/config scope. Update Codex plugin to the compatible target generation using verified commands. Explicitly enable lossless-claw and its contextEngine slot and grant hooks.allowConversationAccess=true. Preserve other plugin allow entries. Summarization inherits the existing configured model; do not add a new provider/key or override model. No bulk history migration by default.
6. Cut over to the separately staged runtime; preserve the existing host loopback port publishing, Docker user, CPU/RAM/swap/CA/logging parameters. No in-place replacement of a running runtime. Validate config/model invariants before starting. Rollback must restore the pre-cutover state/schema as well as the prior runtime; keep failed candidate data for diagnosis.
7. Verify runtime/plugin package versions + actual startup registration, readyz, Telegram channel readiness, fresh main/fallback route smoke (no external delivery), LCM storage and recall/compaction persistence. Only report completed checks; route override smoke is not automatic failover proof. Recheck unaffected service PIDs and report user Telegram UAT separately.
8. Record live outcome, backup/rollback location, remaining UAT and new 48–72h canary start time in SESSION_HANDOVER/LOCAL_CONTEXT/lesson index. No scheduled monitor or cleanup unless separately requested.

## LCM behavior and cost

LCM stores raw conversation messages and uses the configured LLM to summarize older context. This adds model calls during compaction. Keep the existing Muse/Sol routing and default bounded summary-call protections; do not claim token savings before measuring. Installing/enabling the engine is not proof that model-backed compaction or automatic failover works.

## Sources checked

- https://docs.openclaw.ai/releases/2026.10.3
- https://github.com/Martian-Engineering/lossless-claw/blob/v1.1.1/README.md
- https://github.com/Martian-Engineering/lossless-claw/releases/tag/v1.1.1
- https://github.com/openclaw/openclaw/issues/171311
