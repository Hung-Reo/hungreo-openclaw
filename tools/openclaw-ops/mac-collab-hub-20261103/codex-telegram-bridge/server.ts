#!/usr/bin/env bun
/**
 * Codex Telegram Bridge for Mac Collaboration Hub (Read-Only Default)
 *
 * Bridges a dedicated Telegram bot to local Codex CLI (`codex exec -s read-only -c sandbox_mode="read-only"`)
 * on Hưng's Mac, sharing the hardened `collab-gate.ts` security model:
 * - Only human users in `access.allowFrom` can invoke Codex (bots are blocked even in Stage 2).
 * - Both `exec` and `exec resume` enforce `-c sandbox_mode="read-only"`.
 * - Outbound messages are redacted for `-----BEGIN`, `sk-`, `ghp_`, and Telegram bot tokens before `sendMessage`.
 */

import { Bot, type Context } from 'grammy'
import type { ReactionTypeEmoji } from 'grammy/types'
import { chmodSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { execFileSync, spawn } from 'node:child_process'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  BotLoopGuard,
  buildCodexExecArgs,
  evaluateCodexInboundGate,
  redactSensitiveOutput,
  type Access,
  type InboundContextLite,
} from '../lib/collab-gate.ts'

const __dirname = dirname(fileURLToPath(import.meta.url))
const HUB_DIR = dirname(__dirname)
const PROTOCOL_FILE = join(HUB_DIR, 'COLLAB_PROTOCOL.md')

const STATE_DIR =
  process.env.CODEX_TELEGRAM_STATE_DIR ??
  join(process.env.CODEX_HOME ?? join(homedir(), '.codex'), 'channels', 'telegram-collab')
const ACCESS_FILE = join(STATE_DIR, 'access.json')
const ENV_FILE = join(STATE_DIR, '.env')
const THREADS_FILE = join(STATE_DIR, 'threads.json')
const PID_FILE = join(STATE_DIR, 'bot.pid')

const WORKSPACE_DIR = process.env.COLLAB_WORKSPACE_DIR ?? '/Users/hungdinh/Development/hungreo-openclaw'
const CODEX_BIN =
  process.env.CODEX_BIN ??
  '/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex'
const SANDBOX_MODE = process.env.CODEX_SANDBOX_MODE ?? 'read-only'

try {
  chmodSync(ENV_FILE, 0o600)
  for (const line of readFileSync(ENV_FILE, 'utf8').split('\n')) {
    const m = line.match(/^(\w+)=(.*)$/)
    if (m && process.env[m[1]] === undefined) {process.env[m[1]] = m[2].trim()}
  }
} catch {}

const TOKEN = process.env.TELEGRAM_BOT_TOKEN
if (!TOKEN) {
  process.stderr.write(
    `codex-telegram-bridge: TELEGRAM_BOT_TOKEN required\n` +
      `  set in ${ENV_FILE}\n` +
      `  or run: bash tools/openclaw-ops/mac-collab-hub-20261103/10_setup_access.sh\n`,
  )
  process.exit(1)
}

