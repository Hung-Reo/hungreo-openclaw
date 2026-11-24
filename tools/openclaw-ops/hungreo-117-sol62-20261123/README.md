# Hungreo 11.7 and Sol 6.2 cutover

**Status on 23 November 2026: rolled back.** The original profile is back in service on OpenClaw 2026.9.36 with Sol 6.1.

The 11.7 package and official plugin versions were staged separately on the VPS. The existing binding preload and command registry check were incompatible with the new build. The candidate preload preserves the decline-only fallthrough in memory and checks the exact target artifact. It passed the static version invocation. Gateway plugin behavior on 11.7 remains unverified.

The quiescent full-profile copy matched with rsync checksum comparison. SQLite quick_check passed for the main state, agent transcript, and lossless-claw databases. The live profile was then replaced by that working copy for the candidate CLI preflight. The CLI rejected agents.defaults.heartbeat before the model or plugins were changed. Upstream 11.7 requires converting this to an automation job, which changes some delivery behavior.

Rollback restored the original directory and 9.36 runtime. The config and environment file hashes matched, both OpenClaw gateways returned readyz 200, the Hungreo Telegram probe passed, and the healthcheck timer was active. Earlier attempts stopped on protected /proc entries and were recovered on 9.36. The last recovery required a separate healthcheck timer start. The script now checks /proc access while the gateway is still up and rejects the known heartbeat incompatibility before stopping any service.

The VPS backup bundle is /home/hung/backups/hungreo-rollback-openclaw-117/20261123-193941.i0mm568Q. The verified profile copy is under post-cutover.QWYd4KUQ/profile. The bundle is private because it contains configuration, credentials, and bot state.

The current scripts are retained for their backup and recovery logic. Applying them to the live profile is blocked until there is a separately approved heartbeat migration with explicit cadence, isolation, model, and delivery checks.

## Approved heartbeat migration attempt at 20:03 on 23 November

The operator approved one heartbeat migration for Hungreo. The approved configuration was 2h cadence, 06:00 to 23:00 in Asia/Ho_Chi_Minh, isolated session, light context, and openai/gpt-5.6-luna. The original checklist contained five entries. Sol 6.2 was to be tested only after verifying the heartbeat and unrelated jobs.

The new backup passed checksum comparison and quick_check on all three databases. Doctor then hit the runbook's 220-second timeout during config and plugin convergence. The isolated working state reached shared schema 36. The agent DB remained at schema 24 and the heartbeat was still in legacy form. Aborted plugin-contract loads occurred during timeout shutdown. Sol 6.2 never ran.

The original profile and runtime were restored. The timer was restarted separately. At 20:14 the Hungreo and Suckhoe ready probes returned 200, the Hungreo Telegram probe passed, the config and environment checksums matched, and the timer was active. Suckhoe and Hermes retained their observed PIDs. The partial migration was held in the 20:03 bundle until the targeted cleanup below. The earlier verified pre-migration copy remains in the 19:39 bundle described above.

The local runbook now gives Doctor up to 600 seconds. That change has not been exercised. The VPS had 7.3 GiB available after rollback. A fresh 6.6 GiB profile copy and the additional Doctor files observed during this run do not fit together in the remaining space. Keep the current service online until a new cutover can preserve the rollback copy and provide adequate migration space.

## Targeted cleanup at 20:23 on 23 November

Hưng authorized removing only `20261123-200336.I4n9RXL4/post-cutover.XclYzVBD/profile`. The attempt was marked rolled back, and the directory contained the partially migrated shared schema 36. The check found no reference from inspectable processes, user systemd units, or crontab, and no mounts within the directory. Four protected system helpers matched their expected service or login scopes.

After removal, available space rose from 7.22 to 14.31 GiB, reclaiming 7.09 GiB. The independent 9.36 copy passed critical-file checksums before and after the operation. The Doctor log and live config and environment files matched their pre-cleanup checksums. Both OpenClaw readiness probes returned 200, and the checked services kept their PIDs and restart counters.

## Approved cutover at 20:34 on 23 November

The cutover started after the 20:33 heartbeat completed. An online pre-copy reduced the time the service was stopped. The final copy passed rsync checksum comparison and SQLite `quick_check` on all three databases. Doctor completed with the 600-second timeout. The candidate reached shared schema 36 and agent schema 38.

The config check stopped the cutover because Doctor dropped the explicitly disabled `skills.entries.nano-banana-pro` entry and updated two wizard metadata fields. Offline comparison of the preserved candidate found that the approved heartbeat kept the same ID, schedule anchor, checklist, owner delivery, and empty-checklist guard. It became an isolated, idle-only Luna 5.6 automation. The candidate also lost one unrelated, enabled weekly `agentTurn` job. That job had a successful run at 04:33 the same day and was due again at 04:33 on 30 November. The candidate did not receive Telegram traffic or run Sol 6.2.

Automatic rollback put back the original profile, 9.36 executable, and Sol 6.1 config. At 20:46 the config and environment checksums matched and the timer was active. Both gateways returned `/readyz` 200 and the Hungreo Telegram probe passed. The weekly job is present in the restored database.

