// Local STT for one voice: capped download → ffmpeg wav 16k → duration check → whisper-cli -l vi.
// No network except the Telegram file download. Child processes are killed as a group on abort.
import { spawn } from 'child_process'
import { mkdtempSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'fs'
import { join } from 'path'
import { tooLong, wavDurationSec } from './voice-wav.ts'
import type { SttResult } from './voice-pipeline.ts'

export const MAX_VOICE_BYTES = 2 * 1024 * 1024
export const FFMPEG = '/opt/homebrew/bin/ffmpeg'
export const WHISPER = '/opt/homebrew/bin/whisper-cli'
export const STEP_MS = { download: 15_000, ffmpeg: 10_000, whisper: 60_000 }

class StepError extends Error {  }

function linked(signal: AbortSignal, ms: number): AbortSignal {
  return AbortSignal.any([signal, AbortSignal.timeout(ms)])
}

// Settle as soon as `signal` aborts even if `p` ignores it (backstop; the real request is
// cancelled by passing the same signal into it). A late result is discarded.
function untilAbort<T>(p: Promise<T>, signal: AbortSignal): Promise<T> {
  if (signal.aborted) { p.catch(() => {}); return Promise.reject(new StepError('aborted')) }
  return new Promise<T>((resolve, reject) => {
    const onAbort = () => reject(new StepError('aborted'))
    signal.addEventListener('abort', onAbort, { once: true })
    p.then(v => { signal.removeEventListener('abort', onAbort); resolve(v) },
      () => { signal.removeEventListener('abort', onAbort); reject(new StepError(signal.aborted ? 'aborted' : 'failed')) })
  })
}

export async function fetchCapped(url: string, maxBytes: number, signal: AbortSignal): Promise<Uint8Array> {
  let res: Response
  try { res = await fetch(url, { signal }) } catch { throw new StepError(signal.aborted ? 'aborted' : 'failed') }
  if (!res.ok || !res.body) {throw new StepError('failed')}
  const declared = Number(res.headers.get('content-length') ?? '0')
  if (declared > maxBytes) { void res.body.cancel().catch(() => {}); throw new StepError('too_long') }
  const parts: Uint8Array[] = []
  let n = 0
  const reader = res.body.getReader()
  try {
    for (;;) {
      const { done, value } = await reader.read()
      if (done) {break}
      n += value.byteLength
      if (n > maxBytes) { void reader.cancel().catch(() => {}); throw new StepError('too_long') }
      parts.push(value)
    }
  } catch (e) {
    if (e instanceof StepError) {throw e}
    throw new StepError(signal.aborted ? 'aborted' : 'failed')
  }
  const out = new Uint8Array(n)
  let off = 0
  for (const p of parts) { out.set(p, off); off += p.byteLength }
  return out
}

export function run(cmd: string, args: string[], signal: AbortSignal, maxOut = 64 * 1024): Promise<string> {
  return new Promise((resolve, reject) => {
    if (signal.aborted) {return reject(new StepError('aborted'))}
    const child = spawn(cmd, args, { detached: true, stdio: ['ignore', 'pipe', 'ignore'] })
    let out = ''
    const kill = () => { try { process.kill(-child.pid!, 'SIGKILL') } catch {} }
    signal.addEventListener('abort', kill, { once: true })
    child.stdout.on('data', (b: Buffer) => { if (out.length < maxOut) {out += b.toString('utf8')} })
    child.on('error', () => { signal.removeEventListener('abort', kill); reject(new StepError('failed')) })
    child.on('close', code => {
      signal.removeEventListener('abort', kill)
      if (signal.aborted) {reject(new StepError('aborted'))}
      else if (code === 0) {resolve(out)}
      else {reject(new StepError('failed'))}
    })
  })
}

export function cleanTmpRoot(tmpRoot: string): void {
  mkdirSync(tmpRoot, { recursive: true, mode: 0o700 })
  for (const f of readdirSync(tmpRoot)) {rmSync(join(tmpRoot, f), { recursive: true, force: true })}
}

export async function sttVoice(a: {
  // Resolves the Telegram download URL (contains token: never log). MUST pass `signal`
  // to the real request (bot.api.getFile(file_id, signal)); it carries the download deadline.
  fileUrl: (signal: AbortSignal) => Promise<string>
  signal: AbortSignal
  tmpRoot: string
  model: string
  ffmpeg?: string
  whisper?: string
  stepMs?: Partial<typeof STEP_MS>  // tests only
}): Promise<SttResult> {
  const ms = { ...STEP_MS, ...a.stepMs }
  mkdirSync(a.tmpRoot, { recursive: true, mode: 0o700 })
  const dir = mkdtempSync(join(a.tmpRoot, 'job-'))
  try {
    // One deadline covers getFile + file download; it is also linked to the job/flag abort.
    const dl = linked(a.signal, ms.download)
    let url: string
    try { url = await untilAbort(a.fileUrl(dl), dl) } catch (e) { throw e instanceof StepError ? e : new StepError('failed') }
    if (dl.aborted) {throw new StepError('aborted')}
    const ogg = await fetchCapped(url, MAX_VOICE_BYTES, dl)
    const inPath = join(dir, 'in.oga'), wavPath = join(dir, 'in.wav')
    writeFileSync(inPath, ogg, { mode: 0o600 })
    await run(a.ffmpeg ?? FFMPEG, ['-v', 'error', '-nostdin', '-y', '-i', inPath, '-t', '125', '-ar', '16000', '-ac', '1', '-c:a', 'pcm_s16le', wavPath],
      linked(a.signal, ms.ffmpeg))
    let sec: number
    try { sec = wavDurationSec(readFileSync(wavPath)) } catch { throw new StepError('failed') }
    if (tooLong(sec)) {throw new StepError('too_long')}
    const text = await run(a.whisper ?? WHISPER, ['-m', a.model, '-f', wavPath, '-l', 'vi', '-nt', '-np'],
      linked(a.signal, ms.whisper))
    return { ok: true, text }
  } catch (e) {
    return { ok: false, code: e instanceof StepError ? e.code : 'failed' }
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
}
