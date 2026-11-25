# Communication review and local fix — 2026-11-03

Status: APPLIED ON MAC under explicit owner GO on 2026-11-03; same session resumed. No VPS changes/restarts or Telegram messages sent by the applying agent. Two-way delivery remains UNVERIFIED.

## Evidence

- Claude collab session 91460c38 received the human-pasted Hermes message, and reported no direct Hermes inbound at 19:40. This does not identify transport versus local gate failure.
- Claude access file: group bot senders enabled with mentions. Hermes .env: TELEGRAM_ALLOW_BOTS=mentions and TELEGRAM_BOTS_REQUIRE_MENTION=true. File configuration does not establish effective runtime policy.
- Telegram getMe for both bots: can_read_all_group_messages=false. Claude is administrator in one configured group; another configured group getChatMember failed. Raw chat/user IDs and credentials are omitted.
- Bot-to-Bot Communication Mode is not exposed in the getMe fields returned. Its BotFather state remains unverified.
- Telegram supports bot-to-bot with Communication Mode and command mentions/direct replies. Plain @mention alone is not sufficient in every privacy configuration.
- A real local bug was reproduced: per-group mentionPatterns are ignored for humans. Old result: drop; patched result: deliver.

## Local changes

- Group-specific human patterns work; bots still need a literal Telegram entity mention/command, never a broad regex.
- Group decisions log metadata only to stderr: hashed chat ID, message ID, sender_is_bot, verdict/reason. No text or credentials.
- Channel metadata carries current allow_bots and sender_is_bot rather than relying on stale session stage claims.
- reply attachments rejected before reading or uploading files; channel is text-only.
- Protocol documents native transport requirements, safe direct-reply test, and no bot-sourced GO.

Validation: 17/17 gate tests pass; separate reproduced human-trigger failure now passes; Bun server build passes. Both local gate copies match. No live two-way UAT yet. No credential extraction or real-send canary run.

## Next actions

1. Owner: in verified @BotFather, inspect/enable Bot-to-Bot Communication Mode for the two dedicated bots. Keep group privacy enabled; use direct replies with explicit mentions for test. If the option is absent, report actual UI rather than invent commands.
2. Apply only reviewed local server.ts and collab-gate.ts to the exact active Telegram plugin path, preserving a new backup of the current files. Requires explicit GO for the Mac collab process restart; do not restart Hermes or other services. CLI append-system-prompt reads protocol at session start, so the collab session must reload it.
3. Owner: request one bounded Hermes-to-Claude-to-Hermes exchange with distinct nonce strings. Each bot must reply to the other bot's message and explicitly mention it. Stop after acknowledgement. Use metadata logs to distinguish missing Telegram delivery, gate drops, and model behavior.
4. Do not claim fixed end-to-end until both receivers acknowledge the nonces from bot-sent originals. Do not add a relay or broaden SSH permissions before this diagnosis.

Official sources:
- https://core.telegram.org/bots/features#bot-to-bot-communication
- https://core.telegram.org/api/bots/bot-to-bot

## Authorized apply verification — 2026-11-03 19:55 VNT

- Independent fresh-context reviewer: bounded APPROVE; 17/17 tests and build PASS, no blocker in reviewed patch.
- Before hashes checked to prevent overwriting concurrent plugin changes.
- Backup: `~/.claude/channels/telegram-collab/patch-backup-20261103-195524/`; contains the prior two plugin sources and non-secret resume metadata.
- Old Claude PID 45135 and plugin PID 45172 stopped. New Claude PID 62134 and plugin PID 62178 running.
- Same session resumed: `91460c38-012f-4ddd-aae1-b8757614df3a`. Session metadata verified after startup; history retained.
- Both installed files byte-match the reviewed repo sources; runtime disallowedTools still Bash,Edit,Write,NotebookEdit; updated protocol present in startup arguments.
- Launcher started via persistent PTY exec session 14414. No new model prompt or Telegram message was injected by the applying agent.
- Startup warns of simultaneous CLAUDE_CODE_OAUTH_TOKEN and managed login key, and remote managed settings 401. This is an existing auth configuration issue, not proven model-call failure. Auth was not changed; a natural owner message is required to verify model execution.
- Owner UI guidance: use official BotFather Mini App https://t.me/botfather?startapp rather than relying only on the legacy chat keyboard. Official docs confirm Communication Mode; exact menu layout is not documented for every client. Await owner confirmation and bounded two-way test.

## Follow-up: missing reply pointer — 20:07 test

