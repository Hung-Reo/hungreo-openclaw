// CLAUDE-BOT-MENU-20261125: Telegram menu cho @hungreo_claude_bot trên VPS.
// Tầng 1 (/status /help /start): plugin tự trả lời, không tốn lượt Claude.
// Tầng 2 (/handover /tasks): plugin đẩy một chỉ thị cố định vào phiên Claude đang chạy.
// Không có /model hay /reset: plugin là MCP con, không đổi được model hay phiên của tiến trình cha.
import { readdirSync, readFileSync, statSync } from 'fs'
import { join } from 'path'

export type TelegramBotCommand = { command: string; description: string }
export type TelegramCommandScope = { type: 'all_private_chats' }
export type SetMyCommandsApi = {
  setMyCommands: (commands: TelegramBotCommand[], other?: { scope?: TelegramCommandScope }) => Promise<unknown>
}

export const CLAUDE_BOT_COMMANDS: readonly TelegramBotCommand[] = [
  { command: 'status', description: 'Tình trạng bot: phiên, voice, hạn đăng nhập' },
  { command: 'handover', description: 'Nhờ Claude ghi handover phiên hiện tại' },
  { command: 'tasks', description: 'Nhờ Claude liệt kê việc đang mở' },
  { command: 'help', description: 'Bot làm được gì' },
  { command: 'start', description: 'Giới thiệu @hungreo_claude_bot' },
]

export async function registerClaudeBotCommands(
  api: SetMyCommandsApi,
  onError?: (err: unknown) => void,
): Promise<boolean> {
  try {
    await api.setMyCommands(CLAUDE_BOT_COMMANDS.map(c => ({ ...c })), { scope: { type: 'all_private_chats' } })
    return true
  } catch (err) {
    onError?.(err)
    return false
  }
}

// Tầng 2: nội dung cố định do plugin viết, không chứa chữ người dùng gõ thêm sau lệnh.
export const SLASH_PROMPTS = {
  handover:
    '[slash_command=/handover từ Hưng qua menu Telegram]\n' +
    'Viết handover cho phiên hiện tại vào ~/collab-bot/handoff/handover-<YYYYMMDD-HHMM>.md (giờ VN): ' +
    'việc đang làm, đã xong gì (kèm bằng chứng), còn dở gì, đang chờ Hưng quyết gì, bước tiếp theo. ' +
    'Không chép secret hay token. Xong thì reply Hưng tóm tắt 5 dòng và đường dẫn file.',
  tasks:
    '[slash_command=/tasks từ Hưng qua menu Telegram]\n' +
    'Đọc ~/collab-bot/handoff/ và ~/collab-bot/memory/, liệt kê các việc còn mở: tên việc, trạng thái, ' +
    'đang chờ ai. Tối đa 10 dòng, việc mới nhất trước. Chỉ đọc, không sửa file.',
} as const
export type SlashPromptName = keyof typeof SLASH_PROMPTS

export const HELP_TEXT =
  '🤖 Claude chạy 24/7 trên VPS, dùng gói claude.ai (không tính tiền API).\n\n' +
  'Cứ nhắn tin, gửi ảnh hay voice (khi voice đang bật). Việc cần quyền, bot sẽ hỏi qua nút bấm ở DM.\n\n' +
  '/status — tình trạng bot (không tốn lượt Claude)\n' +
  '/handover — nhờ Claude ghi handover phiên\n' +
  '/tasks — nhờ Claude liệt kê việc đang mở\n' +
  '/help — tin này'

export const START_TEXT =
  '👋 Chào Hưng, đây là @hungreo_claude_bot (Claude Code trên VPS).\n' +
  'Gõ /help để xem lệnh, /status để xem bot còn khoẻ không.'

/** Claude Code đặt tên thư mục transcript bằng cwd, thay mọi ký tự không phải chữ/số bằng '-'. */
export function projectSlug(cwd: string): string {
  return cwd.replace(/[^a-zA-Z0-9]/g, '-')
}

export type TranscriptInfo = {
  file: string
  bytes: number
  mtimeMs: number
  turns: number
  model?: string
  contextTokens?: number
  cumulativeTokens: number
  lastTurnMs?: number
  firstMs?: number
}

