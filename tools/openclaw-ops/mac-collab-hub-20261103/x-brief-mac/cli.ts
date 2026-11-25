#!/usr/bin/env bun
import { existsSync, readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { buildAgyArgs, resolveAgyTimeoutConfig, runAgyProcess } from '../gemini-telegram-bridge/agy-runner.ts'
import { hasPermissionDenial } from '../gemini-telegram-bridge/permissions.ts'
import { formatChunks, stripMdv2 } from '../claude-telegram-plugin/telegram-format.ts'
import { redactSensitiveOutput } from '../lib/collab-gate.ts'
import { runXBriefPipeline } from './runner.ts'
import type { XBriefMode } from './types.ts'

const __dirname = dirname(fileURLToPath(import.meta.url))
const HUB_DIR = dirname(__dirname)
const STATE_DIR =
  process.env.GEMINI_TELEGRAM_STATE_DIR ??
  join(process.env.GEMINI_HOME ?? join(homedir(), '.gemini'), 'channels', 'telegram-collab')
const ENV_FILE = join(STATE_DIR, '.env')
const ACCESS_FILE = join(STATE_DIR, 'access.json')

try {
  for (const line of readFileSync(ENV_FILE, 'utf8').split('\n')) {
    const m = line.match(/^(\w+)=(.*)$/)
    if (m && process.env[m[1]] === undefined) {process.env[m[1]] = m[2].trim()}
  }
} catch {}

function parseArgs(argv: readonly string[]): { mode: XBriefMode; send: boolean; noAgy: boolean } {
  let mode: XBriefMode = 'test'
  let send = false
  let noAgy = false
  for (const arg of argv) {
    if (arg === '--scheduled') {mode = 'scheduled'}
    else if (arg === '--dry-run') {mode = 'dry-run'}
    else if (arg === '--test') {mode = 'test'}
    else if (arg === '--send') {send = true}
    else if (arg === '--no-agy') {noAgy = true}
  }
  return { mode, send, noAgy }
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

async function sendTelegramDM(text: string): Promise<void> {
  const token = process.env.TELEGRAM_BOT_TOKEN?.trim()
  if (!token) {throw new Error('Thiếu TELEGRAM_BOT_TOKEN để gửi Telegram.')}
  if (!existsSync(ACCESS_FILE)) {throw new Error(`Không tìm thấy ${ACCESS_FILE}`)}
  const access = JSON.parse(readFileSync(ACCESS_FILE, 'utf8')) as { allowFrom?: string[] }
  const targets = access.allowFrom ?? []
  if (targets.length === 0) {throw new Error('access.json chưa có allowFrom để gửi DM.')}

  const chunks = formatChunks(redactSensitiveOutput(text), 4000, chunkText)
  for (const chatId of targets) {
    for (const chunk of chunks) {
      const res = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          chat_id: chatId,
          text: chunk,
          parse_mode: 'MarkdownV2',
        }),
      })
      if (!res.ok) {
        const fallback = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ chat_id: chatId, text: stripMdv2(chunk) }),
        })
        if (!fallback.ok) {
          throw new Error(`Telegram sendMessage failed (${fallback.status})`)
        }
      }
    }
  }
}

async function main(): Promise<void> {
  const { mode, send, noAgy } = parseArgs(process.argv.slice(2))
  const agyBin = process.env.AGY_BIN ?? join(homedir(), '.gemini', 'bin', 'agy')
  const readonlySettingsFile = join(__dirname, 'editor-readonly-settings.json')
  const fallbackSettingsFile = join(HUB_DIR, 'gemini-collab-settings.json')
  const settingsFile = existsSync(readonlySettingsFile) ? readonlySettingsFile : fallbackSettingsFile
  const workspaceDir = process.env.COLLAB_WORKSPACE_DIR ?? '/Users/hungdinh/Development/hungreo-openclaw'
  const model = process.env.X_BRIEF_MODEL ?? process.env.GEMINI_MODEL ?? 'gemini-4-hydrogen-high'

  const runEditorPrompt =
    !noAgy && existsSync(agyBin)
      ? async (prompt: string) => {
          const args = buildAgyArgs({
            model,
            mode: 'plan',
            dangerouslySkipPermissions: false,
            settingsPath: existsSync(settingsFile) ? settingsFile : undefined,
            prompt,
          })
          const res = await runAgyProcess({
            agyBin,
            args,
            cwd: workspaceDir,
            env: {
              ...process.env,
              PATH: `${join(homedir(), '.gemini', 'bin')}:${process.env.PATH ?? ''}`,
            },
            timeouts: resolveAgyTimeoutConfig(process.env),
          })
          if (hasPermissionDenial(res)) {
            return { ok: false, error: 'blocked_tool_attempt_in_readonly_editor' }
          }
          return res.response ? { ok: true, text: res.response } : { ok: false, error: res.error }
        }
      : undefined

  const result = await runXBriefPipeline({
    stateDir: STATE_DIR,
    mode,
    runEditorPrompt,
  })

  if (!result.ok) {
    process.stderr.write(`❌ [x-brief-mac] (${result.stage}): ${result.error}\n`)
    process.exit(1)
  }

  if (result.skipped) {
    process.stdout.write(`ℹ️ ${result.skipReason}\n`)
    return
  }

  process.stdout.write(`${result.message}\n`)
  if (send) {
    await sendTelegramDM(result.message)
    process.stdout.write(`📤 Đã gửi bản tin về Telegram DM.\n`)
  }
}

void main()
