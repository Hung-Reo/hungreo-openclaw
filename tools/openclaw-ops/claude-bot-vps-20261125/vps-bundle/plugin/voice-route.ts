// Prototype v1d. Pure: no I/O, no side effects.
// Rule (Hưng GO, group tin 439): wake Claude when the transcript contains Claude or a
// sound-alike ANYWHERE (word boundary, case-insensitive, NFC), or the voice replies to
// Claude, or the caption mentions Claude. No negation, no "uncertain": Claude reads the
// verbatim transcript and decides itself whether it was addressed. The transcript is
// never rewritten (Hermes delta tin 441): "cloud" stays "cloud".
export type WakeReason = `name_match:${string}` | 'reply_to_claude' | 'caption' | 'dm'
export type Wake = { wake: true; wake_reason: WakeReason } | { wake: false; wake_reason: null }
export type Envelope = { repliedToClaude: boolean; captionMentionsClaude: boolean }

// Longest first so "claude" wins over "claud"/"clau". "close" dropped (common English word).
export const NAME_LIST = ['claude', 'klaude', 'claud', 'cloud', 'clau', 'klaus', 'cờ lốt', 'cờ lau']
  .map(s => s.normalize('NFC'))
const NAME_RE = new RegExp(
  `(?<![\\p{L}\\p{N}])(${NAME_LIST.map(n => n.replace(/ /g, '\\s+')).join('|')})(?![\\p{L}\\p{N}])`,
  'u',
)

export function routeTranscript(raw: string, env: Envelope): Wake {
  const t = raw.normalize('NFC').toLowerCase()
  const m = t.match(NAME_RE)
  if (m) return { wake: true, wake_reason: `name_match:${m[1].replace(/\s+/g, ' ')}` }
  if (env.repliedToClaude) return { wake: true, wake_reason: 'reply_to_claude' }
  if (env.captionMentionsClaude) return { wake: true, wake_reason: 'caption' }
  return { wake: false, wake_reason: null }
}