type Usage = { input_tokens?: number; cache_read_input_tokens?: number; cache_creation_input_tokens?: number; output_tokens?: number }
const n = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : 0)

/** Chỉ đọc metadata (type, model, usage, timestamp); không đọc nội dung tin nhắn. */
export function parseTranscript(raw: string): Omit<TranscriptInfo, 'file' | 'bytes' | 'mtimeMs'> {
  let turns = 0, cumulative = 0, model: string | undefined, ctx: number | undefined, last: number | undefined, first: number | undefined
  const seen = new Set<string>()
  for (const line of raw.split('\n')) {
    if (!line) continue
    let r: { type?: string; subtype?: string; isSidechain?: boolean; timestamp?: string; message?: { id?: string; model?: string; usage?: Usage } }
    try { r = JSON.parse(line) } catch { continue }
    const ts = r.timestamp ? Date.parse(r.timestamp) : NaN
    if (first == null && !Number.isNaN(ts)) first = ts
    if (r.type === 'system' && r.subtype === 'turn_duration') { turns++; continue }
    if (r.type !== 'assistant' || r.isSidechain) continue
    const u = r.message?.usage
    // Một câu trả lời được ghi thành nhiều bản ghi cùng message.id (mỗi khối nội dung một dòng): chỉ đếm 1 lần.
    const id = r.message?.id
    if (u && !(id && seen.has(id))) {
      if (id) seen.add(id)
      cumulative += n(u.input_tokens) + n(u.cache_creation_input_tokens) + n(u.output_tokens)
    }
    if (u) ctx = n(u.input_tokens) + n(u.cache_read_input_tokens) + n(u.cache_creation_input_tokens)
    if (r.message?.model) model = r.message.model
    if (!Number.isNaN(ts)) last = ts
  }
  return { turns, cumulativeTokens: cumulative, ...(model ? { model } : {}), ...(ctx != null ? { contextTokens: ctx } : {}), ...(last != null ? { lastTurnMs: last } : {}), ...(first != null ? { firstMs: first } : {}) }
}

export function latestTranscript(projectsDir: string, cwd: string): TranscriptInfo | null {
  const dir = join(projectsDir, projectSlug(cwd))
  let best: { file: string; mtimeMs: number; bytes: number } | null = null
  try {
    for (const name of readdirSync(dir)) {
      if (!name.endsWith('.jsonl')) continue
      const st = statSync(join(dir, name))
      if (!best || st.mtimeMs > best.mtimeMs) best = { file: name, mtimeMs: st.mtimeMs, bytes: st.size }
    }
  } catch {
    return null
  }
  if (!best) return null
  let parsed: ReturnType<typeof parseTranscript> = { turns: 0, cumulativeTokens: 0 }
  try { parsed = parseTranscript(readFileSync(join(dir, best.file), 'utf8')) } catch {}
  return { ...best, ...parsed }
}

export type AuthInfo = { method: string; expiresAt?: string } | null

/** Chỉ đọc 2 trường không bí mật từ `claude auth status --json`. */
export function parseAuthStatus(json: string): AuthInfo {
  try {
    const j = JSON.parse(json) as { authMethod?: unknown; loginExpiresAt?: unknown }
    if (typeof j.authMethod !== 'string') return null
    return { method: j.authMethod, ...(typeof j.loginExpiresAt === 'string' ? { expiresAt: j.loginExpiresAt } : {}) }
  } catch {
    return null
  }
}

export type StatusInput = {
  now: number
  pluginUptimeSec: number
  transcript: TranscriptInfo | null
  voiceOn: boolean
  auth: AuthInfo
  pairedAs: string
}

const VN_TZ = 'Asia/Ho_Chi_Minh'
function vnTime(ms: number): string {
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-GB', {
    timeZone: VN_TZ, day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false,
  }).formatToParts(new Date(ms)).map(x => [x.type, x.value]))
  return `${p.hour}:${p.minute} ${p.day}/${p.month}`
}
function duration(sec: number): string {
  const d = Math.floor(sec / 86400), h = Math.floor((sec % 86400) / 3600), m = Math.floor((sec % 3600) / 60)
  return d > 0 ? `${d} ngày ${h} giờ` : h > 0 ? `${h} giờ ${m} phút` : `${m} phút`
}

