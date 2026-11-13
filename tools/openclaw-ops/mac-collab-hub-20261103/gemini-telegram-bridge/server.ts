#!/usr/bin/env bun
/**
 * Gemini Telegram Bridge for Mac Collaboration Hub (Antigravity CLI / Gemini)
 *
 * Bridges a dedicated Telegram bot (@hungreo_gemini_bot) to local Antigravity CLI (`~/.gemini/bin/agy`)
 * on Hưng's Mac, sharing the hardened `collab-gate.ts` security model:
 * - Powered by Hưng's Google / Gemini account on Mac (0đ API cost).
 * - Multi-turn memory via `agy --conversation <id>`.
 * - Sandboxed execution (`--sandbox --dangerously-skip-permissions`).
 * - Hardened group gate: mentions only, human-verified, botLoopGuard to prevent loops.
 * - Outbound redaction for keys, tokens, and secrets before `sendMessage`.
 */

import { execFileSync } from 'node:child_process'
import {
  chmodSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  renameSync,
  rmSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { Bot, InlineKeyboard, type Context } from 'grammy'
import type { ReactionTypeEmoji } from 'grammy/types'
import { formatChunks, isEntityParseError, stripMdv2 } from '../claude-telegram-plugin/telegram-format.ts'
import {
  BotLoopGuard,
  evaluateInboundGate,
  redactSensitiveOutput,
  type Access,
  type InboundContextLite,
} from '../lib/collab-gate.ts'
import { runXBriefPipeline } from '../x-brief-mac/runner.ts'
import { startXBriefScheduler } from '../x-brief-mac/scheduler.ts'
import { buildAgyArgs, resolveAgyTimeoutConfig, runAgyProcess, type AgyProcessResult } from './agy-runner.ts'
import { registerGeminiBotCommands } from './commands.ts'
import {
  ThreadStatsStore,
  formatContextStatusMessage,
  resolveQuotaPolicy,
  type ContextWarningAction,
} from './context-status.ts'
import {
  RecentTurnBuffer,
  buildTelegramInitialPrompt,
  executeAutoHandover,
  formatHandoverResultMessage,
  type HandoverTrigger,
} from './handover.ts'
import {
  ALBUM_DEBOUNCE_MS,
  MAX_ALBUM_PHOTOS,
  MediaGroupBatcher,
  extractImageSpec,
  formatMediaPrompt,
  mergeAlbumCaptions,
  pickAlbumRepresentative,
} from './media.ts'
import {
  MODEL_PRESETS,
  PendingPermissionStore,
  canAlwaysAllowRule,
  createEphemeralSettingsWithRule,
  derivePermissionCandidate,
  findModelPresetById,
  formatHardDenyNotice,
  formatPermissionDmMessage,
  grantPermissionRuleInFile,
  hasPermissionDenial,
  isRuleBlockedByDeny,
  resolveModelPreset,
  resolveTurnExecutionPolicy,
  type ModelPresetKey,
} from './permissions.ts'
import { formatClock, truncateSingleLine } from './stream-logger.ts'

const __dirname = dirname(fileURLToPath(import.meta.url))
const HUB_DIR = dirname(__dirname)

const STATE_DIR =
  process.env.GEMINI_TELEGRAM_STATE_DIR ??
  join(process.env.GEMINI_HOME ?? join(homedir(), '.gemini'), 'channels', 'telegram-collab')
const ACCESS_FILE = join(STATE_DIR, 'access.json')
const ENV_FILE = join(STATE_DIR, '.env')
const THREADS_FILE = join(STATE_DIR, 'threads.json')
const THREAD_STATS_FILE = join(STATE_DIR, 'thread-stats.json')
const HANDOVERS_DIR = join(STATE_DIR, 'handovers')
const EPHEMERAL_PERMS_DIR = join(STATE_DIR, 'tmp-perms')
const PID_FILE = join(STATE_DIR, 'bot.pid')
const QUOTA_POLICY = resolveQuotaPolicy(process.env)
const CONTEXT_WINDOW_TOKENS = QUOTA_POLICY.contextWindowTokens
const threadStatsStore = new ThreadStatsStore(THREAD_STATS_FILE)

const WORKSPACE_DIR = process.env.COLLAB_WORKSPACE_DIR ?? '/Users/hungdinh/Development/hungreo-openclaw'
const AGY_BIN = process.env.AGY_BIN ?? join(homedir(), '.gemini', 'bin', 'agy')
let currentModel = process.env.GEMINI_MODEL ?? 'gemini-4-hydrogen-high' // default fast & capable
const GEMINI_MODE = process.env.GEMINI_MODE ?? 'accept-edits'
const GEMINI_DANGEROUSLY_SKIP_PERMISSIONS = process.env.GEMINI_DANGEROUSLY_SKIP_PERMISSIONS === '1'
const DEFAULT_SETTINGS_FILE = join(HUB_DIR, 'gemini-collab-settings.json')
const GROUP_READONLY_SETTINGS_FILE = join(HUB_DIR, 'gemini-group-readonly-settings.json')
const X_BRIEF_READONLY_SETTINGS_FILE = join(HUB_DIR, 'x-brief-mac', 'editor-readonly-settings.json')
const GEMINI_SETTINGS_FILE =
  process.env.GEMINI_SETTINGS_FILE ?? (existsSync(DEFAULT_SETTINGS_FILE) ? DEFAULT_SETTINGS_FILE : '')
const READONLY_SETTINGS_FILE =
  process.env.GEMINI_READONLY_SETTINGS_FILE ??
  (existsSync(GROUP_READONLY_SETTINGS_FILE)
    ? GROUP_READONLY_SETTINGS_FILE
    : existsSync(X_BRIEF_READONLY_SETTINGS_FILE)
      ? X_BRIEF_READONLY_SETTINGS_FILE
      : '')
const INBOX_DIR = process.env.GEMINI_TELEGRAM_INBOX_DIR ?? '/tmp/gemini-telegram-inbox'

function logTimeline(tag: string, message: string): void {
  process.stdout.write(`[${formatClock()}] [${tag}] ${redactSensitiveOutput(message)}\n`)
}
const MAX_VOICE_SECONDS = 120 // 2 phút theo yêu cầu Hưng
const MAX_VOICE_BYTES = 10 * 1024 * 1024
const MAX_PHOTO_BYTES = 20 * 1024 * 1024
const INBOX_TTL_MS = 24 * 60 * 60 * 1000

try {
  chmodSync(ENV_FILE, 0o600)
  for (const line of readFileSync(ENV_FILE, 'utf8').split('\n')) {
    const m = line.match(/^(\w+)=(.*)$/)
    if (m && process.env[m[1]] === undefined) {
      process.env[m[1]] = m[2].trim()
    }
  }
} catch {}

const TOKEN = process.env.TELEGRAM_BOT_TOKEN
const TIMEOUTS = resolveAgyTimeoutConfig(process.env)
if (!TOKEN) {
  process.stderr.write(
    `gemini-telegram-bridge: TELEGRAM_BOT_TOKEN required\n` +
      `  set in ${ENV_FILE}\n` +
      `  format: TELEGRAM_BOT_TOKEN=123456789:AAH...\n`,
  )
  process.exit(1)
}

if (!existsSync(AGY_BIN)) {
  process.stderr.write(`gemini-telegram-bridge: Antigravity CLI not found at ${AGY_BIN}\n`)
  process.exit(1)
}

mkdirSync(STATE_DIR, { recursive: true, mode: 0o700 })
try {
  rmSync(EPHEMERAL_PERMS_DIR, { recursive: true, force: true })
} catch {}
try {
  const stale = parseInt(readFileSync(PID_FILE, 'utf8'), 10)
  if (stale > 1 && stale !== process.pid) {
    process.kill(stale, 0)
    const cmd = execFileSync('ps', ['-p', String(stale), '-o', 'args='], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    })
    if (cmd.includes('gemini-telegram-bridge')) {
      process.stderr.write(`gemini-telegram-bridge: replacing stale poller pid=${stale}\n`)
      process.kill(stale, 'SIGTERM')
    }
  }
} catch {}
writeFileSync(PID_FILE, String(process.pid), { mode: 0o600 })