mkdirSync(STATE_DIR, { recursive: true, mode: 0o700 })
try {
  const stale = parseInt(readFileSync(PID_FILE, 'utf8'), 10)
  if (stale > 1 && stale !== process.pid) {
    process.kill(stale, 0)
    const cmd = execFileSync('ps', ['-p', String(stale), '-o', 'args='], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    })
    if (cmd.includes('codex-telegram-bridge')) {
      process.stderr.write(`codex-telegram-bridge: replacing stale poller pid=${stale}\n`)
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
      mentionPatterns: parsed.mentionPatterns,
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
  if (text.length <= limit) {return [text]}
  const out: string[] = []
  let rest = text
  while (rest.length > limit) {
    let idx = rest.lastIndexOf('\n', limit)
    if (idx < limit * 0.5) {idx = limit}
    out.push(rest.slice(0, idx))
    rest = rest.slice(idx).replace(/^\n+/, '')
  }
  if (rest) {out.push(rest)}
  return out
}

async function runCodexReview(params: {
  chatId: string
  senderLabel: string
  isBotSender: boolean
  userText: string
}): Promise<string> {
  const protocol = existsSync(PROTOCOL_FILE) ? readFileSync(PROTOCOL_FILE, 'utf8') : ''
  const outFile = join(tmpdir(), `codex-collab-reply-${process.pid}-${Date.now()}.txt`)
  const threads = loadThreads()
  const existingThreadId = threads[params.chatId]

  const prompt = [
    `[Telegram Collaboration Context]`,
    `- Workspace: ${WORKSPACE_DIR}`,
    `- Mode: ${SANDBOX_MODE} (Review/Verify only unless Hung explicitly authorizes implementation)`,
    `- Sender: ${params.senderLabel} (is_bot=${params.isBotSender})`,
    protocol ? `\n${protocol}\n` : '',
    `[Inbound Message]\n${params.userText}`,
  ].join('\n')

  const args = buildCodexExecArgs({
    existingThreadId,
    sandboxMode: SANDBOX_MODE,
    workspaceDir: WORKSPACE_DIR,
    outFile,
    prompt,
  })

  return new Promise((resolve, reject) => {
    const child = spawn(CODEX_BIN, args, {
      cwd: WORKSPACE_DIR,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: { ...process.env },
    })

    let stdoutBuf = ''
    let stderrBuf = ''
    const timer = setTimeout(() => {
      child.kill('SIGTERM')
      reject(new Error('Codex execution timed out after 240s'))
    }, 240_000)

    child.stdout.on('data', chunk => {
      stdoutBuf += String(chunk)
    })
    child.stderr.on('data', chunk => {
      stderrBuf += String(chunk)
    })

    child.on('error', err => {
      clearTimeout(timer)
      reject(err)
    })

    child.on('close', code => {
      clearTimeout(timer)
      // Extract thread_id from JSONL if started a new thread
      for (const line of stdoutBuf.split('\n')) {
        if (!line.trim().startsWith('{')) {continue}
        try {
          const ev = JSON.parse(line)
          if (ev.type === 'thread.started' && typeof ev.thread_id === 'string') {
            const updated = loadThreads()
            updated[params.chatId] = ev.thread_id
            saveThreads(updated)
          }
        } catch {}
      }

      let reply = ''
      try {
        if (existsSync(outFile)) {
          reply = readFileSync(outFile, 'utf8').trim()
          rmSync(outFile, { force: true })
        }
      } catch {}

      if (code !== 0 && !reply) {
        // If resuming a stale thread failed, clear stored thread id
        if (existingThreadId) {
          const updated = loadThreads()
          delete updated[params.chatId]
          saveThreads(updated)
        }
        reject(new Error(`codex exited with code ${code}: ${stderrBuf.slice(-400)}`))
        return
      }
      resolve(redactSensitiveOutput(reply || '(Codex hoàn tất nhưng không có nội dung văn bản trả về)'))
    })
  })
}

const bot = new Bot(TOKEN)
let botUsername = ''
const loopGuard = new BotLoopGuard()
const activeLocks = new Set<string>()

bot.command('reset_thread', async ctx => {
  const access = loadAccess()
  const senderId = String(ctx.from?.id ?? '')
  if (!ctx.from || ctx.from.is_bot || !access.allowFrom.includes(senderId)) {return}
  const chatId = String(ctx.chat.id)
  const threads = loadThreads()
  delete threads[chatId]
  saveThreads(threads)
  await ctx.reply('Đã xoá lịch sử thread Codex cho phòng chat này; lượt gọi tới sẽ mở phiên mới.')
})

bot.on('message:text', async ctx => {
  const access = loadAccess()
  const verdict = evaluateCodexInboundGate({
    ctx: ctx as unknown as InboundContextLite,
    access,
    botUsername,
    loopGuard,
  })
  if (verdict.action !== 'deliver') {return}

  const chatId = String(ctx.chat.id)
  const msgId = ctx.message.message_id
  const from = ctx.from
  const senderLabel = from.username ? `@${from.username}` : String(from.id)

  if (activeLocks.has(chatId)) {
    await ctx.reply('⏳ Codex đang xử lý lượt trước trong nhóm này, vui lòng đợi xong rồi gọi tiếp nhé.', {
      reply_parameters: { message_id: msgId },
    })
    return
  }

  activeLocks.add(chatId)
  if (access.ackReaction) {
    void bot.api
      .setMessageReaction(chatId, msgId, [
        { type: 'emoji', emoji: access.ackReaction as ReactionTypeEmoji['emoji'] },
      ])
      .catch(() => {})
  }

  const typingTimer = setInterval(() => {
    void bot.api.sendChatAction(chatId, 'typing').catch(() => {})
  }, 4500)
  void bot.api.sendChatAction(chatId, 'typing').catch(() => {})

  try {
    const answer = await runCodexReview({
      chatId,
      senderLabel,
      isBotSender: verdict.isBotSender,
      userText: ctx.message.text,
    })
    const safeAnswer = redactSensitiveOutput(answer)
    const chunks = chunkText(safeAnswer, access.textChunkLimit ?? 4000)
    for (let i = 0; i < chunks.length; i++) {
      await bot.api.sendMessage(chatId, chunks[i], (i === 0 ? { reply_parameters: { message_id: msgId } } : {}))
    }
  } catch (err) {
    const msg = redactSensitiveOutput(err instanceof Error ? err.message : String(err))
    await bot.api
      .sendMessage(chatId, `⚠️ Lỗi khi gọi Codex trên Mac: ${msg}`, {
        reply_parameters: { message_id: msgId },
      })
      .catch(() => {})
  } finally {
    clearInterval(typingTimer)
    activeLocks.delete(chatId)
  }
})

let shuttingDown = false
function shutdown(): void {
  if (shuttingDown) {return}
  shuttingDown = true
  try {
    if (parseInt(readFileSync(PID_FILE, 'utf8'), 10) === process.pid) {rmSync(PID_FILE)}
  } catch {}
  setTimeout(() => process.exit(0), 2000)
  void Promise.resolve(bot.stop()).finally(() => process.exit(0))
}
process.on('SIGTERM', shutdown)
process.on('SIGINT', shutdown)
process.on('SIGHUP', shutdown)

bot.catch(err => {
  process.stderr.write(`codex-telegram-bridge: handler error: ${err.error}\n`)
})

void (async () => {
  await bot.start({
    onStart: info => {
      botUsername = info.username
      process.stdout.write(
        `[Codex Collab Bridge] Polling as @${info.username} (workspace=${WORKSPACE_DIR}, sandbox=${SANDBOX_MODE})\n`,
      )
    },
  })
})()
