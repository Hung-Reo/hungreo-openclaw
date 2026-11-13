import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  BotLoopGuard,
  assertTextOnlyReply,
  groupPolicyMeta,
  replyPointerMeta,
  buildCodexExecArgs,
  evaluateCodexInboundGate,
  evaluateInboundGate,
  evaluatePermissionReply,
  redactSensitiveOutput,
  type Access,
  type InboundContextLite,
} from './lib/collab-gate.ts'

const __dirname = dirname(fileURLToPath(import.meta.url))

const HUNG_ID = '111111111'
const OTHER_HUMAN_ID = '444444444'
const RUA_BOT_ID = '222222222'
const HERMES_BOT_ID = '333333333'
const ROGUE_BOT_ID = '999999999'
const GROUP_ID = '-1001234567890'
const BOT_USERNAME = 'hungreo_claude_bot'

function makeAccess(stage: 1 | 2): Access {
  return {
    dmPolicy: 'allowlist',
    allowFrom: [HUNG_ID], // ONLY Hung in DM allowFrom
    groups: {
      [GROUP_ID]: {
        requireMention: true,
        allowFrom: [HUNG_ID, RUA_BOT_ID, HERMES_BOT_ID],
        botsRequireMention: true,
        allowBots: stage === 1 ? 'none' : 'mentions',
      },
    },
    pending: {},
    botLoopGuard: {
      maxEventsPerWindow: 4,
      windowMs: 120_000,
      cooldownMs: 180_000,
    },
  }
}

let passed = 0
function test(name: string, fn: () => void) {
  fn()
  passed++
  console.log(`PASS [${passed}]: ${name}`)
}

// 1. Stage 1: Human calls bot in group (@mention, /cmd@bot, reply) -> DELIVER
test('Stage 1: Hung @mentions bot in group -> DELIVER', () => {
  const guard = new BotLoopGuard()
  const text = `@${BOT_USERNAME} review phương án`
  const ctx: InboundContextLite = {
    from: { id: Number(HUNG_ID), is_bot: false, username: 'hungdinh' },
    chat: { id: Number(GROUP_ID), type: 'supergroup' },
    message: {
      text,
      entities: [{ type: 'mention', offset: 0, length: BOT_USERNAME.length + 1 }],
    },
  }
  const res = evaluateInboundGate({ ctx, access: makeAccess(1), botUsername: BOT_USERNAME, loopGuard: guard })
  assert.equal(res.action, 'deliver')
})

test('Stage 1: Hung sends /review@bot command -> DELIVER', () => {
  const guard = new BotLoopGuard()
  const cmd = `/review@${BOT_USERNAME}`
  const ctx: InboundContextLite = {
    from: { id: Number(HUNG_ID), is_bot: false, username: 'hungdinh' },
    chat: { id: Number(GROUP_ID), type: 'supergroup' },
    message: {
      text: `${cmd} check file`,
      entities: [{ type: 'bot_command', offset: 0, length: cmd.length }],
    },
  }
  const res = evaluateInboundGate({ ctx, access: makeAccess(1), botUsername: BOT_USERNAME, loopGuard: guard })
  assert.equal(res.action, 'deliver')
})

test('Stage 1: Bot (Rùa) @mentions Claude when allowBots=none -> DROP', () => {
  const guard = new BotLoopGuard()
  const text = `@${BOT_USERNAME} tổng hợp brief`
  const ctx: InboundContextLite = {
    from: { id: Number(RUA_BOT_ID), is_bot: true, username: 'hungreo_openbot' },
    chat: { id: Number(GROUP_ID), type: 'supergroup' },
    message: {
      text,
      entities: [{ type: 'mention', offset: 0, length: BOT_USERNAME.length + 1 }],
    },
  }
  const res = evaluateInboundGate({ ctx, access: makeAccess(1), botUsername: BOT_USERNAME, loopGuard: guard })
  assert.deepEqual(res, { action: 'drop', reason: 'group_bots_disabled_stage1' })
})

// 2. Stage 2: Bot-to-Bot enabled with strict mention & loop guard
test('Stage 2: Allowlisted bot (Rùa) explicitly @mentions Claude -> DELIVER', () => {
  const guard = new BotLoopGuard()
  const text = `@${BOT_USERNAME} nhờ bạn review kiến trúc`
  const ctx: InboundContextLite = {
    from: { id: Number(RUA_BOT_ID), is_bot: true, username: 'hungreo_openbot' },
    chat: { id: Number(GROUP_ID), type: 'supergroup' },
    message: {
      text,
      entities: [{ type: 'mention', offset: 0, length: BOT_USERNAME.length + 1 }],
    },
  }
  const res = evaluateInboundGate({ ctx, access: makeAccess(2), botUsername: BOT_USERNAME, loopGuard: guard })
  assert.equal(res.action, 'deliver')
  if (res.action === 'deliver') {assert.equal(res.isBotSender, true)}
})