function defaultAccess(): Access {
  return {
    dmPolicy: 'allowlist',
    allowFrom: [],
    groups: {},
    pending: {},
    ackReaction: '👀',
    replyToMode: 'first',
    textChunkLimit: 4000,
    chunkMode: 'newline',
    mentionPatterns: ['\\bgemini\\b', '\\bcả ba\\b', '\\b3 bot\\b', '\\bba bot\\b', '\\bcác bạn\\b'],
  }
}

function loadAccess(): Access {
  try {
    const parsed = JSON.parse(readFileSync(ACCESS_FILE, 'utf8')) as Partial<Access>
    return {
      dmPolicy: parsed.dmPolicy ?? 'allowlist',
      allowFrom: parsed.allowFrom ?? [],
      groups: parsed.groups ?? {},
      pending: parsed.pending ?? {},
      mentionPatterns: parsed.mentionPatterns ?? [
        '\\bgemini\\b',
        '\\bcả ba\\b',
        '\\b3 bot\\b',
        '\\bba bot\\b',
        '\\bcác bạn\\b',
      ],
      ackReaction: parsed.ackReaction ?? '👀',
      replyToMode: parsed.replyToMode ?? 'first',
      textChunkLimit: parsed.textChunkLimit ?? 4000,
      chunkMode: parsed.chunkMode ?? 'newline',
      botLoopGuard: parsed.botLoopGuard,
    }
  } catch {
    return defaultAccess()
  }
}

function loadThreads(): Record<string, string> {
  try {
    return JSON.parse(readFileSync(THREADS_FILE, 'utf8')) as Record<string, string>
  } catch {
    return {}
  }
}

function saveThreads(map: Record<string, string>): void {
  const tmp = `${THREADS_FILE}.tmp`
  writeFileSync(tmp, JSON.stringify(map, null, 2) + '\n', { mode: 0o600 })
  renameSync(tmp, THREADS_FILE)
}

function chunkText(text: string, limit = 4000): string[] {
  if (text.length <= limit) {
    return [text]
  }
  const out: string[] = []
  let rest = text
  while (rest.length > limit) {
    let idx = rest.lastIndexOf('\n', limit)
    if (idx < limit * 0.5) {
      idx = limit
    }
    out.push(rest.slice(0, idx))
    rest = rest.slice(idx).replace(/^\n+/, '')
  }
  if (rest) {
    out.push(rest)
  }
  return out
}

function pruneInbox(): void {
  try {
    mkdirSync(INBOX_DIR, { recursive: true, mode: 0o700 })
    const cutoff = Date.now() - INBOX_TTL_MS
    for (const name of readdirSync(INBOX_DIR)) {
      const fullPath = join(INBOX_DIR, name)
      try {
        const st = statSync(fullPath)
        if (st.isFile() && st.mtimeMs < cutoff) {
          unlinkSync(fullPath)
        }
      } catch {}
    }
  } catch {}
}

let downloadSeq = 0

async function downloadTelegramFile(params: {
  ctx: Context
  fileId: string
  fileUniqueId: string
  prefix: 'photo' | 'voice'
  fallbackExt: string
  maxBytes: number
}): Promise<string> {
  const file = await params.ctx.api.getFile(params.fileId)
  if (!file.file_path) {
    throw new Error('Telegram không trả về đường dẫn file')
  }
  if (file.file_size && file.file_size > params.maxBytes) {
    throw new Error(`File quá lớn (${(file.file_size / 1024 / 1024).toFixed(1)} MB)`)
  }

  const url = `https://api.telegram.org/file/bot${TOKEN}/${file.file_path}`
  let res: Response
  try {
    res = await fetch(url, { signal: AbortSignal.timeout(30_000) })
  } catch (err) {
    throw new Error(`Lỗi mạng khi tải file từ Telegram (${err instanceof Error ? err.name : 'fetch_error'})`, {
      cause: err,
    })
  }
  if (!res.ok) {
    throw new Error(`HTTP ${res.status} khi tải file từ Telegram`)
  }
  const buf = Buffer.from(await res.arrayBuffer())
  if (buf.byteLength > params.maxBytes) {
    throw new Error(`File vượt quá giới hạn ${(params.maxBytes / 1024 / 1024).toFixed(0)} MB`)
  }

  let ext = (file.file_path.split('.').pop() ?? params.fallbackExt).toLowerCase().replace(/[^a-z0-9]/g, '')
  if (!ext) {
    ext = params.fallbackExt
  }
  if (ext === 'oga') {
    ext = 'ogg'
  }

  const safeUid = params.fileUniqueId.replace(/[^a-zA-Z0-9_-]/g, '') || 'media'
  pruneInbox()
  const outPath = join(INBOX_DIR, `${params.prefix}-${Date.now()}-${downloadSeq++}-${safeUid}.${ext}`)
  writeFileSync(outPath, buf, { mode: 0o600 })
  logTimeline('Telegram', `📎 downloaded ${params.prefix} -> ${outPath} (${(buf.byteLength / 1024).toFixed(1)} KB)`)
  return outPath
}

type TelegramChatType = 'private' | 'group' | 'supergroup' | 'channel'

type GeminiTurnOutcome =
  | {
      kind: 'reply'
      reply: string
      conversationId?: string
      warningAction?: ContextWarningAction
      usagePct?: number
    }
  | { kind: 'denied'; result: AgyProcessResult; isReadOnly: boolean; settingsPathUsed?: string }

function invokeAgyPrompt(
  prompt: string,
  conversationId?: string,
  settingsPathOverride?: string,
  options?: { mode?: string; dangerouslySkipPermissions?: boolean },
): Promise<AgyProcessResult> {
  const args = buildAgyArgs({
    model: currentModel || undefined,
    conversationId,
    mode: options?.mode ?? GEMINI_MODE,
    settingsPath: settingsPathOverride ?? (GEMINI_SETTINGS_FILE || undefined),
    dangerouslySkipPermissions: options?.dangerouslySkipPermissions ?? GEMINI_DANGEROUSLY_SKIP_PERMISSIONS,
    prompt,
  })
  return runAgyProcess({
    agyBin: AGY_BIN,
    args,
    cwd: WORKSPACE_DIR,
    env: {
      ...process.env,
      PATH: `/Users/hungdinh/.gemini/bin:${process.env.PATH ?? ''}`,
    },
    timeouts: TIMEOUTS,
  })
}

