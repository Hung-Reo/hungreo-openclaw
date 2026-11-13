// Pure decision helpers for the job lifecycle (prototype v1d).
// v1d vs v1c: transcript outcome carries a Wake (not a Route); the 'uncertain' notice is gone;
// Effect carries wakeReason; voiceMeta builds the notification meta. Everything else unchanged.
import type { Wake } from './voice-route.ts'
export type Verdict = { action: 'deliver' } | { action: 'drop'; reason: string }
export type Outcome =
  | { kind: 'transcript'; wake: Wake }
  | { kind: 'stt_error'; code: 'too_long' | 'failed' | 'busy' }
  | { kind: 'cancelled_flag' }
export type Effect = {
  notifyModel: boolean            // mcp notification to Claude session
  contextText: string | null      // what room context stores (via prepare with a DROP decision when not waking)
  telegramNotice: null | 'too_long' | 'failed' | 'busy'
  wakeReason: string | null
}
// precomputed DELIVER may only replace the missing-mention drop; every other drop stands.
export function overrideVerdict(original: Verdict, wake: boolean): Verdict {
  if (original.action === 'drop' && original.reason !== 'group_missing_mention') {return original}
  return wake ? { action: 'deliver' } : { action: 'drop', reason: 'group_missing_mention' }
}
export function effectFor(original: Verdict, out: Outcome, text = ''): Effect {
  if (original.action === 'drop' && original.reason !== 'group_missing_mention')
    {return { notifyModel: false, contextText: null, telegramNotice: null, wakeReason: null }}
  if (out.kind === 'cancelled_flag') {return { notifyModel: false, contextText: '(voice message)', telegramNotice: null, wakeReason: null }}
  if (out.kind === 'stt_error') {return { notifyModel: false, contextText: '(voice message)', telegramNotice: out.code, wakeReason: null }}
  const notify = overrideVerdict(original, out.wake.wake).action === 'deliver'
  return {
    notifyModel: notify,
    contextText: text,              // verbatim transcript, never rewritten
    telegramNotice: null,
    wakeReason: notify ? out.wake.wake_reason : null,
  }
}
// Meta sent with the notification. The transcript is data, never a GO.
export function voiceMeta(a: { senderId: string; chatId: string; messageId: number; transcript: string; wakeReason: string }) {
  return {
    kind: 'voice_transcript',
    sender_id: a.senderId,
    chat_id: a.chatId,
    message_id: String(a.messageId),
    transcript: a.transcript,
    wake_reason: a.wakeReason,
  }
}
// Dedup by chat_id+message_id BEFORE enqueue (bounded, TTL).
export class Seen {
  private m = new Map<string, number>()
  constructor(private ttlMs = 3_600_000, private max = 500) {}
  firstTime(chatId: string, messageId: number, now = Date.now()): boolean {
    for (const [k, t] of this.m) {if (now - t >= this.ttlMs) this.m.delete(k)}
    const k = `${chatId}:${messageId}`
    if (this.m.has(k)) {return false}
    if (this.m.size >= this.max) {this.m.delete(this.m.keys().next().value!)}
    this.m.set(k, now)
    return true
  }
}
