/**
 * Hardened Access Gate & Bot Loop Guard for Mac Collaboration Hub (Claude & Codex)
 * Incorporates Rùa (hungreo), Argon, and Claude (PC) security reviews (2026-11-03):
 * 1. Separates human DM permission-approval authority (`allowFrom`) from group discussion (`groups[id].allowFrom`).
 * 2. Blocks `is_bot === true` and non-private chats from EVER triggering tool permission approvals (`yes xxxxx`).
 * 3. Requires explicit `@botUsername` mention when sender is another bot (`botsRequireMention: true` by default),
 *    preventing infinite quote-reply loops between two bots.
 * 4. Enforces sliding-window `BotLoopGuard` (default max 4 bot messages / 120s window per chat, 2 rounds max).
 * 5. Enforces human-only `allowFrom` caller restriction, `-c sandbox_mode="read-only"` on both `exec` and `exec resume`,
 *    and outbound secret redaction (`-----BEGIN`, `sk-`, `ghp_`, Telegram bot tokens) for Codex bridge.
 */

export type PendingEntry = {
  senderId: string
  chatId: string
  createdAt: number
  expiresAt: number
  replies: number
}

export type GroupPolicy = {
  requireMention: boolean
  /** Opt-in bounded, memory-only history; never invokes the model on its own. */
  roomContext?: boolean
  /** Extra human triggers only; bot senders always need an explicit Telegram mention. */
  mentionPatterns?: string[]
  allowFrom: string[]
  /** Require explicit @botUsername when sender.is_bot === true (quote-reply alone won't trigger). Default: true */
  botsRequireMention?: boolean
  /** Allow bot senders listed in allowFrom (or any bot if allowFrom is empty AND allowBots is "mentions"|"all"). Default: "none" (Stage 1), set to "mentions" in Stage 2 */
  allowBots?: 'none' | 'mentions' | 'all'
}

export type BotLoopGuardConfig = {
  maxEventsPerWindow: number
  windowMs: number
  cooldownMs: number
}

export type Access = {
  dmPolicy: 'pairing' | 'allowlist' | 'disabled'
  /** Numeric human user IDs allowed in DM AND allowed to approve permissions. NEVER add bot IDs here! */
  allowFrom: string[]
  groups: Record<string, GroupPolicy>
  pending: Record<string, PendingEntry>
  mentionPatterns?: string[]
  ackReaction?: string
  replyToMode?: 'off' | 'first' | 'all'
  textChunkLimit?: number
  chunkMode?: 'length' | 'newline'
  botLoopGuard?: Partial<BotLoopGuardConfig>
}

export type InboundContextLite = {
  from?: {
    id: number
    is_bot?: boolean
    username?: string
  }
  chat?: {
    id: number
    type: 'private' | 'group' | 'supergroup' | 'channel'
  }
  message?: {
    message_id?: number
    date?: number
    text?: string
    caption?: string
    quote?: { text: string }
    entities?: Array<{ type: string; offset: number; length: number; user?: { is_bot?: boolean; username?: string } }>
    caption_entities?: Array<{ type: string; offset: number; length: number; user?: { is_bot?: boolean; username?: string } }>
    reply_to_message?: {
      message_id?: number
      text?: string
      caption?: string
      from?: {
        id?: number
        is_bot?: boolean
        username?: string
      }
    }
  }
}

export type GateVerdict =
  | { action: 'deliver'; access: Access; isBotSender: boolean }
  | { action: 'drop'; reason: string }
  | { action: 'pair'; code: string; isResend: boolean }

const PERMISSION_REPLY_RE = /^\s*(y|yes|n|no)\s+([a-km-z]{5})\s*$/i

export class BotLoopGuard {
  private history = new Map<string, number[]>()
  private cooldownUntil = new Map<string, number>()