async function runGeminiTurn(params: {
  chatId: string
  chatType?: TelegramChatType
  senderLabel: string
  isBotSender: boolean
  userText: string
  settingsPathOverride?: string
}): Promise<GeminiTurnOutcome> {
  const threads = loadThreads()
  const existingConvId = threads[params.chatId]

  const prompt = existingConvId
    ? `[${params.senderLabel}]: ${params.userText}`
    : buildTelegramInitialPrompt(params.senderLabel, params.userText)

  const policy = resolveTurnExecutionPolicy({
    chatType: params.chatType,
    isBotSender: params.isBotSender,
    defaultMode: GEMINI_MODE,
    defaultSettingsPath: GEMINI_SETTINGS_FILE || undefined,
    readonlySettingsPath: READONLY_SETTINGS_FILE || undefined,
    dangerouslySkipPermissions: GEMINI_DANGEROUSLY_SKIP_PERMISSIONS,
  })
  const effectiveSettingsPath =
    !policy.isReadOnly && params.settingsPathOverride ? params.settingsPathOverride : policy.settingsPath

  logTimeline(
    'Policy',
    `chat=${params.chatId} type=${params.chatType ?? 'unknown'} bot=${params.isBotSender} mode=${policy.mode} readonly=${policy.isReadOnly}`,
  )

  const res = await invokeAgyPrompt(prompt, existingConvId, effectiveSettingsPath, {
    mode: policy.mode,
    dangerouslySkipPermissions: policy.dangerouslySkipPermissions,
  })

  let reply = res.response
  const convId = res.conversationId
  const permissionDenied = hasPermissionDenial(res)
  let contextWarningText: string | undefined
  let warningAction: ContextWarningAction | undefined
  let usagePct: number | undefined

  if (convId && (reply || permissionDenied)) {
    const updated = loadThreads()
    updated[params.chatId] = convId
    saveThreads(updated)
    const { stats, warning } = threadStatsStore.recordTurn({
      chatId: params.chatId,
      conversationId: convId,
      modelId: currentModel,
      contextTokens: res.contextTokens,
      cumulativeTokens: res.totalTokens,
      durationSeconds: res.durationSeconds,
      contextWindowTokens: CONTEXT_WINDOW_TOKENS,
      thresholdsTokens: QUOTA_POLICY.warnTokenThresholds,
      autoHandoverTokens: QUOTA_POLICY.autoHandoverTokens,
    })
    if (warning.shouldWarn && warning.warningText) {
      contextWarningText = warning.warningText
      warningAction = warning.action
      usagePct = warning.usagePct
      logTimeline(
        'Context',
        `⚠️ chat=${params.chatId} action=${warning.action ?? 'button'} ctx=${stats.lastContextTokens ?? 0}/${QUOTA_POLICY.autoHandoverTokens} cum=${stats.lastCumulativeTokens ?? 0} (${warning.usagePct.toFixed(1)}% of 1M)`,
      )
    }
  } else if (!reply && existingConvId) {
    // Conversation bị kẹt hoặc lỗi -> xoá để phiên sau mở mới
    const updated = loadThreads()
    delete updated[params.chatId]
    saveThreads(updated)
    threadStatsStore.clear(params.chatId)
  }

  if (permissionDenied) {
    return {
      kind: 'denied',
      result: res,
      isReadOnly: policy.isReadOnly,
      settingsPathUsed: effectiveSettingsPath,
    }
  }

  if (!reply) {
    if (res.error) {
      throw new Error(res.error)
    }
    if (res.exitCode !== 0) {
      throw new Error(`agy exited with code ${res.exitCode}: ${res.stderr.slice(-300)}`)
    }
    reply = 'Dạ em chào anh! Em đã nhận được tin nhắn của anh. Anh cần em hỗ trợ gì cứ nhắn em nhé.'
  }

  const finalReply = contextWarningText ? `${reply}\n\n---\n${contextWarningText}` : reply
  return {
    kind: 'reply',
    reply: redactSensitiveOutput(finalReply),
    conversationId: convId,
    warningAction,
    usagePct,
  }
}

const bot = new Bot(TOKEN)
let botUsername = ''
const loopGuard = new BotLoopGuard()
const activeLocks = new Set<string>()
const pendingPermissions = new PendingPermissionStore()
const albumBatcher = new MediaGroupBatcher<Context>(ALBUM_DEBOUNCE_MS, MAX_ALBUM_PHOTOS)
const recentTurnBuffer = new RecentTurnBuffer(3, 600)
let xBriefRunning = false
let xBriefScheduler: { stop: () => void } | undefined

async function runAndDeliverXBrief(params: {
  mode: 'scheduled' | 'test'
  targetChatIds: readonly string[]
  replyToMsgId?: number
}): Promise<void> {
  if (xBriefRunning) {
    if (params.mode === 'test' && params.targetChatIds[0]) {
      await bot.api
        .sendMessage(params.targetChatIds[0], '⏳ Bản tin X Đối Chứng đang chạy, anh đợi chút nhé.')
        .catch(() => {})
    }
    return
  }

  xBriefRunning = true
  try {
    const res = await runXBriefPipeline({
      stateDir: STATE_DIR,
      mode: params.mode,
      runEditorPrompt: async prompt => {
        const readonlySettings = existsSync(X_BRIEF_READONLY_SETTINGS_FILE)
          ? X_BRIEF_READONLY_SETTINGS_FILE
          : GEMINI_SETTINGS_FILE || undefined
        const agyRes = await invokeAgyPrompt(prompt, undefined, readonlySettings, {
          mode: 'plan',
          dangerouslySkipPermissions: false,
        })
        if (hasPermissionDenial(agyRes)) {
          logTimeline('XBrief', '🛡️ blocked tool attempt during read-only X brief editorial step; falling back cleanly')
          return { ok: false, error: 'blocked_tool_attempt_in_readonly_editor' }
        }
        return agyRes.response
          ? { ok: true, text: agyRes.response }
          : { ok: false, error: agyRes.error ?? 'empty_response' }
      },
    })

    if (!res.ok) {
      const errMsg = `⚠️ **Bản tin X Đối Chứng (${params.mode}) chưa chạy được (${res.stage}):**\n${res.error}`
      for (const cid of params.targetChatIds) {
        await sendFormattedReply(cid, errMsg, 4000, params.replyToMsgId).catch(() => {})
      }
      if (params.mode === 'scheduled') {
        throw new Error(res.error)
      }
      return
    }

    if (res.skipped) {
      return
    }

    for (const cid of params.targetChatIds) {
      await sendFormattedReply(cid, res.message, 4000, params.replyToMsgId)
    }
    logTimeline(
      'XBrief',
      `📤 sent ${params.mode} brief (${res.items.length}/5, cost=$${res.costUsd.toFixed(4)}, ${res.durationSeconds.toFixed(1)}s)`,
    )
  } finally {
    xBriefRunning = false
  }
}

function buildAutoHandoverKeyboard(label = '🔄 Auto-Handover & Reset'): InlineKeyboard {
  return new InlineKeyboard().text(label, 'ghandover:run')
}

