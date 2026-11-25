// ROOM-CHANGE-VOICE-20261109-01 Pha 2b: voice → local STT → wake decision (v1d).
// Orchestration only; Telegram/MCP/process I/O is injected so the handler wiring is testable.
import { routeTranscript } from './voice-route.ts'
import { effectFor, Seen, type Effect, type Outcome, type Verdict } from './voice-job.ts'
import { MAX_VOICE_SEC, TOLERANCE_SEC } from './voice-wav.ts'

// Repo public: ID lấy từ env do launcher đặt (access.json + voice-chat-id trong STATE_DIR). Thiếu → voice tắt (fail-closed).
export const VOICE_CHAT_ID = process.env.TELEGRAM_VOICE_CHAT_ID?.trim() || '__unset__'
export const VOICE_USER_ID = process.env.TELEGRAM_VOICE_USER_ID?.trim() || '__unset__'

export type VoiceInput = {
  chatId: string
  chatType?: string
  messageId: number
  senderId: string
  senderIsBot: boolean
  repliedToClaude: boolean
  duration?: number
}
export type SttResult = { ok: true; text: string } | { ok: false; code: 'too_long' | 'failed' | 'aborted' }
export type VoiceDeps = {
  flagOn(): boolean
  gate(): Verdict                                    // called at most once per voice
  passthrough(original?: Verdict): void              // pre-voice behaviour (handleInbound as before)
  stt(signal: AbortSignal): Promise<SttResult>
  accessStillOk(): boolean                           // fresh loadAccess(), pure check, no gate()
  dispatch(effect: Effect, transcript: string | null): void
  notice(code: 'too_long' | 'failed' | 'busy'): void // fixed sentence, rate-limited by caller
  log(ev: Record<string, unknown>): void             // metadata only, never transcript
}
export type PipelineOpts = { maxWaiting: number; maxWaitMs: number; jobMs: number; flagPollMs: number; graceMs: number; now: () => number }
const DEFAULTS: PipelineOpts = { maxWaiting: 3, maxWaitMs: 180_000, jobMs: 140_000, flagPollMs: 2_000, graceMs: 2_000, now: () => Date.now() }

// DM of Hưng with the bot (ROOM-CHANGE-VOICE-DM-20261125): chat_id of a private chat = user id.
export function isOwnerDm(v: VoiceInput): boolean {
  return v.chatType === 'private' && v.chatId === VOICE_USER_ID && v.senderId === VOICE_USER_ID
}

export function eligible(v: VoiceInput, flagOn: boolean): boolean {
  if (!flagOn || v.senderIsBot || v.senderId !== VOICE_USER_ID) return false
  if (isOwnerDm(v)) return true
  return v.chatId === VOICE_CHAT_ID && (v.chatType === 'group' || v.chatType === 'supergroup')
}

// Neutralise forged headers inside the transcript; words themselves are never changed ("cloud" stays).
export function sanitizeTranscript(t: string): string {
  return t.replace(/\s+/g, ' ').trim().replace(/\[voice_transcript/gi, '(voice_transcript').replace(/<\/?channel/gi, '(channel')
}

export class RateLimit {
  private last = new Map<string, number>()
  constructor(private windowMs = 10 * 60_000) {}
  allow(key: string, now = Date.now()): boolean {
    const t = this.last.get(key)
    if (t != null && now - t < this.windowMs) return false
    this.last.set(key, now)
    return true
  }
}

export class VoicePipeline {
  readonly seen = new Seen()
  private o: PipelineOpts
  private inflight = 0
  private tail: Promise<void> = Promise.resolve()
  constructor(opts: Partial<PipelineOpts> = {}) { this.o = { ...DEFAULTS, ...opts } }

  // Resolves when the voice is fully handled (tests await it; server fires and forgets).
  handle(v: VoiceInput, d: VoiceDeps): Promise<void> {
    if (!eligible(v, d.flagOn())) { d.passthrough(); return Promise.resolve() }
    if (!this.seen.firstTime(v.chatId, v.messageId)) { d.log({ stage: 'dedup' }); return Promise.resolve() }
    const original = d.gate()
    if (original.action === 'drop' && original.reason !== 'group_missing_mention') { d.passthrough(original); return Promise.resolve() }
    const finish = (out: Outcome, text: string | null) => this.finish(v, d, original, out, text)
    if (v.duration != null && v.duration > MAX_VOICE_SEC + TOLERANCE_SEC) { finish({ kind: 'stt_error', code: 'too_long' }, null); return Promise.resolve() }
    // In flight = 1 running + up to maxWaiting queued.
    if (this.inflight >= this.o.maxWaiting + 1) { finish({ kind: 'stt_error', code: 'busy' }, null); return Promise.resolve() }
    this.inflight++
    const enq = this.o.now()
    const job = this.tail.then(async () => {
      if (!d.flagOn()) return finish({ kind: 'cancelled_flag' }, null)
      if (this.o.now() - enq > this.o.maxWaitMs) return finish({ kind: 'stt_error', code: 'busy' }, null)
      const ac = new AbortController()
      let byFlag = false
      const timer = setTimeout(() => ac.abort(), this.o.jobMs)
      const poll = setInterval(() => { if (!d.flagOn()) { byFlag = true; ac.abort() } }, this.o.flagPollMs)
      let r: SttResult
      // Backstop: once aborted, stt gets graceMs to settle; after that the slot is released and
      // any late result is dropped (finish runs once per voice). Real cancellation is in voice-stt.
      let graceTimer: ReturnType<typeof setTimeout> | undefined
      const released = new Promise<SttResult>(res => ac.signal.addEventListener('abort',
        () => { graceTimer = setTimeout(() => res({ ok: false, code: 'aborted' }), this.o.graceMs) }, { once: true }))
      try { r = await Promise.race([d.stt(ac.signal), released]) } catch { r = { ok: false, code: 'failed' } }
      finally { clearTimeout(timer); clearInterval(poll); clearTimeout(graceTimer) }
      if (byFlag || !d.flagOn()) return finish({ kind: 'cancelled_flag' }, null)
      if (!r.ok) return finish({ kind: 'stt_error', code: r.code === 'too_long' ? 'too_long' : 'failed' }, null)
      const text = sanitizeTranscript(r.text)
      if (!text) return finish({ kind: 'stt_error', code: 'failed' }, null)
      // In the owner DM every voice is addressed to Claude; no name match needed.
      const wake = isOwnerDm(v) ? { wake: true as const, wake_reason: 'dm' as const } : routeTranscript(text, {
        repliedToClaude: v.repliedToClaude,
        captionMentionsClaude: original.action === 'deliver' && !v.repliedToClaude,
      })
      return finish({ kind: 'transcript', wake }, text)
    }).finally(() => { this.inflight-- })
    this.tail = job.catch(() => {})
    return job
  }

  private finish(v: VoiceInput, d: VoiceDeps, original: Verdict, out: Outcome, text: string | null): void {
    let e = effectFor(original, out, text ?? '')
    if (e.notifyModel && !d.accessStillOk()) e = { notifyModel: false, contextText: null, telegramNotice: null, wakeReason: null }
    d.log({ stage: 'done', outcome: out.kind, code: out.kind === 'stt_error' ? out.code : undefined,
      notify: e.notifyModel, wake_reason: e.wakeReason ?? undefined })
    if (e.notifyModel || e.contextText != null) d.dispatch(e, text)
    if (e.telegramNotice) d.notice(e.telegramNotice)
  }
}