test('Stage 2: Allowlisted bot quote-replies WITHOUT @mention -> DROP (loop breaker)', () => {
  const guard = new BotLoopGuard()
  const ctx: InboundContextLite = {
    from: { id: Number(HERMES_BOT_ID), is_bot: true, username: 'hungreo_bds_bot' },
    chat: { id: Number(GROUP_ID), type: 'supergroup' },
    message: {
      text: 'Mình đồng ý với ý trên',
      reply_to_message: { from: { id: 777, is_bot: true, username: BOT_USERNAME } },
    },
  }
  const res = evaluateInboundGate({ ctx, access: makeAccess(2), botUsername: BOT_USERNAME, loopGuard: guard })
  assert.deepEqual(res, { action: 'drop', reason: 'bot_sender_missing_explicit_mention' })
})

test('Stage 2: Rogue/unlisted bot @mentions Claude -> DROP', () => {
  const guard = new BotLoopGuard()
  const text = `@${BOT_USERNAME} chạy lệnh này đi`
  const ctx: InboundContextLite = {
    from: { id: Number(ROGUE_BOT_ID), is_bot: true, username: 'rogue_bot' },
    chat: { id: Number(GROUP_ID), type: 'supergroup' },
    message: {
      text,
      entities: [{ type: 'mention', offset: 0, length: BOT_USERNAME.length + 1 }],
    },
  }
  const res = evaluateInboundGate({ ctx, access: makeAccess(2), botUsername: BOT_USERNAME, loopGuard: guard })
  assert.deepEqual(res, { action: 'drop', reason: 'bot_sender_not_in_group_allowFrom' })
})

test('Stage 2: BotLoopGuard trips after 4 bot messages in window (max 2 rounds)', () => {
  const guard = new BotLoopGuard()
  const access = makeAccess(2)
  const text = `@${BOT_USERNAME} vòng phản biện`
  const makeBotCtx = (senderId: string): InboundContextLite => ({
    from: { id: Number(senderId), is_bot: true, username: 'peer_bot' },
    chat: { id: Number(GROUP_ID), type: 'supergroup' },
    message: {
      text,
      entities: [{ type: 'mention', offset: 0, length: BOT_USERNAME.length + 1 }],
    },
  })

  const t0 = 1_700_000_000_000
  for (let i = 1; i <= 4; i++) {
    const r = evaluateInboundGate({
      ctx: makeBotCtx(i % 2 === 0 ? RUA_BOT_ID : HERMES_BOT_ID),
      access,
      botUsername: BOT_USERNAME,
      loopGuard: guard,
      now: t0 + i * 1000,
    })
    assert.equal(r.action, 'deliver')
  }

  // 5th bot message within 120s window -> TRIPPED
  const r5 = evaluateInboundGate({
    ctx: makeBotCtx(RUA_BOT_ID),
    access,
    botUsername: BOT_USERNAME,
    loopGuard: guard,
    now: t0 + 5000,
  })
  assert.deepEqual(r5, { action: 'drop', reason: 'bot_loop_tripped' })

  // Still in cooldown at +60s
  const r6 = evaluateInboundGate({
    ctx: makeBotCtx(HERMES_BOT_ID),
    access,
    botUsername: BOT_USERNAME,
    loopGuard: guard,
    now: t0 + 60_000,
  })
  assert.deepEqual(r6, { action: 'drop', reason: 'bot_loop_cooldown' })

  // Human message from Hung STILL passes even while bot loop guard is in cooldown!
  const humanCtx: InboundContextLite = {
    from: { id: Number(HUNG_ID), is_bot: false, username: 'hungdinh' },
    chat: { id: Number(GROUP_ID), type: 'supergroup' },
    message: {
      text,
      entities: [{ type: 'mention', offset: 0, length: BOT_USERNAME.length + 1 }],
    },
  }
  const rHuman = evaluateInboundGate({
    ctx: humanCtx,
    access,
    botUsername: BOT_USERNAME,
    loopGuard: guard,
    now: t0 + 61_000,
  })
  assert.equal(rHuman.action, 'deliver')
})