async function sendFormattedReply(
  chatId: string,
  answer: string,
  textChunkLimit = 4000,
  replyToMessageId?: number,
  replyMarkup?: InlineKeyboard,
): Promise<number> {
  const safeAnswer = redactSensitiveOutput(answer)
  const limit = Math.max(1, Math.min(textChunkLimit, 4096))
  let chunks: string[]
  let useMdv2 = true
  try {
    chunks = formatChunks(safeAnswer, limit, (text, sz) => chunkText(text, sz))
  } catch {
    chunks = chunkText(safeAnswer, limit)
    useMdv2 = false
  }
  for (let i = 0; i < chunks.length; i++) {
    const replyOpts = i === 0 && replyToMessageId ? { reply_parameters: { message_id: replyToMessageId } } : {}
    const markupOpts = i === chunks.length - 1 && replyMarkup ? { reply_markup: replyMarkup } : {}
    await bot.api
      .sendMessage(chatId, chunks[i], {
        ...replyOpts,
        ...markupOpts,
        ...(useMdv2 ? { parse_mode: 'MarkdownV2' as const } : {}),
      })
      .catch(err => {
        if (!useMdv2 || !isEntityParseError(err)) {
          throw err
        }
        return bot.api.sendMessage(chatId, stripMdv2(chunks[i]), { ...replyOpts, ...markupOpts })
      })
  }
  return chunks.length
}

async function performChatHandover(params: {
  chatId: string
  oldConversationId?: string
  trigger: HandoverTrigger
  access: Access
  replyToMsgId?: number
}): Promise<void> {
  const { chatId, trigger, access, replyToMsgId } = params
  const oldConversationId = params.oldConversationId ?? loadThreads()[chatId]
  const recentTurns = recentTurnBuffer.get(chatId)
  logTimeline('Handover', `🔄 start chat=${chatId} trigger=${trigger} conv=${oldConversationId?.slice(0, 8) ?? 'none'}`)

  const result = await executeAutoHandover({
    chatId,
    trigger,
    oldConversationId,
    modelId: currentModel,
    handoversDir: HANDOVERS_DIR,
    recentTurns,
    summarizeTurn: async (convId, prompt) => {
      const res = await invokeAgyPrompt(prompt, convId, READONLY_SETTINGS_FILE || undefined, {
        mode: 'plan',
        dangerouslySkipPermissions: false,
      })
      if (hasPermissionDenial(res) && !res.response) {
        return { ok: false, error: 'Bị chặn yêu cầu quyền công cụ khi tóm tắt' }
      }
      if (!res.response) {
        return {
          ok: false,
          error: res.error ?? (res.exitCode !== 0 ? `agy exit ${res.exitCode}` : 'Empty response'),
        }
      }
      return { ok: true, text: res.response }
    },
    seedNewTurn: async prompt => {
      const res = await invokeAgyPrompt(prompt, undefined, READONLY_SETTINGS_FILE || undefined, {
        mode: 'plan',
        dangerouslySkipPermissions: false,
      })
      if (hasPermissionDenial(res) && !res.conversationId) {
        return { ok: false, error: 'Bị chặn quyền công cụ khi mở phiên mới' }
      }
      if (!res.conversationId) {
        return {
          ok: false,
          error: res.error ?? (res.exitCode !== 0 ? `agy exit ${res.exitCode}` : 'Thiếu conversationId'),
        }
      }
      return {
        ok: true,
        conversationId: res.conversationId,
        reply: res.response,
        contextTokens: res.contextTokens,
        totalTokens: res.totalTokens,
        durationSeconds: res.durationSeconds,
      }
    },
    clearOldThreadState: cid => {
      const updated = loadThreads()
      delete updated[cid]
      saveThreads(updated)
      threadStatsStore.clear(cid)
      recentTurnBuffer.clear(cid)
    },
    commitNewThreadState: input => {
      const updated = loadThreads()
      updated[input.chatId] = input.conversationId
      saveThreads(updated)
      threadStatsStore.recordTurn({
        chatId: input.chatId,
        conversationId: input.conversationId,
        modelId: input.modelId,
        contextTokens: input.contextTokens,
        cumulativeTokens: input.totalTokens,
        durationSeconds: input.durationSeconds,
        contextWindowTokens: CONTEXT_WINDOW_TOKENS,
        thresholdsTokens: QUOTA_POLICY.warnTokenThresholds,
        autoHandoverTokens: QUOTA_POLICY.autoHandoverTokens,
      })
    },
  })

  if (result.ok) {
    logTimeline(
      'Handover',
      `✅ done chat=${chatId} ${result.oldConversationId.slice(0, 8)}->${result.newConversationId.slice(0, 8)} ctx=${result.newContextTokens ?? 0} cum=${result.newTokens ?? 0}`,
    )
  } else {
    logTimeline('Handover', `⚠️ failed chat=${chatId} stage=${result.stage}: ${result.error}`)
  }

  const msgText = formatHandoverResultMessage(result, CONTEXT_WINDOW_TOKENS)
  const retryMarkup =
    !result.ok && result.stage === 'summarize' ? buildAutoHandoverKeyboard('🔄 Thử lại Auto-Handover') : undefined
  await sendFormattedReply(chatId, msgText, access.textChunkLimit ?? 4000, replyToMsgId, retryMarkup)
}

function buildPermissionKeyboard(requestId: string, includeMore: boolean, includeAlways = true): InlineKeyboard {
  const kb = new InlineKeyboard()
  if (includeMore) {
    kb.text('🔍 See more', `gperm:more:${requestId}`)
  }
  kb.text('✅ Allow (1 lần)', `gperm:once:${requestId}`)
  if (includeMore) {
    kb.row()
  }
  if (includeAlways) {
    kb.text('🔓 Luôn cho phép', `gperm:always:${requestId}`)
  }
  return kb.text('❌ Deny', `gperm:deny:${requestId}`)
}