  constructor(
    private defaultCfg: BotLoopGuardConfig = {
      maxEventsPerWindow: 4, // Max 2 back-and-forth rounds
      windowMs: 120_000,
      cooldownMs: 180_000,
    },
  ) {}

  admit(chatId: string, now = Date.now(), customCfg?: Partial<BotLoopGuardConfig>): { allowed: boolean; reason?: string } {
    const cfg = { ...this.defaultCfg, ...customCfg }
    const until = this.cooldownUntil.get(chatId) ?? 0
    if (now < until) {
      return { allowed: false, reason: 'bot_loop_cooldown' }
    }
    const cutoff = now - cfg.windowMs
    const recent = (this.history.get(chatId) ?? []).filter(ts => ts > cutoff)
    if (recent.length >= cfg.maxEventsPerWindow) {
      this.cooldownUntil.set(chatId, now + cfg.cooldownMs)
      this.history.set(chatId, recent)
      return { allowed: false, reason: 'bot_loop_tripped' }
    }
    recent.push(now)
    this.history.set(chatId, recent)
    return { allowed: true }
  }

  reset(chatId?: string): void {
    if (chatId) {
      this.history.delete(chatId)
      this.cooldownUntil.delete(chatId)
    } else {
      this.history.clear()
      this.cooldownUntil.clear()
    }
  }
}

export function isExplicitlyMentioned(
  ctx: InboundContextLite,
  botUsername: string,
  extraPatterns?: string[],
): boolean {
  if (!botUsername) {return false}
  const entities = ctx.message?.entities ?? ctx.message?.caption_entities ?? []
  const text = ctx.message?.text ?? ctx.message?.caption ?? ''
  const targetAt = `@${botUsername}`.toLowerCase()
  const targetCmdSuffix = `@${botUsername}`.toLowerCase()

  for (const e of entities) {
    if (e.type === 'mention') {
      const mentioned = text.slice(e.offset, e.offset + e.length).toLowerCase()
      if (mentioned === targetAt) {return true}
    }
    if (e.type === 'bot_command') {
      const cmd = text.slice(e.offset, e.offset + e.length).toLowerCase()
      if (cmd.endsWith(targetCmdSuffix)) {return true}
    }
    if (e.type === 'text_mention' && e.user?.is_bot && e.user.username?.toLowerCase() === botUsername.toLowerCase()) {
      return true
    }
  }

  for (const pat of extraPatterns ?? []) {
    try {
      if (new RegExp(pat, 'i').test(text)) {return true}
    } catch {
      // ignore invalid regex
    }
  }
  return false
}

export function isMentionedOrReplied(
  ctx: InboundContextLite,
  botUsername: string,
  extraPatterns?: string[],
): boolean {
  if (isExplicitlyMentioned(ctx, botUsername, extraPatterns)) {return true}
  if (
    botUsername &&
    ctx.message?.reply_to_message?.from?.username?.toLowerCase() === botUsername.toLowerCase()
  ) {
    return true
  }
  return false
}

/**
 * Strict permission-reply check (Rùa Review Point 4):
 * ONLY a human user (`!is_bot`) in a private DM (`chat.type === 'private'`) who is in top-level `access.allowFrom`
 * can approve or deny tool permissions (`yes xxxxx` / `no xxxxx`).
 * Group messages or bot messages are NEVER treated as permission approvals.
 */
export function evaluatePermissionReply(
  ctx: InboundContextLite,
  access: Access,
  text: string,
): { isPermissionReply: boolean; requestId?: string; behavior?: 'allow' | 'deny'; blockedReason?: string } {
  const m = PERMISSION_REPLY_RE.exec(text)
  if (!m) {return { isPermissionReply: false }}

  if (!ctx.from || ctx.from.is_bot) {
    return { isPermissionReply: false, blockedReason: 'bot_cannot_approve_permission' }
  }
  if (ctx.chat?.type !== 'private') {
    return { isPermissionReply: false, blockedReason: 'group_chat_cannot_approve_permission' }
  }
  const senderId = String(ctx.from.id)
  if (!access.allowFrom.includes(senderId)) {
    return { isPermissionReply: false, blockedReason: 'sender_not_in_dm_allowFrom' }
  }

  return {
    isPermissionReply: true,
    requestId: m[2].toLowerCase(),
    behavior: m[1].toLowerCase().startsWith('y') ? 'allow' : 'deny',
  }
}

