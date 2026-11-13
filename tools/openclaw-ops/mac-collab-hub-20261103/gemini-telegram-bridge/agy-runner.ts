import { spawn, type ChildProcess } from 'node:child_process'
import { redactSensitiveOutput } from '../lib/collab-gate.ts'
import { AgyStreamParser, formatClock, type AgyStreamResult } from './stream-logger.ts'

export const DEFAULT_MAX_TIMEOUT_MS = 900_000 // 15 minutes for large multi-step tasks
export const DEFAULT_IDLE_TIMEOUT_MS = 300_000 // 5 minutes of inactivity before killing hung process
export const DEFAULT_KILL_GRACE_MS = 5_000

export type AgyTimeoutConfig = {
  maxTimeoutMs: number
  idleTimeoutMs: number
  killGraceMs: number
}

export type AgyProcessResult = AgyStreamResult & {
  exitCode: number | null
  stderr: string
}

export type SpawnFn = typeof spawn

function parseTimeoutMs(
  raw: string | undefined,
  fallbackMs: number,
  options: { allowZero?: boolean } = {},
): number {
  if (raw === undefined || raw.trim() === '') {return fallbackMs}
  const parsed = Number(raw.trim())
  if (!Number.isFinite(parsed)) {return fallbackMs}
  if (parsed === 0 && options.allowZero) {return 0}
  if (parsed <= 0) {return fallbackMs}
  return Math.floor(parsed)
}

/**
 * Resolves two-tier execution timeouts from environment variables.
 * `GEMINI_MAX_TIMEOUT_MS` (or `GEMINI_TIMEOUT_MS`) caps total turn duration;
 * `GEMINI_IDLE_TIMEOUT_MS` resets on every stream output chunk and catches frozen processes.
 */
export function resolveAgyTimeoutConfig(env: Record<string, string | undefined> = process.env): AgyTimeoutConfig {
  const maxTimeoutMs = parseTimeoutMs(env.GEMINI_MAX_TIMEOUT_MS ?? env.GEMINI_TIMEOUT_MS, DEFAULT_MAX_TIMEOUT_MS)
  const rawIdle = parseTimeoutMs(env.GEMINI_IDLE_TIMEOUT_MS, DEFAULT_IDLE_TIMEOUT_MS, { allowZero: true })
  const idleTimeoutMs = rawIdle > 0 ? Math.min(rawIdle, maxTimeoutMs) : 0
  const killGraceMs = parseTimeoutMs(env.GEMINI_KILL_GRACE_MS, DEFAULT_KILL_GRACE_MS)
  return { maxTimeoutMs, idleTimeoutMs, killGraceMs }
}

/**
 * Builds CLI arguments for `agy` in non-interactive `stream-json` mode.
 */
export function buildAgyArgs(params: {
  model?: string
  conversationId?: string
  mode?: string
  settingsPath?: string
  dangerouslySkipPermissions?: boolean
  prompt: string
}): string[] {
  const args: string[] = [
    '--output-format',
    'stream-json',
    '--sandbox',
  ]
  if (params.dangerouslySkipPermissions) {
    args.push('--dangerously-skip-permissions')
  } else {
    args.push('--mode', params.mode || 'accept-edits')
  }
  if (params.settingsPath) {args.push('--settings', params.settingsPath)}
  if (params.model) {args.push('--model', params.model)}
  if (params.conversationId) {args.push('--conversation', params.conversationId)}
  args.push('-p', params.prompt)
  return args
}

function terminateChild(child: ChildProcess, killGraceMs: number): void {
  try {
    child.kill('SIGTERM')
  } catch {}
  const forceTimer = setTimeout(() => {
    try {
      child.kill('SIGKILL')
    } catch {}
  }, killGraceMs)
  forceTimer.unref?.()
}

/**
 * Spawns `agy`, streams NDJSON progress to `log`, and enforces idle + max timeouts.
 */