async function handleDeniedOutcome(params: {
  res: AgyProcessResult
  chatId: string
  msgId: number
  senderLabel: string
  isBotSender: boolean
  userText: string
  access: Access
  isReadOnly: boolean
  settingsPathUsed?: string
}): Promise<string> {
  const { res, chatId, msgId, senderLabel, isBotSender, userText, access, isReadOnly, settingsPathUsed } = params
  const derived = derivePermissionCandidate(res)
  if (!derived.ok) {
    logTimeline(
      'Permission',
      `🔒 hard-deny (${derived.blockedReason}) tool=${derived.toolName} input=${derived.rawInput ?? 'none'}`,
    )
    if (res.response) {
      return redactSensitiveOutput(res.response)
    }
    const reasonLabel =
      derived.blockedReason === 'shell_chain_not_allowed'
        ? 'lệnh ghép chuỗi/chuyển hướng shell không được phép duyệt tự động'
        : `không xác định được rule an toàn (${derived.blockedReason})`
    return formatHardDenyNotice({
      reason: reasonLabel,
      toolName: derived.toolName,
      rawInput: derived.rawInput ? redactSensitiveOutput(derived.rawInput) : undefined,
    })
  }

  const { candidate } = derived
  const effectiveSettingsForDeny = settingsPathUsed || GEMINI_SETTINGS_FILE
  const denyCheck = isRuleBlockedByDeny(effectiveSettingsForDeny, candidate.rule, candidate.rawInput)
  if (denyCheck.blocked) {
    logTimeline(
      'Permission',
      `🔒 blocked by deny (${denyCheck.matchedDeny ?? candidate.rule}) input=${candidate.rawInput ?? 'none'}`,
    )
    return formatHardDenyNotice({
      reason: `trùng danh sách cấm (\`permissions.deny\`: \`${denyCheck.matchedDeny ?? candidate.rule}\`)`,
      toolName: candidate.toolName,
      rawInput: candidate.rawInput ? redactSensitiveOutput(candidate.rawInput) : undefined,
    })
  }

  if (isReadOnly) {
    logTimeline('Permission', `🔒 readonly-mode blocked (${candidate.rule}) chat=${chatId} bot=${isBotSender}`)
    return formatHardDenyNotice({
      reason:
        'phòng chat nhóm / tin nhắn từ bot đang chạy ở chế độ chỉ đọc (`plan`), không cấp quyền ghi/chạy lệnh qua DM',
      toolName: candidate.toolName,
      rawInput: candidate.rawInput ? redactSensitiveOutput(candidate.rawInput) : undefined,
    })
  }

  if (access.allowFrom.length === 0) {
    const denied = res.deniedActions?.map(d => d.displayName ?? d.action ?? 'unknown').join(', ') ?? candidate.rule
    return `🛡️ Thao tác bị từ chối bởi chính sách an toàn headless (${denied}).`
  }

  const alwaysCheck = canAlwaysAllowRule(candidate.rule, candidate.rawInput)
  const canAlwaysAllow = alwaysCheck.allowed

  const entry = pendingPermissions.create({
    rule: candidate.rule,
    toolName: candidate.toolName,
    description: candidate.description,
    inputPreview: candidate.inputPreview,
    rawInput: candidate.rawInput,
    canAlwaysAllow,
    chatId,
    messageId: msgId,
    senderLabel,
    isBotSender,
    userText,
  })

  const keyboard = buildPermissionKeyboard(entry.requestId, true, canAlwaysAllow)

  const dmText = formatPermissionDmMessage({
    rule: entry.rule,
    senderLabel,
    chatId,
    rawInput: entry.rawInput,
    inputPreview: entry.inputPreview,
    canAlwaysAllow,
  })

  for (const dmChatId of access.allowFrom) {
    void bot.api.sendMessage(dmChatId, dmText, { reply_markup: keyboard }).catch(err => {
      process.stderr.write(`gemini permission_request send to ${dmChatId} failed: ${err}\n`)
    })
  }

  if (!canAlwaysAllow) {
    return `⏳ Cần cấp quyền 1 lần cho \`${candidate.rule}\` — đã gửi nút [✅ Allow (1 lần) / ❌ Deny] (kèm lệnh đầy đủ) vào DM của anh Hưng.`
  }
  return `⏳ Cần cấp quyền \`${candidate.rule}\` — đã gửi nút [✅ Allow (1 lần) / 🔓 Luôn cho phép / ❌ Deny] vào DM của anh Hưng.`
}

async function runLockedHandover(params: {
  chatId: string
  trigger: HandoverTrigger
  access: Access
  replyToMsgId?: number
  oldConversationId?: string
}): Promise<void> {
  const { chatId, trigger, access, replyToMsgId, oldConversationId } = params
  const typingTimer = setInterval(() => {
    void bot.api.sendChatAction(chatId, 'typing').catch(() => {})
  }, 4500)
  void bot.api.sendChatAction(chatId, 'typing').catch(() => {})
  try {
    await performChatHandover({ chatId, oldConversationId, trigger, access, replyToMsgId })
  } catch (err) {
    const msg = redactSensitiveOutput(err instanceof Error ? err.message : String(err))
    logTimeline('Handover', `⚠️ error chat=${chatId}: ${msg}`)
    await bot.api
      .sendMessage(
        chatId,
        `⚠️ Lỗi khi chạy Auto-Handover: ${msg}`,
        replyToMsgId ? { reply_parameters: { message_id: replyToMsgId } } : {},
      )
      .catch(() => {})
  } finally {
    clearInterval(typingTimer)
    activeLocks.delete(chatId)
  }
}

async function runLockedTurnAndDeliver(params: {
  chatId: string
  chatType?: TelegramChatType
  msgId: number
  senderLabel: string
  isBotSender: boolean
  access: Access
  userText: string
  settingsPathOverride?: string
}): Promise<void> {
  const { chatId, chatType, msgId, senderLabel, isBotSender, access, userText, settingsPathOverride } = params
  const startedAt = Date.now()
  const typingTimer = setInterval(() => {
    void bot.api.sendChatAction(chatId, 'typing').catch(() => {})
  }, 4500)
  void bot.api.sendChatAction(chatId, 'typing').catch(() => {})

  try {
    const outcome = await runGeminiTurn({
      chatId,
      chatType,
      senderLabel,
      isBotSender,
      userText,
      settingsPathOverride,
    })
    const finalReply =
      outcome.kind === 'reply'
        ? outcome.reply
        : await handleDeniedOutcome({
            res: outcome.result,
            chatId,
            msgId,
            senderLabel,
            isBotSender,
            userText,
            access,
            isReadOnly: outcome.isReadOnly,
            settingsPathUsed: outcome.settingsPathUsed,
          })
    const replyMarkup =
      outcome.kind === 'reply' && outcome.warningAction === 'button' ? buildAutoHandoverKeyboard() : undefined
    const chunkCount = await sendFormattedReply(chatId, finalReply, access.textChunkLimit ?? 4000, msgId, replyMarkup)
    const elapsedSec = ((Date.now() - startedAt) / 1000).toFixed(1)
    logTimeline('Telegram', `📤 sent ${chunkCount} chunk(s) to chat=${chatId} (Done in ${elapsedSec}s)`)

    if (outcome.kind === 'reply') {
      recentTurnBuffer.record(chatId, {
        senderLabel,
        userText,
        assistantReply: outcome.reply,
      })
    }

    if (outcome.kind === 'reply' && outcome.warningAction === 'auto' && outcome.conversationId) {
      await performChatHandover({
        chatId,
        oldConversationId: outcome.conversationId,
        trigger: 'auto',
        access,
        replyToMsgId: msgId,
      })
    }
  } catch (err) {
    const msg = redactSensitiveOutput(err instanceof Error ? err.message : String(err))
    const elapsedSec = ((Date.now() - startedAt) / 1000).toFixed(1)
    logTimeline('Telegram', `⚠️ error chat=${chatId} after ${elapsedSec}s: ${msg}`)
    await bot.api
      .sendMessage(chatId, `⚠️ Lỗi khi gọi Gemini (agy) trên Mac: ${msg}`, {
        reply_parameters: { message_id: msgId },
      })
      .catch(() => {})
  } finally {
    clearInterval(typingTimer)
    activeLocks.delete(chatId)
  }
}

