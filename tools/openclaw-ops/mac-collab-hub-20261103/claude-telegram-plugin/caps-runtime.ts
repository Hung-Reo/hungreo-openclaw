// CLAUDE-BOT-CAPS-20261112: runtime helpers for the patched Telegram channel plugin.
// 1) Owner trust marker -> read by the PreToolUse owner-gate hook (Bậc 0 / Q2).
// 2) Inbox location + 7-day retention (Bậc 1 / Q4).
// Pure functions are exported for tests; IO helpers never throw into the poller.
import { lstatSync, mkdirSync, readdirSync, readFileSync, renameSync, rmSync, writeFileSync } from 'fs'
import { homedir } from 'os'
import { join } from 'path'

export type TrustState = {
  v: 1
  last_owner_ts: number | null      // ms epoch of last delivered message that may use elevated tools
  last_untrusted_ts: number | null  // ms epoch of last delivered message that may NOT
  last_reason: string
}

export type TrustEvent = {
  senderIsBot: boolean
  senderInAllowFrom: boolean        // access.allowFrom = Hưng's human DM allowlist (single owner)
  chatType: string | undefined      // 'private' | 'group' | 'supergroup' | ...
  roomContextCount: number          // passive messages of OTHER people attached to this delivery
}

// Q2: elevated only for Hưng (human, allowFrom). In a group, only when the delivery carries
// no attached room-context from other people (that text is untrusted and could inject).
export function classifyTrust(e: TrustEvent): { owner: boolean; reason: string } {
  if (e.senderIsBot) {return { owner: false, reason: 'sender_is_bot' }}
  if (!e.senderInAllowFrom) {return { owner: false, reason: 'sender_not_owner' }}
  if (e.chatType === 'private') {return { owner: true, reason: 'owner_dm' }}
  if (e.roomContextCount > 0) {return { owner: false, reason: 'owner_group_with_room_context' }}
  return { owner: true, reason: 'owner_group_no_context' }
}

export function nextTrustState(prev: TrustState | null, e: TrustEvent, now: number): TrustState {
  const base: TrustState = prev ?? { v: 1, last_owner_ts: null, last_untrusted_ts: null, last_reason: 'init' }
  const c = classifyTrust(e)
  return c.owner
    ? { ...base, last_owner_ts: now, last_reason: c.reason }
    : { ...base, last_untrusted_ts: now, last_reason: c.reason }
}

function readTrust(file: string): TrustState | null {
  try {
    const j = JSON.parse(readFileSync(file, 'utf8'))
    return j && j.v === 1 ? (j as TrustState) : null
  } catch { return null }
}

// Atomic write (tmp + rename) so the hook never reads a half-written file.
export function recordTrust(file: string, e: TrustEvent, now = Date.now()): void {
  try {
    const next = nextTrustState(readTrust(file), e, now)
    const tmp = `${file}.tmp-${process.pid}`
    writeFileSync(tmp, JSON.stringify(next) + '\n', { mode: 0o600 })
    renameSync(tmp, file)
  } catch (err) {
    // Fail-closed by design: if the marker cannot be written, the hook keeps the old/no state.
    process.stderr.write(`telegram channel: trust marker write failed: ${err}\n`)
  }
}

// Bậc 1: inbox outside ~/.claude/channels (which stays denied because it holds .env/access.json).
export function resolveInboxDir(env: NodeJS.ProcessEnv, stateDir: string, collabStateDir: string): string {
  if (env.TELEGRAM_INBOX_DIR) {return env.TELEGRAM_INBOX_DIR}
  if (stateDir === collabStateDir) {return join(homedir(), 'collab-bot', 'inbox')}
  return join(stateDir, 'inbox')
}

export function ensureInbox(dir: string): void {
  mkdirSync(dir, { recursive: true, mode: 0o700 })
}

// Deletes only regular files directly inside dir older than maxAgeMs. Never follows symlinks,
// never recurses. Returns number of deleted files.
export function pruneInbox(dir: string, maxAgeMs: number, now = Date.now()): number {
  let n = 0
  let names: string[] = []
  try { names = readdirSync(dir) } catch { return 0 }
  for (const name of names) {
    const p = join(dir, name)
    try {
      const st = lstatSync(p)
      if (!st.isFile()) {continue}
      if (now - st.mtimeMs > maxAgeMs) { rmSync(p); n++ }
    } catch {}
  }
  return n
}

export function retentionMs(env: NodeJS.ProcessEnv): number {
  const d = Number(env.TELEGRAM_INBOX_RETENTION_DAYS ?? '7')
  return (Number.isFinite(d) && d > 0 ? d : 7) * 24 * 60 * 60 * 1000
}