export function runAgyProcess(params: {
  agyBin: string
  args: string[]
  cwd: string
  env: Record<string, string | undefined>
  timeouts?: AgyTimeoutConfig
  log?: (line: string) => void
  spawnFn?: SpawnFn
}): Promise<AgyProcessResult> {
  const timeouts = params.timeouts ?? resolveAgyTimeoutConfig(params.env)
  const log = params.log ?? ((line: string) => process.stdout.write(`${line}\n`))
  const spawnImpl = params.spawnFn ?? spawn

  return new Promise<AgyProcessResult>((resolve, reject) => {
    const child = spawnImpl(params.agyBin, params.args, {
      cwd: params.cwd,
      env: params.env as NodeJS.ProcessEnv,
      stdio: ['ignore', 'pipe', 'pipe'],
    })

    let stderrBuf = ''
    let settled = false
    let maxTimer: ReturnType<typeof setTimeout> | undefined
    let idleTimer: ReturnType<typeof setTimeout> | undefined

    const clearTimers = (): void => {
      if (maxTimer) {clearTimeout(maxTimer)}
      if (idleTimer) {clearTimeout(idleTimer)}
    }

    const fail = (err: Error): void => {
      if (settled) {return}
      settled = true
      clearTimers()
      reject(err)
    }

    const resetIdleTimer = (): void => {
      if (settled || timeouts.idleTimeoutMs <= 0) {return}
      if (idleTimer) {clearTimeout(idleTimer)}
      idleTimer = setTimeout(() => {
        terminateChild(child, timeouts.killGraceMs)
        const sec = Math.round(timeouts.idleTimeoutMs / 1000)
        fail(new Error(`Gemini agy execution timed out after ${sec}s of inactivity (idle timeout)`))
      }, timeouts.idleTimeoutMs)
    }

    maxTimer = setTimeout(() => {
      terminateChild(child, timeouts.killGraceMs)
      const sec = Math.round(timeouts.maxTimeoutMs / 1000)
      fail(new Error(`Gemini agy execution exceeded max timeout (${sec}s)`))
    }, timeouts.maxTimeoutMs)
    resetIdleTimer()

    const emitLog = (line: string): void => {
      log(redactSensitiveOutput(line))
    }

    const parser = new AgyStreamParser({
      onInit: info => {
        const model = info.model ?? 'default'
        const mode = info.permissionMode ?? 'default'
        emitLog(`[${formatClock()}] [Gemini] init model=${model} permission=${mode}`)
      },
      onToolStart: (toolName, detail) => {
        const suffix = detail ? ` ${detail}` : ''
        emitLog(`[${formatClock()}] [Gemini] ▶ ${toolName}${suffix}`)
      },
      onToolDone: (toolName, dur) => {
        const durText = typeof dur === 'number' ? ` (${dur.toFixed(2)}s)` : ''
        emitLog(`[${formatClock()}] [Gemini] ✓ ${toolName}${durText}`)
      },
      onToolError: (toolName, msg, dur) => {
        const durText = typeof dur === 'number' ? ` (${dur.toFixed(2)}s)` : ''
        emitLog(`[${formatClock()}] [Gemini] ✗ ${toolName}${durText}: ${msg}`)
      },
      onResult: res => {
        const parts = [`status=${res.status || 'DONE'}`]
        if (typeof res.durationSeconds === 'number') {parts.push(`dur=${res.durationSeconds.toFixed(1)}s`)}
        if (typeof res.numTurns === 'number') {parts.push(`turns=${res.numTurns}`)}
        if (typeof res.totalTokens === 'number') {parts.push(`tokens=${res.totalTokens}`)}
        if (res.deniedActions?.length) {
          parts.push(`denied=${res.deniedActions.map(d => d.action ?? d.displayName ?? 'unknown').join(',')}`)
        }
        emitLog(`[${formatClock()}] [Gemini] ✅ ${parts.join(' ')}`)
      },
    })

    child.stdout?.on('data', chunk => {
      resetIdleTimer()
      parser.feed(String(chunk))
    })

    child.stderr?.on('data', chunk => {
      resetIdleTimer()
      stderrBuf += String(chunk)
      if (stderrBuf.length > 8192) {
        stderrBuf = stderrBuf.slice(-8192)
      }
    })

    child.on('error', err => {
      fail(err instanceof Error ? err : new Error(String(err)))
    })

    child.on('close', exitCode => {
      if (settled) {return}
      settled = true
      clearTimers()
      const parsed = parser.finish()
      resolve({
        ...parsed,
        exitCode,
        stderr: stderrBuf,
      })
    })
  })
}