async function executeGeminiTurnAndReply(params: {
  ctx: Context
  access: Access
  isBotSender: boolean
  buildUserText: () => Promise<string>
}): Promise<void> {
  const { ctx, access, isBotSender, buildUserText } = params
  const chatId = String(ctx.chat!.id)
  const chatType = ctx.chat?.type
  const msgId = ctx.message!.message_id
  const from = ctx.from!
  const senderLabel = from.username ? `@${from.username}` : String(from.id)

  if (activeLocks.has(chatId)) {
    await ctx.reply('⏳ Gemini đang xử lý lượt trước trong nhóm này, vui lòng đợi xong rồi gọi tiếp nhé.', {
      reply_parameters: { message_id: msgId },
    })
    return
  }

  activeLocks.add(chatId)
  const rawPreview = (ctx.message?.text ?? ctx.message?.caption ?? '').trim()
  const inboundKind = ctx.message?.voice
    ? `voice(${ctx.message.voice.duration}s)`
    : ctx.message?.media_group_id
      ? 'album'
      : extractImageSpec(ctx.message)
        ? 'photo'
        : 'text'
  logTimeline(
    'Telegram',
    `📩 chat=${chatId} from=${senderLabel} kind=${inboundKind}${rawPreview ? ` "${truncateSingleLine(rawPreview, 70)}"` : ''}`,
  )
  if (access.ackReaction) {
    void bot.api
      .setMessageReaction(chatId, msgId, [{ type: 'emoji', emoji: access.ackReaction as ReactionTypeEmoji['emoji'] }])
      .catch(() => {})
  }

  let finalUserText = ''
  try {
    finalUserText = await buildUserText()
  } catch (err) {
    activeLocks.delete(chatId)
    const msg = redactSensitiveOutput(err instanceof Error ? err.message : String(err))
    await bot.api
      .sendMessage(chatId, `⚠️ Lỗi xử lý đính kèm trước khi gọi Gemini: ${msg}`, {
        reply_parameters: { message_id: msgId },
      })
      .catch(() => {})
    return
  }

  await runLockedTurnAndDeliver({
    chatId,
    chatType,
    msgId,
    senderLabel,
    isBotSender,
    access,
    userText: finalUserText,
  })
}

async function handleAlbumBatch(items: Context[]): Promise<void> {
  if (items.length === 0) {
    return
  }
  const access = loadAccess()
  const repCtx = pickAlbumRepresentative(items)
  const verdict = evaluateInboundGate({
    ctx: repCtx as unknown as InboundContextLite,
    access,
    botUsername,
    loopGuard,
  })
  if (verdict.action !== 'deliver') {
    return
  }

  const rawText = mergeAlbumCaptions(items)
  await executeGeminiTurnAndReply({
    ctx: repCtx,
    access,
    isBotSender: verdict.isBotSender,
    buildUserText: async () => {
      const photoPaths: string[] = []
      for (const item of items.slice(0, MAX_ALBUM_PHOTOS)) {
        const spec = extractImageSpec(item.message)
        if (!spec) {
          continue
        }
        const path = await downloadTelegramFile({
          ctx: item,
          fileId: spec.fileId,
          fileUniqueId: spec.fileUniqueId,
          prefix: 'photo',
          fallbackExt: spec.fallbackExt,
          maxBytes: MAX_PHOTO_BYTES,
        })
        photoPaths.push(path)
      }
      if (photoPaths.length === 0) {
        throw new Error('Không tải được ảnh nào từ album')
      }
      return formatMediaPrompt({ rawText, photoPaths })
    },
  })
}

function buildModelKeyboard(activeModelId: string): InlineKeyboard {
  const activePreset = findModelPresetById(activeModelId)
  const labelFor = (key: ModelPresetKey): string => {
    const p = MODEL_PRESETS[key]
    return activePreset?.key === key ? `✓ ${p.shortLabel}` : p.shortLabel
  }
  return new InlineKeyboard()
    .text(labelFor('hydrogen'), 'gmodel:hydrogen')
    .text(labelFor('orchestrator'), 'gmodel:orchestrator')
    .row()
    .text(labelFor('argon'), 'gmodel:argon')
    .text(labelFor('flash'), 'gmodel:flash')
}

bot.command('model', async ctx => {
  const access = loadAccess()
  const senderId = String(ctx.from?.id ?? '')
  if (!ctx.from || ctx.from.is_bot || !access.allowFrom.includes(senderId)) {
    return
  }

  const arg = (ctx.match ?? '').trim()
  if (arg) {
    const preset = resolveModelPreset(arg)
    if (!preset) {
      await ctx.reply(`Model không hợp lệ: "${arg}". Các preset hỗ trợ: hydrogen, orchestrator, argon, flash.`)
      return
    }
    currentModel = preset.id
    logTimeline('Config', `🤖 switched model -> ${preset.label} (${preset.id})`)
    await ctx.reply(`🤖 Đã chuyển model của @hungreo_gemini_bot sang ${preset.label} (${preset.id}).`)
    return
  }

  const activePreset = findModelPresetById(currentModel)
  const activeLabel = activePreset ? `${activePreset.label} (${currentModel})` : currentModel
  await ctx.reply(`🤖 Model hiện tại: ${activeLabel}\nChọn model muốn chuyển:`, {
    reply_markup: buildModelKeyboard(currentModel),
  })
})

bot.command('status', async ctx => {
  const access = loadAccess()
  const senderId = String(ctx.from?.id ?? '')
  if (!ctx.from || ctx.from.is_bot || !access.allowFrom.includes(senderId)) {
    return
  }

  const chatId = String(ctx.chat.id)
  const threads = loadThreads()
  const conversationId = threads[chatId]
  const stats = threadStatsStore.get(chatId)
  const activePreset = findModelPresetById(currentModel)
  const currentModelLabel = activePreset ? activePreset.label : currentModel

  const statusText = formatContextStatusMessage({
    botUsername,
    currentModelId: currentModel,
    currentModelLabel,
    conversationId,
    contextWindowTokens: CONTEXT_WINDOW_TOKENS,
    warnStartTokens: QUOTA_POLICY.warnTokenThresholds[0],
    autoHandoverTokens: QUOTA_POLICY.autoHandoverTokens,
    stats,
  })
  await sendFormattedReply(chatId, statusText, access.textChunkLimit ?? 4000, ctx.message?.message_id)
})

bot.command('handover', async ctx => {
  const access = loadAccess()
  const senderId = String(ctx.from?.id ?? '')
  if (!ctx.from || ctx.from.is_bot || !access.allowFrom.includes(senderId)) {
    return
  }

  const chatId = String(ctx.chat.id)
  if (activeLocks.has(chatId)) {
    await ctx.reply('⏳ Gemini đang xử lý lượt trước trong phòng chat này, vui lòng đợi xong rồi gọi /handover nhé.')
    return
  }

  activeLocks.add(chatId)
  await runLockedHandover({
    chatId,
    trigger: 'command',
    access,
    replyToMsgId: ctx.message?.message_id,
  })
})

bot.command('reset_thread', async ctx => {
  const access = loadAccess()
  const senderId = String(ctx.from?.id ?? '')
  if (!ctx.from || ctx.from.is_bot || !access.allowFrom.includes(senderId)) {
    return
  }
  const chatId = String(ctx.chat.id)
  const threads = loadThreads()
  delete threads[chatId]
  saveThreads(threads)
  threadStatsStore.clear(chatId)
  recentTurnBuffer.clear(chatId)
  await ctx.reply('Đã xoá lịch sử conversation Gemini cho phòng chat này; lượt gọi tới sẽ mở phiên mới.')
})

bot.command('start', async ctx => {
  await ctx.reply('Xin chào anh Hưng! Mình là @hungreo_gemini_bot chạy trên Antigravity (Gemini) trên Mac.')
})