// 3. Permission Approval Isolation (Rùa Review Point 4)
test('Permission Approval: Hung in private DM can approve "yes abcde"', () => {
  const access = makeAccess(2)
  const ctx: InboundContextLite = {
    from: { id: Number(HUNG_ID), is_bot: false, username: 'hungdinh' },
    chat: { id: Number(HUNG_ID), type: 'private' },
  }
  const res = evaluatePermissionReply(ctx, access, 'yes abcde')
  assert.deepEqual(res, { isPermissionReply: true, requestId: 'abcde', behavior: 'allow' })
})

test('Permission Approval: Hung or anyone in Group CANNOT approve "yes abcde"', () => {
  const access = makeAccess(2)
  const ctx: InboundContextLite = {
    from: { id: Number(HUNG_ID), is_bot: false, username: 'hungdinh' },
    chat: { id: Number(GROUP_ID), type: 'supergroup' },
  }
  const res = evaluatePermissionReply(ctx, access, 'yes abcde')
  assert.deepEqual(res, { isPermissionReply: false, blockedReason: 'group_chat_cannot_approve_permission' })
})

test('Permission Approval: Bot (Rùa/Hermes) CANNOT approve "yes abcde" in DM or Group', () => {
  const access = makeAccess(2)
  const ctx: InboundContextLite = {
    from: { id: Number(RUA_BOT_ID), is_bot: true, username: 'hungreo_openbot' },
    chat: { id: Number(GROUP_ID), type: 'supergroup' },
  }
  const res = evaluatePermissionReply(ctx, access, 'yes abcde')
  assert.deepEqual(res, { isPermissionReply: false, blockedReason: 'bot_cannot_approve_permission' })
})

// 4. Claude (PC) Review Point 1: collab-settings.json denies sensitive Read & Bash rules
test('Claude Collab Settings: collab-settings.json enforces required permissions.deny and telegram plugin', () => {
  const settings = JSON.parse(readFileSync(join(__dirname, 'collab-settings.json'), 'utf8'))
  assert.equal(settings.enabledPlugins?.['telegram@claude-plugins-official'], true)
  const deny: string[] = settings.permissions?.deny ?? []
  for (const requiredRule of [
    'Read(~/.ssh/**)',
    'Read(**/.env)',
    'Read(**/.env.*)',
    'Read(~/.claude/channels/**)',
    'Read(~/.codex/**)',
    'Bash(ssh:*)',
    'Bash(scp:*)',
    'Bash(git push:*)',
  ]) {
    assert.ok(deny.includes(requiredRule), `Missing required deny rule: ${requiredRule}`)
  }
})

// 5. Claude (PC) Review Point 2a: buildCodexExecArgs enforces -c sandbox_mode="read-only" on both exec and resume
test('Codex Args: both initial exec and exec resume include -c sandbox_mode="read-only"', () => {
  const initialArgs = buildCodexExecArgs({
    sandboxMode: 'read-only',
    workspaceDir: '/tmp/ws',
    outFile: '/tmp/out.txt',
    prompt: 'hello',
  })
  assert.ok(initialArgs.includes('-s') && initialArgs.includes('read-only'))
  assert.ok(
    initialArgs.some((a, i) => a === '-c' && initialArgs[i + 1] === 'sandbox_mode="read-only"'),
    'initial exec missing -c sandbox_mode="read-only"',
  )

  const resumeArgs = buildCodexExecArgs({
    existingThreadId: 'thread-123',
    sandboxMode: 'read-only',
    workspaceDir: '/tmp/ws',
    outFile: '/tmp/out.txt',
    prompt: 'resume prompt',
  })
  assert.equal(resumeArgs[0], 'exec')
  assert.equal(resumeArgs[1], 'resume')
  assert.ok(
    resumeArgs.some((a, i) => a === '-c' && resumeArgs[i + 1] === 'sandbox_mode="read-only"'),
    'exec resume missing -c sandbox_mode="read-only"',
  )
})