- Claude inbound #41 is from the owner, not a direct Hermes H3. Hermes reports it has not sent H3. Missing H3 is not a delivery failure yet.
- Source verified on VPS: Telegram adapter _reply_context returns reply_to_id/text and _build_message_event stores reply_to_message_id. gateway/run_inbound.py::_prepend_inbound_reply_context uses the ID as a condition, but renders quoted text without the original message ID. This is a source-level omission; no evidence yet that raw Telegram update #41 contained a reply pointer.
- Source verified on Mac: Claude server omitted reply_to metadata entirely. Local follow-up adds original reply message ID and sender_is_bot flag, without importing quoted text as instructions. This follow-up is NOT installed into the running plugin.
- Original Claude message #38 is known from its recorded outbound reply at 19:40. A direct test can use that explicit target; the owner need not repeat quote gestures to recover it.
- No Hermes patch/install/restart or real-send test performed. A bounded Telegram send test requires owner authorization; Bot-to-Bot mode is now owner-confirmed enabled for both bots, not independently verified via API.

## Authorized single H3 send attempt

- Owner explicitly authorized exactly one H3 canary as Hermes, replying to Claude message38.
- Exactly one sendMessage request attempted; Telegram returned HTTPError, no successful message ID obtained. No automatic retry.
- Diagnostic limitation: the send wrapper caught only the exception type and did not retain HTTP status/error description. This prevents claiming the exact rejection cause. Do not reconstruct the missing error from guesses.
- Subsequent read-only checks: sender username hungreo_bds_bot; target is a group; Hermes membership administrator. Claude's original recorded outbound message38 targets the same chat. No routing mismatch found in these checks.
- Next bounded transport probe, if separately authorized: send one bot-command mention /collab@hungreo_claude_bot H3 without a reply anchor, eliminating dependency on pre-enable message38. Preserve HTTP status and sanitized Telegram error description on failure. No relay or service change required.

## Command canary result and proven gate blocker

- Exactly one authorized command-mention canary sent as Hermes: sendMessage ok=true, Hermes-side message_id=3050. No automatic retry.
- Group type is basic group. Telegram official message ID sequence documentation confirms IDs are account-scoped in basic groups; Claude-side message38 must not be reused blindly as a Hermes-side reply anchor. This invalid assumption in the earlier test has been corrected.
- Independently retrieved actual Hermes bot identity via getMe and compared it with the target Claude group allowFrom: NOT PRESENT. No raw identity values stored in repo.
- Reproduced the actual command/message sender against the installed gate with current access.json: drop / bot_sender_not_in_group_allowFrom. Adding that verified ID to just that group in memory changes verdict to deliver. Live access.json has not been changed.
- A scoped atomic apply script is prepared privately at /private/tmp/codex-apply-hermes-group-allowlist.py. It backs up access.json, changes one group sender entry only, preserves human DM/approval authority, and needs no restart because access is reloaded per inbound message.
- No end-to-end H3/C3 PASS yet. Request target-specific GO for that group allowlist change plus one fresh canary, as required by owner access-control rules.
- Source: https://core.telegram.org/api/updates#message-id-sequences

## Allowlist apply and two-way canary PASS — 2026-11-03 20:28–20:29 VNT

- Owner explicitly GO adding the verified Hermes ID to exactly the current group allowFrom and one fresh canary. Scoped apply completed with private backup; top-level DM/approval allowFrom unchanged; no service restart.
- Sent exactly one new H3-ALLOWLIST command mention as Hermes: Telegram ok=true, Hermes-side message_id3051, date1793712529.
- Claude session91460c38 received it directly at 13:28:49Z as message51, sender_is_bot=true, allow_bots=mentions. No human forwarding.
- Claude invoked Telegram reply to its own received message51 with text `Đã nhận H3-ALLOWLIST. C3-ALLOWLIST @hungreo_bds_bot`; tool result sent(id:52) at13:29:04Z.
- Hermes state.db opened mode=ro: row21280 is inbound user-role C3-ALLOWLIST with platform_message_id3052 timestamp1793712544. Row21281 is assistant acknowledgment at1793712549.471597: `Đã nhận C3-ALLOWLIST từ Claude. Xác nhận một lần và dừng tại đây.` No tag back to Claude.
- Both native transport directions and actual model handling are verified for this bounded exchange. This does not certify sustained stability, production-action permissions, or general multi-agent productivity.
- Proven blocker fixed: verified Hermes sender missing from Claude group allowlist. User confirmed BotFather mode enabled earlier. No relay needed.
- Pending local-only follow-up: replyPointerMeta addition (18th unit test) was not needed for this command/reply canary and has not been installed. The running plugin retains the earlier reviewed 17-test patch; do not conflate the two versions.
- OAuth/managed-settings startup warnings remain a separate issue; model call succeeded on the canary. No auth changes performed.

## Shared tracking recorded

Canonical shared issue: VPS-20261103-001, monitoring. Registry validate/rebuild PASS (19 issues). Entry records bounded verified root cause/resolution, two-way evidence and explicit residuals. Lesson and handover point to this issue; no bot/config/service changes made while recording.