bot.command('x_brief', async ctx => {
  const access = loadAccess()
  const senderId = String(ctx.from?.id ?? '')
  if (!ctx.from || ctx.from.is_bot || !access.allowFrom.includes(senderId)) {
    return
  }

  const chatId = String(ctx.chat.id)
  if (xBriefRunning) {
    await ctx.reply(
      '⏳ Bản tin X Đối Chứng đang chạy, anh đợi chút nhé.',
      ctx.message?.message_id ? { reply_parameters: { message_id: ctx.message.message_id } } : {},
    )
    return
  }

  await ctx.reply(
    '🔎 Đang thu thập & biên tập Bản tin X Đối Chứng (Apify + Gemini Mac)...',
    ctx.message?.message_id ? { reply_parameters: { message_id: ctx.message.message_id } } : {},
  )
  void runAndDeliverXBrief({
    mode: 'test',
    targetChatIds: [chatId],
    replyToMsgId: ctx.message?.message_id,
  })
})

bot.on('callback_query:data', async ctx => {
  const data = ctx.callbackQuery.data
  const access = loadAccess()
  const senderId = String(ctx.from.id)

  const modelMatch = /^gmodel:(hydrogen|orchestrator|argon|flash)$/.exec(data)
  if (modelMatch) {
    if (ctx.from.is_bot || !access.allowFrom.includes(senderId)) {
      await ctx.answerCallbackQuery({ text: 'Not authorized.' }).catch(() => {})
      return
    }
    const preset = MODEL_PRESETS[modelMatch[1] as ModelPresetKey]
    currentModel = preset.id
    logTimeline('Config', `🤖 switched model -> ${preset.label} (${preset.id})`)
    await ctx.answerCallbackQuery({ text: `Đã chọn ${preset.shortLabel}` }).catch(() => {})
    await ctx
      .editMessageText(`🤖 Model hiện tại: ${preset.label} (${preset.id})\nChọn model muốn chuyển:`, {
        reply_markup: buildModelKeyboard(currentModel),
      })
      .catch(() => {})
    return
  }

  if (data === 'ghandover:run') {
    if (ctx.from.is_bot || !access.allowFrom.includes(senderId)) {
      await ctx.answerCallbackQuery({ text: 'Not authorized.' }).catch(() => {})
      return
    }
    const chatId = ctx.chat ? String(ctx.chat.id) : ''
    if (!chatId) {
      await ctx.answerCallbackQuery({ text: 'Không xác định được phòng chat.' }).catch(() => {})
      return
    }
    if (activeLocks.has(chatId)) {
      await ctx.answerCallbackQuery({ text: 'Phòng chat đang xử lý lượt khác, thử lại sau giây lát.' }).catch(() => {})
      return
    }
    activeLocks.add(chatId)
    await ctx.answerCallbackQuery({ text: '🔄 Đang chốt handover & mở phiên mới...' }).catch(() => {})
    await ctx.editMessageReplyMarkup({ reply_markup: { inline_keyboard: [] } }).catch(() => {})
    void runLockedHandover({
      chatId,
      trigger: 'button',
      access,
      replyToMsgId: ctx.callbackQuery.message?.message_id,
    })
    return
  }

  const permMatch = /^gperm:(once|always|deny|more):([a-km-z]{5})$/.exec(data)
  if (!permMatch) {
    await ctx.answerCallbackQuery().catch(() => {})
    return
  }

  if (ctx.from.is_bot || ctx.chat?.type !== 'private' || !access.allowFrom.includes(senderId)) {
    await ctx.answerCallbackQuery({ text: 'Not authorized (private human DM only).' }).catch(() => {})
    return
  }

  const [, behavior, requestId] = permMatch
  const entry = pendingPermissions.get(requestId)
  if (!entry) {
    await ctx.answerCallbackQuery({ text: 'Yêu cầu đã hết hạn hoặc đã được xử lý.' }).catch(() => {})
    return
  }

  if (behavior === 'more') {
    let prettyInput = entry.inputPreview
    try {
      prettyInput = JSON.stringify(JSON.parse(entry.inputPreview), null, 2)
    } catch {}
    const safeDesc = redactSensitiveOutput(entry.description)
    const safeInput = redactSensitiveOutput(prettyInput)
    const safeUserText = redactSensitiveOutput(truncateSingleLine(entry.userText, 240))
    const expanded =
      `🔐 Permission (Gemini): ${entry.rule}\n\n` +
      `tool_name: ${entry.toolName}\n` +
      `rule: ${entry.rule}\n` +
      `caller: ${entry.senderLabel} (chat ${entry.chatId})\n` +
      `description: ${safeDesc}\n` +
      `input_preview:\n${safeInput}\n` +
      `prompt: ${safeUserText}`
    const allowAlways = entry.canAlwaysAllow ?? canAlwaysAllowRule(entry.rule, entry.rawInput).allowed
    const keyboard = buildPermissionKeyboard(requestId, false, allowAlways)
    await ctx.editMessageText(expanded.slice(0, 3900), { reply_markup: keyboard }).catch(() => {})
    await ctx.answerCallbackQuery().catch(() => {})
    return
  }

  const msg = ctx.callbackQuery.message
  const baseText = msg && 'text' in msg && msg.text ? msg.text : `🔐 Permission (Gemini): ${entry.rule}`

  if (behavior === 'deny') {
    pendingPermissions.delete(requestId)
    await ctx.answerCallbackQuery({ text: '❌ Denied' }).catch(() => {})
    await ctx.editMessageText(`${baseText}\n\n❌ Denied`).catch(() => {})
    if (entry.chatId !== String(ctx.chat.id)) {
      void bot.api
        .sendMessage(entry.chatId, `❌ Anh Hưng đã từ chối cấp quyền \`${entry.rule}\`.`, {
          reply_parameters: { message_id: entry.messageId },
        })
        .catch(() => {})
    }
    return
  }

  if (activeLocks.has(entry.chatId)) {
    await ctx.answerCallbackQuery({ text: 'Phòng chat đang xử lý lượt khác, thử lại sau giây lát.' }).catch(() => {})
    return
  }

  const replayChatType: TelegramChatType = entry.chatId.startsWith('-') ? 'group' : 'private'

  if (behavior === 'once') {
    const ephem = createEphemeralSettingsWithRule({
      settingsPath: GEMINI_SETTINGS_FILE,
      tempDir: EPHEMERAL_PERMS_DIR,
      requestId: requestId,
      rule: entry.rule,
      rawInput: entry.rawInput,
    })
    pendingPermissions.delete(requestId)
    if (!ephem.ok) {
      await ctx.answerCallbackQuery({ text: '🔒 Bị chặn bởi deny list' }).catch(() => {})
      await ctx.editMessageText(`${baseText}\n\n🔒 Blocked (${ephem.reason})`).catch(() => {})
      return
    }

    logTimeline('Permission', `⏱️ granted ONCE ${entry.rule} for chat=${entry.chatId}`)
    await ctx.answerCallbackQuery({ text: '✅ Allow 1 lần — đang chạy lại' }).catch(() => {})
    await ctx
      .editMessageText(
        `${baseText}\n\n✅ Allow (1 lần): ${entry.rule}\n⏳ Đang chạy lại yêu cầu (không lưu vào settings)...`,
      )
      .catch(() => {})

    activeLocks.add(entry.chatId)
    void runLockedTurnAndDeliver({
      chatId: entry.chatId,
      chatType: replayChatType,
      msgId: entry.messageId,
      senderLabel: entry.senderLabel,
      isBotSender: entry.isBotSender,
      access,
      userText: entry.userText,
      settingsPathOverride: ephem.tempSettingsPath,
    }).finally(ephem.cleanup)
    return
  }

  // behavior === 'always'
  const alwaysCheck =
    entry.canAlwaysAllow === false
      ? { allowed: false, reason: 'interpreter_or_shell_once_only' }
      : canAlwaysAllowRule(entry.rule, entry.rawInput)
  if (!alwaysCheck.allowed) {
    pendingPermissions.delete(requestId)
    await ctx.answerCallbackQuery({ text: '🔒 Shell/interpreter chỉ hỗ trợ Allow (1 lần)' }).catch(() => {})
    await ctx
      .editMessageText(`${baseText}\n\n🔒 Blocked (${alwaysCheck.reason ?? 'always_allow_forbidden'})`)
      .catch(() => {})
    return
  }

  const grantRes = grantPermissionRuleInFile(GEMINI_SETTINGS_FILE, entry.rule, entry.rawInput)
  pendingPermissions.delete(requestId)
  if (!grantRes.ok) {
    await ctx.answerCallbackQuery({ text: '🔒 Bị chặn bởi deny list' }).catch(() => {})
    await ctx.editMessageText(`${baseText}\n\n🔒 Blocked (${grantRes.reason})`).catch(() => {})
    return
  }

  logTimeline('Permission', `🔓 granted ALWAYS ${entry.rule} for chat=${entry.chatId}`)
  await ctx.answerCallbackQuery({ text: '🔓 Luôn cho phép — đang chạy lại' }).catch(() => {})
  await ctx
    .editMessageText(
      `${baseText}\n\n🔓 Luôn cho phép (đã lưu vào settings): ${entry.rule}\n⏳ Đang chạy lại yêu cầu...`,
    )
    .catch(() => {})

  activeLocks.add(entry.chatId)
  void runLockedTurnAndDeliver({
    chatId: entry.chatId,
    chatType: replayChatType,
    msgId: entry.messageId,
    senderLabel: entry.senderLabel,
    isBotSender: entry.isBotSender,
    access,
    userText: entry.userText,
  })
})