export function evaluateInboundGate(params: {
  ctx: InboundContextLite
  access: Access
  botUsername: string
  loopGuard: BotLoopGuard
  now?: number
}): GateVerdict {
  const { ctx, access, botUsername, loopGuard, now = Date.now() } = params

  if (access.dmPolicy === 'disabled') {
    return { action: 'drop', reason: 'dm_policy_disabled' }
  }
  const from = ctx.from
  if (!from) {
    return { action: 'drop', reason: 'missing_sender' }
  }
  if (botUsername && from.username?.toLowerCase() === botUsername.toLowerCase()) {
    return { action: 'drop', reason: 'self_echo' }
  }

  const senderId = String(from.id)
  const isBotSender = Boolean(from.is_bot)
  const chatType = ctx.chat?.type

  // 1. Private DM: Bots are NEVER allowed to DM or pair with the agent
  if (chatType === 'private') {
    if (isBotSender) {
      return { action: 'drop', reason: 'bot_dm_forbidden' }
    }
    if (access.allowFrom.includes(senderId)) {
      return { action: 'deliver', access, isBotSender: false }
    }
    if (access.dmPolicy === 'allowlist') {
      return { action: 'drop', reason: 'dm_not_in_allowlist' }
    }
    return { action: 'drop', reason: 'dm_unpaired' }
  }

  // 2. Group / Supergroup
  if (chatType === 'group' || chatType === 'supergroup') {
    const groupId = String(ctx.chat!.id)
    const policy = access.groups[groupId]
    if (!policy) {
      return { action: 'drop', reason: 'group_not_allowlisted' }
    }

    const groupAllowFrom = policy.allowFrom ?? []
    const requireMention = policy.requireMention ?? true
    const botsRequireMention = policy.botsRequireMention ?? true
    const allowBots = policy.allowBots ?? 'none'

    if (isBotSender) {
      if (allowBots === 'none') {
        return { action: 'drop', reason: 'group_bots_disabled_stage1' }
      }
      if (groupAllowFrom.length > 0 && !groupAllowFrom.includes(senderId)) {
        return { action: 'drop', reason: 'bot_sender_not_in_group_allowFrom' }
      }
      if (botsRequireMention || allowBots === 'mentions') {
        if (!isExplicitlyMentioned(ctx, botUsername)) {
          return { action: 'drop', reason: 'bot_sender_missing_explicit_mention' }
        }
      }
      const loopCheck = loopGuard.admit(groupId, now, access.botLoopGuard)
      if (!loopCheck.allowed) {
        return { action: 'drop', reason: loopCheck.reason ?? 'bot_loop_blocked' }
      }
      return { action: 'deliver', access, isBotSender: true }
    }

    // Human sender in group
    if (groupAllowFrom.length > 0 && !groupAllowFrom.includes(senderId)) {
      return { action: 'drop', reason: 'human_sender_not_in_group_allowFrom' }
    }
    if (requireMention && !isMentionedOrReplied(ctx, botUsername, policy.mentionPatterns ?? access.mentionPatterns)) {
      return { action: 'drop', reason: 'group_missing_mention' }
    }
    return { action: 'deliver', access, isBotSender: false }
  }

  return { action: 'drop', reason: 'unsupported_chat_type' }
}

/**
 * Codex-specific inbound gate (Claude PC Review Point 2):
 * ONLY non-bot human users listed in top-level `access.allowFrom` may invoke Codex,
 * even in Stage 2 when `groups[id].allowBots` is enabled for Claude.
 */