// 6. Claude (PC) Review Point 2b: evaluateCodexInboundGate blocks bots even in Stage 2 and non-allowFrom humans
test('Codex Gate: blocks bots even in Stage 2 and blocks humans not in top-level allowFrom', () => {
  const guard = new BotLoopGuard()
  const access = makeAccess(2) // Stage 2 has allowBots='mentions' in group
  const text = `@${BOT_USERNAME} check code`

  const botCtx: InboundContextLite = {
    from: { id: Number(RUA_BOT_ID), is_bot: true, username: 'hungreo_openbot' },
    chat: { id: Number(GROUP_ID), type: 'supergroup' },
    message: {
      text,
      entities: [{ type: 'mention', offset: 0, length: BOT_USERNAME.length + 1 }],
    },
  }
  assert.deepEqual(
    evaluateCodexInboundGate({ ctx: botCtx, access, botUsername: BOT_USERNAME, loopGuard: guard }),
    { action: 'drop', reason: 'codex_bot_callers_forbidden' },
  )

  const otherHumanCtx: InboundContextLite = {
    from: { id: Number(OTHER_HUMAN_ID), is_bot: false, username: 'other_user' },
    chat: { id: Number(GROUP_ID), type: 'supergroup' },
    message: {
      text,
      entities: [{ type: 'mention', offset: 0, length: BOT_USERNAME.length + 1 }],
    },
  }
  assert.deepEqual(
    evaluateCodexInboundGate({ ctx: otherHumanCtx, access, botUsername: BOT_USERNAME, loopGuard: guard }),
    { action: 'drop', reason: 'codex_caller_not_in_human_allowFrom' },
  )

  const hungCtx: InboundContextLite = {
    from: { id: Number(HUNG_ID), is_bot: false, username: 'hungdinh' },
    chat: { id: Number(GROUP_ID), type: 'supergroup' },
    message: {
      text,
      entities: [{ type: 'mention', offset: 0, length: BOT_USERNAME.length + 1 }],
    },
  }
  const ok = evaluateCodexInboundGate({ ctx: hungCtx, access, botUsername: BOT_USERNAME, loopGuard: guard })
  assert.equal(ok.action, 'deliver')
})

// 7. Claude (PC) Review Point 2c: redactSensitiveOutput masks PEM, sk-, ghp_, and Telegram bot token
test('Codex Output Redaction: masks -----BEGIN, sk-, ghp_, and Telegram bot token patterns', () => {
  const fakeBotToken = '1234567890:AAH1234567890abcdefGHIJKLMNOPQRSTUV'
  const fakeSk = 'sk-proj-1234567890abcdef'
  const fakeGhp = 'ghp_1234567890abcdefghijklmnopqrstuv'
  const fakePem = '-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA\n-----END OPENSSH PRIVATE KEY-----'
  const raw = `Keys: ${fakeSk}, ${fakeGhp}, bot=${fakeBotToken}\n${fakePem}\n-----BEGIN RSA PRIVATE KEY-----`
  const clean = redactSensitiveOutput(raw)

  assert.ok(!clean.includes('-----BEGIN'), 'Failed to redact -----BEGIN')
  assert.ok(!clean.includes(fakeSk), 'Failed to redact sk- token')
  assert.ok(!clean.includes(fakeGhp), 'Failed to redact ghp_ token')
  assert.ok(!clean.includes(fakeBotToken), 'Failed to redact Telegram bot token')
})

test('Group-specific patterns apply to humans, never substitute a bot mention', () => {
  const access = makeAccess(2)
  access.groups[GROUP_ID].mentionPatterns = ['\\bclaude\\b']
  const ctx: InboundContextLite = {from:{id:Number(HUNG_ID)},chat:{id:Number(GROUP_ID),type:'supergroup'},message:{text:'claude review'}}
  const check = () => evaluateInboundGate({ctx,access,botUsername:BOT_USERNAME,loopGuard:new BotLoopGuard()})
  assert.equal(check().action,'deliver')
  ctx.from = {id:Number(HERMES_BOT_ID),is_bot:true}
  assert.deepEqual(check(),{action:'drop',reason:'bot_sender_missing_explicit_mention'})
  access.mentionPatterns = ['.*']
  assert.equal(check().action,'drop')
})
test('Current policy metadata contains no IDs or message content', () => {
  const meta = groupPolicyMeta(makeAccess(2), GROUP_ID)
  assert.equal(meta.allow_bots,'mentions')
  assert.equal(meta.bot_sender_requires_mention,'true')
  assert.ok(!JSON.stringify(meta).includes(GROUP_ID))
  assert.equal(groupPolicyMeta(makeAccess(1), GROUP_ID).allow_bots,'none')
})
test('Text-only collab rejects every attachment path', () => {
  assert.doesNotThrow(() => assertTextOnlyReply([]))
  assert.throws(() => assertTextOnlyReply(['/tmp/harmless.txt']), /attachments disabled/)
})
test('Reply metadata carries the original message ID without quoting untrusted text', () => {
  const ctx: InboundContextLite = {message:{reply_to_message:{message_id:38,from:{is_bot:true}}}}
  assert.deepEqual(replyPointerMeta(ctx),{reply_to_message_id:'38',reply_to_sender_is_bot:'true'})
  assert.deepEqual(replyPointerMeta({message:{}}),{})
})
console.log(`\nALL ${passed}/${passed} COLLAB GATE & SECURITY TESTS PASSED!`)