bot.on(['message:text', 'message:photo', 'message:voice', 'message:document'], async ctx => {
  const imageSpec = extractImageSpec(ctx.message)
  if (ctx.message.document && !imageSpec) {
    return
  }

  if (ctx.message.media_group_id && imageSpec) {
    if (!ctx.from || !ctx.chat) {
      return
    }
    const key = `${ctx.chat.id}:${ctx.from.id}:${ctx.message.media_group_id}`
    albumBatcher.enqueue(key, ctx, items => {
      void handleAlbumBatch(items)
    })
    return
  }

  const access = loadAccess()
  const verdict = evaluateInboundGate({
    ctx: ctx as unknown as InboundContextLite,
    access,
    botUsername,
    loopGuard,
  })
  if (verdict.action !== 'deliver') {
    return
  }

  const msgId = ctx.message.message_id
  const rawText = (ctx.message.text ?? ctx.message.caption ?? '').trim()
  const voice = ctx.message.voice

  if (voice) {
    if (voice.duration > MAX_VOICE_SECONDS) {
      await ctx.reply(
        `🎙️ Voice dài ${voice.duration}s (vượt giới hạn tối đa ${MAX_VOICE_SECONDS}s / 2 phút). Anh gửi ngắn lại hoặc gõ text giúp em nhé!`,
        { reply_parameters: { message_id: msgId } },
      )
      return
    }
    if (voice.file_size && voice.file_size > MAX_VOICE_BYTES) {
      await ctx.reply('🎙️ File voice quá lớn (> 10 MB). Anh gửi ngắn lại giúp em nhé!', {
        reply_parameters: { message_id: msgId },
      })
      return
    }
  } else if (!imageSpec && !rawText) {
    return
  }

  await executeGeminiTurnAndReply({
    ctx,
    access,
    isBotSender: verdict.isBotSender,
    buildUserText: async () => {
      if (voice) {
        const voicePath = await downloadTelegramFile({
          ctx,
          fileId: voice.file_id,
          fileUniqueId: voice.file_unique_id,
          prefix: 'voice',
          fallbackExt: 'ogg',
          maxBytes: MAX_VOICE_BYTES,
        })
        return formatMediaPrompt({
          rawText,
          voicePath,
          voiceDuration: voice.duration,
        })
      }
      if (imageSpec) {
        const photoPath = await downloadTelegramFile({
          ctx,
          fileId: imageSpec.fileId,
          fileUniqueId: imageSpec.fileUniqueId,
          prefix: 'photo',
          fallbackExt: imageSpec.fallbackExt,
          maxBytes: MAX_PHOTO_BYTES,
        })
        return formatMediaPrompt({
          rawText,
          photoPaths: [photoPath],
        })
      }
      return rawText
    },
  })
})

let shuttingDown = false
function shutdown(): void {
  if (shuttingDown) {
    return
  }
  shuttingDown = true
  xBriefScheduler?.stop()
  albumBatcher.clearAll()
  try {
    if (parseInt(readFileSync(PID_FILE, 'utf8'), 10) === process.pid) {
      rmSync(PID_FILE)
    }
  } catch {}
  setTimeout(() => process.exit(0), 2000)
  void Promise.resolve(bot.stop()).finally(() => process.exit(0))
}
process.on('SIGTERM', shutdown)
process.on('SIGINT', shutdown)
process.on('SIGHUP', shutdown)

bot.catch(err => {
  process.stderr.write(`gemini-telegram-bridge: handler error: ${String(err.error)}\n`)
})

void (async () => {
  await bot.start({
    onStart: info => {
      botUsername = info.username
      const modeLabel = GEMINI_DANGEROUSLY_SKIP_PERMISSIONS ? 'dangerously-skip-permissions' : GEMINI_MODE
      const settingsLabel = GEMINI_SETTINGS_FILE || 'none'
      process.stdout.write(
        `[Gemini Collab Bridge] Polling as @${info.username} (workspace=${WORKSPACE_DIR}, model=${currentModel}, mode=${modeLabel}, settings=${settingsLabel}, idleTimeout=${Math.round(TIMEOUTS.idleTimeoutMs / 1000)}s, maxTimeout=${Math.round(TIMEOUTS.maxTimeoutMs / 1000)}s)\n`,
      )
      void registerGeminiBotCommands(bot.api, err => {
        const msg = redactSensitiveOutput(err instanceof Error ? err.message : String(err))
        logTimeline('Telegram', `⚠️ setMyCommands failed: ${msg}`)
      })
      xBriefScheduler = startXBriefScheduler({
        statePath: join(STATE_DIR, 'x-brief', 'schedule-state.json'),
        targetHour: 6,
        targetMinute: 30,
        log: msg => logTimeline('XBrief', msg),
        onTrigger: async () => {
          const access = loadAccess()
          if (access.allowFrom.length === 0) {
            return
          }
          await runAndDeliverXBrief({
            mode: 'scheduled',
            targetChatIds: access.allowFrom,
          })
        },
      })
    },
  })
})()
