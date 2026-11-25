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

export type TranscriptInfo = { file: string; bytes: number; records: number; mtimeMs: number }

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
  let records = 0
  try {
    const raw = readFileSync(join(dir, best.file), 'utf8')
    for (let i = 0; i < raw.length; i++) if (raw.charCodeAt(i) === 10) records++
  } catch {}
  return { ...best, records }
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
  return new Intl.DateTimeFormat('vi-VN', {
    timeZone: VN_TZ, day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false,
  }).format(new Date(ms))
}
function duration(sec: number): string {
  const d = Math.floor(sec / 86400), h = Math.floor((sec % 86400) / 3600), m = Math.floor((sec % 3600) / 60)
  return d > 0 ? `${d} ngày ${h} giờ` : h > 0 ? `${h} giờ ${m} phút` : `${m} phút`
}

// Mốc cảnh báo phiên dài: số liệu đo 25/11 cho thấy mỗi phiên ~0.7–0.9 MB sau vài giờ.
export const TRANSCRIPT_WARN_BYTES = 5 * 1024 * 1024
export const LOGIN_WARN_DAYS = 5

export function buildStatusText(s: StatusInput): string {
  const lines = [`🟢 Bot đang chạy, ghép đôi với ${s.pairedAs}.`]
  lines.push(`⏱️ Phiên này mở được ${duration(s.pluginUptimeSec)} (từ ${vnTime(s.now - s.pluginUptimeSec * 1000)}).`)
  if (s.transcript) {
    const kb = Math.round(s.transcript.bytes / 1024)
    const warn = s.transcript.bytes >= TRANSCRIPT_WARN_BYTES ? ' ⚠️ phiên đã dài, nên /handover rồi mở phiên mới' : ''
    lines.push(`📜 Transcript: ${kb} KB, ${s.transcript.records} bản ghi, sửa lúc ${vnTime(s.transcript.mtimeMs)}.${warn}`)
  } else {
    lines.push('📜 Transcript: chưa thấy file.')
  }
  lines.push(`🎙️ Voice: ${s.voiceOn ? 'BẬT' : 'TẮT'}.`)
  if (!s.auth) {
    lines.push('🔑 Đăng nhập: không đọc được trạng thái.')
  } else if (s.auth.method !== 'claude.ai') {
    lines.push(`🔑 Đăng nhập: ⚠️ authMethod=${s.auth.method}, không phải claude.ai.`)
  } else if (s.auth.expiresAt) {
    const exp = Date.parse(s.auth.expiresAt)
    if (Number.isNaN(exp)) {
      lines.push('🔑 Đăng nhập claude.ai: không rõ hạn.')
    } else {
      const days = Math.floor((exp - s.now) / 86400000)
      const warn = days <= LOGIN_WARN_DAYS ? ' ⚠️ sắp hết, cần claude auth login lại' : ''
      lines.push(`🔑 Đăng nhập claude.ai: còn ${days} ngày (hết ${vnTime(exp)}).${warn}`)
    }
  } else {
    lines.push('🔑 Đăng nhập claude.ai: không rõ hạn.')
  }
  return lines.join('\n')
}