export function evaluateCodexInboundGate(params: {
  ctx: InboundContextLite
  access: Access
  botUsername: string
  loopGuard: BotLoopGuard
  now?: number
}): GateVerdict {
  const from = params.ctx.from
  if (!from) {
    return { action: 'drop', reason: 'missing_sender' }
  }
  if (from.is_bot) {
    return { action: 'drop', reason: 'codex_bot_callers_forbidden' }
  }
  if (!params.access.allowFrom.includes(String(from.id))) {
    return { action: 'drop', reason: 'codex_caller_not_in_human_allowFrom' }
  }
  return evaluateInboundGate(params)
}

/**
 * Build Codex CLI arguments with explicit `-c sandbox_mode="<mode>"` on BOTH `exec` and `exec resume`
 * so `exec resume` never falls back to `sandbox_mode="workspace-write"` from `~/.codex/config.toml`.
 */
export function buildCodexExecArgs(params: {
  existingThreadId?: string
  sandboxMode?: string
  workspaceDir: string
  outFile: string
  prompt: string
}): string[] {
  const mode = params.sandboxMode ?? 'read-only'
  const configOverride = `sandbox_mode="${mode}"`
  if (params.existingThreadId) {
    return [
      'exec',
      'resume',
      '-c',
      configOverride,
      '--json',
      '-o',
      params.outFile,
      params.existingThreadId,
      params.prompt,
    ]
  }
  return [
    'exec',
    '--json',
    '-s',
    mode,
    '-c',
    configOverride,
    '-C',
    params.workspaceDir,
    '-o',
    params.outFile,
    params.prompt,
  ]
}

/**
 * Redact secrets from outbound bot replies before `sendMessage`:
 * - PEM blocks / headers (`-----BEGIN...`)
 * - `sk-...` API keys
 * - `ghp_...` GitHub tokens
 * - `apify_api_...` Apify tokens
 * - Telegram bot tokens (`\d{8,10}:[A-Za-z0-9_-]{35}`)
 */
export function redactSensitiveOutput(text: string): string {
  return text
    .replace(/-----BEGIN [^-]+-----[\s\S]*?-----END [^-]+-----/g, '[REDACTED_PEM_BLOCK]')
    .replace(/-----BEGIN[^\n\r]*/g, '[REDACTED_PEM_HEADER]')
    .replace(/\bsk-[A-Za-z0-9_-]{6,}\b/g, '[REDACTED_SK_TOKEN]')
    .replace(/\bghp_[A-Za-z0-9_]{6,}\b/g, '[REDACTED_GHP_TOKEN]')
    .replace(/\bapify_api_[A-Za-z0-9_-]{6,}\b/g, '[REDACTED_APIFY_TOKEN]')
    .replace(/\b\d{8,10}:[A-Za-z0-9_-]{35}\b/g, '[REDACTED_TELEGRAM_BOT_TOKEN]')
}

/** Runtime metadata must describe the current access file, not the session's old stage. */
export function groupPolicyMeta(access: Access, chatId: string): Record<string, string> {
  const policy = access.groups[chatId]
  if (!policy) {return {allow_bots: 'none'}}
  return {
    allow_bots: policy.allowBots ?? 'none',
    bot_sender_requires_mention: String(policy.botsRequireMention ?? true),
  }
}

/** The group review channel is text-only; Read denials do not cover MCP file uploads. */
export function assertTextOnlyReply(files: readonly string[]): void {
  if (files.length) {throw new Error('collab attachments disabled: text-only review channel')}
}

/** A quoted Telegram message is context, never authority to approve an action. */
export function replyPointerMeta(ctx: InboundContextLite): Record<string, string> {
  const parent = ctx.message?.reply_to_message
  if (parent?.message_id == null) {return {}}
  return {
    reply_to_message_id: String(parent.message_id),
    reply_to_sender_is_bot: String(Boolean(parent.from?.is_bot)),
  }
}