// ASSUMPTION: cửa sổ 200k cho model không có hậu tố [1m]; mốc auto-compact chính xác không công bố → ghi "ước tính".
export function contextWindow(model?: string): number {
  return model && /\[1m\]/i.test(model) ? 1_000_000 : 200_000
}
export const LOGIN_WARN_DAYS = 5
export const EXPECTED_MODEL_PREFIX = 'claude-opus-'

function bar(pct: number): string {
  const full = Math.max(0, Math.min(10, Math.round(pct / 10)))
  return (pct >= 80 ? '🟥' : pct >= 60 ? '🟧' : '🟨').repeat(full) + '⬜'.repeat(10 - full)
}
const fmt = (v: number) => v.toLocaleString('en-US')
function ago(ms: number): string {
  const sec = Math.max(0, Math.floor(ms / 1000))
  return sec < 60 ? 'vừa xong' : `${duration(sec)} trước`
}

export function buildStatusText(s: StatusInput): string {
  const startMs = s.now - s.pluginUptimeSec * 1000
  const lines = [`📊 Trạng thái @hungreo_claude_bot (ghép đôi ${s.pairedAs})`]
  // Launcher không --resume: phiên hiện tại luôn bắt đầu sau khi bot mở. File cũ hơn = phiên trước restart.
  const t = s.transcript && (s.transcript.firstMs ?? 0) >= startMs - 120_000 ? s.transcript : null
  if (t?.model) {
    const off = t.model.startsWith(EXPECTED_MODEL_PREFIX) ? '' : ' ⚠️ không phải Opus'
    lines.push(`- Model: ${t.model}${off}`)
  } else {
    lines.push('- Model: chưa có lượt trả lời trong phiên này')
  }
  lines.push(`- Bot mở lúc: ${vnTime(startMs)} (VNT) · chạy ${duration(s.pluginUptimeSec)}`)
  if (!t) {
    lines.push('- Phiên: mới, chưa có lượt nào')
  } else {
    const lastTxt = t.lastTurnMs != null ? ` · lượt cuối ${ago(s.now - t.lastTurnMs)}` : ''
    lines.push(`- Phiên: ${t.file.slice(0, 8)}… · ${t.turns} lượt${lastTxt}`)
    if (t.contextTokens != null) {
      const win = contextWindow(t.model)
      const pct = (t.contextTokens / win) * 100
      const tag = pct >= 80 ? '🔴 nên /handover' : pct >= 60 ? '🟠 sắp đầy' : '🟢 dư dả'
      lines.push(`- Context (ước tính): ${fmt(t.contextTokens)} / ${fmt(win)} tokens (${pct.toFixed(0)}%) · ${tag}`)
      lines.push(`  ${bar(pct)}`)
    }
    lines.push(`- Cộng dồn: ${fmt(t.cumulativeTokens)} tokens (input mới + output, không tính cache đọc lại)`)
  }
  let login: string
  if (!s.auth) login = 'không đọc được trạng thái'
  else if (s.auth.method !== 'claude.ai') login = `⚠️ authMethod=${s.auth.method}, không phải claude.ai`
  else {
    const exp = s.auth.expiresAt ? Date.parse(s.auth.expiresAt) : NaN
    if (Number.isNaN(exp)) login = 'claude.ai, không rõ hạn'
    else {
      const days = Math.floor((exp - s.now) / 86400000)
      login = `claude.ai còn ${days} ngày (hết ${vnTime(exp)})${days <= LOGIN_WARN_DAYS ? ' ⚠️ sắp hết' : ''}`
    }
  }
  lines.push(`- Voice: ${s.voiceOn ? 'BẬT' : 'TẮT'} · Login: ${login}`)
  lines.push('')
  lines.push('Lệnh nhanh: /handover ghi handover · /tasks việc đang mở')
  return lines.join('\n')
}