The failed candidate is retained at `/home/hung/backups/hungreo-rollback-openclaw-117/20261123-203424.x2NKjZ6y/post-cutover.UCo632MT/profile`. It occupies 7.1 GiB. Measured available space was 6.55 GiB after rollback. Keep the existing configuration and every unrelated job in the next candidate, document any nonfunctional Doctor metadata updates, and check space for a fresh full working copy and migration overhead before another cutover.

## Offline Doctor dry-run at 21:20 on 23 November (Claude Code)

Scope approved by Hưng: root cause and a dry-run on a copy only. Rùa stayed on 9.36 + Sol 6.1 throughout (same PID 2219089, `/readyz` 200 for Hungreo and Suckhoe, live config unchanged).

**Root cause (VERIFIED against the 11.7 dist and docs):**

- The weekly job `skill-collection-review-main` (declaration key `skill-collection-review:main`) is the retired Skill Workshop curator. 11.7 deletes such rows whenever the cron store loads, creates no replacement, and reserves the key namespace (`dist/load.kernel-*.mjs` `isRetiredCollectionReview`, `docs/automation/cron-jobs/payloads.md`, `docs/tools/skill-workshop.md`). It cannot be kept by config. The replacement is the daily unused-skill cleanup.
- `nano-banana-pro` is a retired bundled skill. Doctor's `normalizeLegacyNanoBananaSkill` deletes `skills.entries.nano-banana-pro` unconditionally on every run. The risk is that the profile still has `workspace/skills/nano-banana-pro`, which would become enabled once the entry is gone.
- The two wizard fields are `wizard.lastRunAt` and `wizard.lastRunVersion`. They are non-functional.

**Fix tested:** before Doctor, move `workspace/skills/nano-banana-pro` to `workspace/.retired-skills-117/` on the working copy. Treat the four config paths above plus the retired curator job as expected changes.

**Dry-run:** a 5.9 GiB copy (online rsync plus SQLite backup-API snapshots, all quick_check ok) was migrated in Docker (`--network none`, profile bind-mounted at its own path, runtime read-only, 3 GiB memory cap). The copy's stale gateway leases and lock files were removed first to simulate a clean stop. `compare.py` against `must-keep-20261123.json` (48 jobs, 23 enabled, 43 disabled skills) returned PASS. Every other job kept its schedule, payload, prompt hash, delivery and next run. The heartbeat kept its ID, schedule, active hours and next run, and became isolated, idle-only Luna 5.6 with light context. `config validate` passed, `nano-banana-pro` is absent from the skill list, and a second Doctor run changed nothing further.

**Found along the way:** Doctor writes about 0.7 GiB to `~/.openclaw-hungreo.update-captures` outside the profile, plus about 0.75 GiB of DB backups. Its "Database engines" step needs more than 3 GiB RAM when temporary files sit on tmpfs. The VPS swap was about 90% used. The copy was removed afterwards (21 GiB free). Evidence (logs and must-keep only) is in `/home/hung/claude-dryrun-117-20261123`.

**Not covered:** plugin updates with network access, gateway start on 11.7, Telegram, and the Sol 6.2 Codex OAuth turn.

## Script fix and second dry-run at 06:25 on 24 November (Claude Code)

Hưng decided to let 11.7 drop the weekly Skill Workshop curator, and to archive the workspace copy of `nano-banana-pro` rather than delete it. The script changes below are staged in `$UPGRADE/ops`, with backups `*.bak-20261124-*` beside them:

- `cutover.sh` MIGRATE moves `workspace/skills/nano-banana-pro` to `workspace/.retired-skills-117/` before Doctor runs. The 9.36 original in `$B/profile` keeps the skill.
- `profile-check.py` `config` accepts `wizard.lastRunAt` and `wizard.lastRunVersion`. It accepts the removed `skills.entries.nano-banana-pro` only if the entry was a plain disable, the skill is no longer installed, and the archive exists.
- `profile-check.py` `heartbeat` accepts only the retired `skill-collection-review:*` job as missing, and now also compares job names. The checklist size cap rose from 2,048 to 16,384 characters. 9.36 already runs the heartbeat from DB scratch (3,674 characters), not from `HEARTBEAT.md` (1,166 characters, unused since 4 October). Doctor keeps that scratch unchanged.

`dryrun2.sh` and `dryrun2-resume.sh` ran the cutover's MIGRATE and PLUGINS phases on a fresh copy in Docker. The copy had 49 jobs, 24 of them enabled. Doctor finished with rc 0. The patched `check config`, `check heartbeat` and `check db` passed before and after the five plugin updates, and so did `config validate`. The plugin updates ran offline from the staged npm cache and all returned rc 0. `compare.py` passed. The old script failed on the same copy in both checks, which confirms the red to green change. The live profile stayed untouched (PID 2219089, readyz 200, the skill folder and entry in place).

The Sol 6.2 model batch could not be tested offline. Validation needs the Codex app-server online, and a networked copy could refresh the live OAuth token. As of 06:33 on 24 November, the live `codex-home/models_cache.json` (client 0.160.0) lists `gpt-6.1-sol` but no `gpt-6.2-sol`. 11.7 bundles Codex 0.170.0, so whether 6.2 is available remains UNVERIFIED. The MODEL_CHECK phase rolls back if it is not.

Cleanup left 728 MiB in `/home/hung/claude-dryrun-117-20261124/chome`: the Doctor update-captures and two root-owned mount points. The guardrail hook blocks recursive removal of paths that contain the profile name, so Hưng runs this removal himself.
