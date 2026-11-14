import { mkdirSync, renameSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { redactSensitiveOutput } from '../lib/collab-gate.ts'
import { DEFAULT_CONTEXT_WINDOW_TOKENS } from './context-status.ts'

export type HandoverTrigger = 'button' | 'command' | 'auto'

export type HandoverTurnSnippet = {
  senderLabel: string
  userText: string
  assistantReply?: string
}

export type HandoverSummaryResult = {
  ok: boolean
  text?: string
  error?: string
}

export type HandoverSeedResult = {
  ok: boolean
  conversationId?: string
  reply?: string
  contextTokens?: number
  totalTokens?: number
  durationSeconds?: number
  error?: string
}

export type AutoHandoverResult =
  | {
      ok: true
      trigger: HandoverTrigger
      oldConversationId: string
      newConversationId: string
      backupPath: string
      summary: string
      newContextTokens?: number
      newTokens?: number
      newReply?: string
    }
  | {
      ok: false
      trigger: HandoverTrigger
      stage: 'no_thread' | 'summarize' | 'seed'
      error: string
      oldConversationId?: string
      backupPath?: string
      summary?: string
    }

function clipTurnText(raw: string, maxChars: number): string {
  const safe = redactSensitiveOutput(raw).trim()
  if (safe.length <= maxChars) {
    return safe
  }
  return `${safe.slice(0, Math.max(1, maxChars - 1))}…`
}

/**
 * In-memory bounded ring buffer keeping the latest redacted turns per chat
 * so handovers preserve recent verbatim context even when summaries compress details.
 */
export class RecentTurnBuffer {
  private readonly store = new Map<string, HandoverTurnSnippet[]>()

  constructor(
    private readonly maxTurnsPerChat = 3,
    private readonly maxFieldChars = 600,
  ) {}

  record(chatId: string, turn: HandoverTurnSnippet): void {
    const userText = clipTurnText(turn.userText, this.maxFieldChars)
    if (!userText) {
      return
    }
    const assistantReply = turn.assistantReply ? clipTurnText(turn.assistantReply, this.maxFieldChars) : undefined
    const entry: HandoverTurnSnippet = {
      senderLabel: redactSensitiveOutput(turn.senderLabel.trim()) || 'user',
      userText,
      ...(assistantReply ? { assistantReply } : {}),
    }
    const existing = this.store.get(chatId) ?? []
    const next = [...existing, entry]
    if (next.length > this.maxTurnsPerChat) {
      next.splice(0, next.length - this.maxTurnsPerChat)
    }
    this.store.set(chatId, next)
  }

  get(chatId: string): HandoverTurnSnippet[] {
    return (this.store.get(chatId) ?? []).map(item => ({ ...item }))
  }

  clear(chatId: string): void {
    this.store.delete(chatId)
  }
}

function formatRecentTurnsSection(recentTurns?: readonly HandoverTurnSnippet[]): string {
  if (!recentTurns || recentTurns.length === 0) {
    return ''
  }
  const lines = recentTurns.map((turn, idx) => {
    const sender = redactSensitiveOutput(turn.senderLabel.trim()) || 'user'
    const userText = redactSensitiveOutput(turn.userText.trim())
    const reply = turn.assistantReply ? redactSensitiveOutput(turn.assistantReply.trim()) : ''
    return reply ? `${idx + 1}. [${sender}]: ${userText}\n   → Bot: ${reply}` : `${idx + 1}. [${sender}]: ${userText}`
  })
  return `\n\n📌 **Ngữ cảnh trao đổi gần nhất trước khi handover (nguyên văn rút gọn):**\n${lines.join('\n')}`
}

/**
 * Builds the initial Telegram system prompt used when opening any fresh conversation thread.
 */
export function buildTelegramInitialPrompt(senderLabel: string, userText: string, bridgeStartedLabel?: string): string {
  const runtimeLine = bridgeStartedLabel?.trim() ? `[Bridge started: ${bridgeStartedLabel.trim()}]\n` : ''
  return (
    `Bạn là trợ lý AI @hungreo_gemini_bot trên Telegram của anh Hưng (@hungdinh) và nhóm cộng tác.\n` +
    `Hãy giao tiếp tự nhiên, thân thiện, súc tích và hữu ích bằng tiếng Việt.\n` +
    `Định dạng câu trả lời phù hợp với Telegram: chia đoạn ngắn gọn dễ đọc trên điện thoại, dùng **bold** để nhấn mạnh ý chính, thêm emoji tự nhiên cho sinh động, dùng \`code\` cho lệnh/đường dẫn. Không tự escape ký tự Markdown vì bridge sẽ tự chuyển sang MarkdownV2.\n` +
    `Nếu là câu chào hỏi, giao tiếp thông thường hoặc câu hỏi nghiệp vụ/tư vấn, hãy trả lời bằng lời nói tự nhiên, không tự ý chạy tool lệnh shell thừa thãi. Khi cần dùng lệnh shell, chỉ chạy lệnh đơn, tuyệt đối không ghép chuỗi (&&, ||, ;, |) để tránh bị chính sách an toàn chặn.\n` +
    `Tuyệt đối KHÔNG suy đoán trạng thái runtime/restart, mốc thời gian tiến trình hay kết quả lệnh chưa chạy; mọi nhận định đã/chưa restart phải dựa trên nhãn [Bridge started: ...] hoặc bằng chứng đọc trực tiếp. Nếu thiếu bằng chứng, hãy nói thẳng "em chưa kiểm được" và hỏi anh Hưng.\n\n` +
    `${runtimeLine}Tin nhắn từ ${senderLabel}: ${userText}`
  )
}

/**
 * Builds the prompt sent to the expiring thread to capture a structured handover without touching tools.
 */
export function buildHandoverSummaryPrompt(): string {
  return (
    `Hãy viết bản tóm tắt HANDOVER đầy đủ, có cấu trúc rõ ràng (khoảng 25–45 dòng, tối đa ~3.500 ký tự) để chuyển giao sang phiên mới mà KHÔNG làm rơi chi tiết quan trọng.\n` +
    `Yêu cầu:\n` +
    `- CHỈ tổng hợp từ ngữ cảnh hiện có trong phiên này.\n` +
    `- TUYỆT ĐỐI KHÔNG chạy lệnh shell, KHÔNG gọi tool đọc/sửa file.\n` +
    `- Không ép tóm tắt quá cụt nếu đang có format mẫu, cấu trúc hệ thống hoặc yêu cầu cụ thể cần bảo toàn.\n` +
    `- Cấu trúc gồm 5 mục rõ ràng:\n` +
    `  1. Mục tiêu & yêu cầu gần nhất của anh Hưng (giữ đúng ý các trao đổi cuối và câu hỏi/task đang dở)\n` +
    `  2. Đã xong & đã chốt (chỉ ghi việc đã kiểm chứng kèm tên file/symbol/số liệu thật)\n` +
    `  3. Chi tiết kỹ thuật, format & đường dẫn file tham chiếu bắt buộc giữ (format bản tin mẫu, cấu trúc pipeline/query, đường dẫn tuyệt đối các file/báo cáo đã đọc)\n` +
    `  4. Ràng buộc an toàn & quyền (nhánh git, file không được sửa, quyền bị chặn/cần hỏi)\n` +
    `  5. Việc tiếp theo / còn mở (bước kế tiếp và điểm đang chờ anh Hưng chốt)\n` +
    `Trả về thẳng nội dung bản HANDOVER bằng tiếng Việt.`
  )
}

/**
 * Builds the first message sent to a newly reset thread so it immediately loads the handover.
 */
export function buildHandoverSeedPrompt(summaryText: string, recentTurns?: readonly HandoverTurnSnippet[]): string {
  const safeSummary = redactSensitiveOutput(summaryText.trim())
  const recentSection = formatRecentTurnsSection(recentTurns)
  const taskInstruction =
    `Đây là bản HANDOVER tự động từ phiên vừa đóng. ` +
    `Hãy ghi nhớ toàn bộ ngữ cảnh, format mẫu, đường dẫn tham chiếu và các trao đổi gần nhất dưới đây để tiếp tục hỗ trợ anh Hưng liền mạch, không hỏi lại những gì đã chốt.\n` +
    `CHỈ trả lời ngắn gọn 1–2 câu xác nhận đã nạp xong handover (nêu ngắn trọng tâm việc đang làm tiếp) và sẵn sàng tiếp tục (KHÔNG chạy lệnh shell hay tool).\n\n` +
    `${safeSummary}${recentSection}`
  return buildTelegramInitialPrompt('HANDOVER_AUTO', taskInstruction)
}

/**
 * Atomically persists a redacted handover snapshot to disk with strict `0600` permissions.
 */
export function saveHandoverSnapshot(
  handoversDir: string,
  chatId: string,
  summaryText: string,
  recentTurns?: readonly HandoverTurnSnippet[],
): string {
  mkdirSync(handoversDir, { recursive: true, mode: 0o700 })
  const safeChatId = chatId.replace(/[^a-zA-Z0-9_-]/g, '_') || 'chat'
  const filePath = join(handoversDir, `${safeChatId}.md`)
  const tmpPath = `${filePath}.tmp`
  const safeContent = redactSensitiveOutput(`${summaryText.trim()}${formatRecentTurnsSection(recentTurns)}`) + '\n'
  writeFileSync(tmpPath, safeContent, { mode: 0o600 })
  renameSync(tmpPath, filePath)
  return filePath
}

/**
 * Runs the fail-safe 3-step handover: summarize old thread -> save 0600 backup & reset -> seed new thread.
 * Old thread state is preserved intact if summarization fails.
 */
export async function executeAutoHandover(params: {
  chatId: string
  trigger: HandoverTrigger
  oldConversationId?: string
  modelId: string
  handoversDir: string
  recentTurns?: readonly HandoverTurnSnippet[]
  summarizeTurn: (conversationId: string, prompt: string) => Promise<HandoverSummaryResult>
  seedNewTurn: (prompt: string) => Promise<HandoverSeedResult>
  clearOldThreadState: (chatId: string) => void
  commitNewThreadState: (input: {
    chatId: string
    conversationId: string
    modelId: string
    contextTokens?: number
    totalTokens?: number
    durationSeconds?: number
  }) => void
}): Promise<AutoHandoverResult> {
  const { chatId, trigger, oldConversationId } = params
  if (!oldConversationId) {
    return {
      ok: false,
      trigger,
      stage: 'no_thread',
      error: 'Phòng chat này chưa có phiên đang mở để handover.',
    }
  }

  let summaryRes: HandoverSummaryResult
  try {
    summaryRes = await params.summarizeTurn(oldConversationId, buildHandoverSummaryPrompt())
  } catch (err) {
    return {
      ok: false,
      trigger,
      stage: 'summarize',
      oldConversationId,
      error: redactSensitiveOutput(err instanceof Error ? err.message : String(err)),
    }
  }

  const rawSummary = summaryRes.text?.trim() ?? ''
  if (!summaryRes.ok || !rawSummary) {
    return {
      ok: false,
      trigger,
      stage: 'summarize',
      oldConversationId,
      error: redactSensitiveOutput(summaryRes.error ?? 'Không tạo được bản tóm tắt handover từ phiên cũ.'),
    }
  }

  const safeSummary = redactSensitiveOutput(rawSummary)
  const backupPath = saveHandoverSnapshot(params.handoversDir, chatId, safeSummary, params.recentTurns)
  params.clearOldThreadState(chatId)

  let seedRes: HandoverSeedResult
  try {
    seedRes = await params.seedNewTurn(buildHandoverSeedPrompt(safeSummary, params.recentTurns))
  } catch (err) {
    return {
      ok: false,
      trigger,
      stage: 'seed',
      oldConversationId,
      backupPath,
      summary: safeSummary,
      error: redactSensitiveOutput(err instanceof Error ? err.message : String(err)),
    }
  }

  if (!seedRes.ok || !seedRes.conversationId) {
    return {
      ok: false,
      trigger,
      stage: 'seed',
      oldConversationId,
      backupPath,
      summary: safeSummary,
      error: redactSensitiveOutput(seedRes.error ?? 'Không mở được phiên mới khi nạp handover.'),
    }
  }

  params.commitNewThreadState({
    chatId,
    conversationId: seedRes.conversationId,
    modelId: params.modelId,
    contextTokens: seedRes.contextTokens,
    totalTokens: seedRes.totalTokens,
    durationSeconds: seedRes.durationSeconds,
  })

  return {
    ok: true,
    trigger,
    oldConversationId,
    newConversationId: seedRes.conversationId,
    backupPath,
    summary: safeSummary,
    newContextTokens: seedRes.contextTokens,
    newTokens: seedRes.totalTokens,
    newReply: seedRes.reply ? redactSensitiveOutput(seedRes.reply) : undefined,
  }
}

/**
 * Formats the Telegram confirmation or fail-safe error message after a handover run.
 */
export function formatHandoverResultMessage(
  result: AutoHandoverResult,
  contextWindowTokens: number = DEFAULT_CONTEXT_WINDOW_TOKENS,
): string {
  const windowTokens = contextWindowTokens > 0 ? contextWindowTokens : DEFAULT_CONTEXT_WINDOW_TOKENS

  if (!result.ok) {
    if (result.stage === 'no_thread') {
      return `ℹ️ ${result.error}`
    }
    if (result.stage === 'summarize') {
      return (
        `⚠️ **Auto-Handover tạm dừng ở bước tóm tắt** (${result.error}).\n` +
        `🔒 **Phiên cũ vẫn được giữ nguyên** để không mất ngữ cảnh. Anh có thể bấm thử lại hoặc gõ \`/handover\`.`
      )
    }
    return (
      `⚠️ **Đã lưu handover & xoá phiên cũ**, nhưng chưa nạp xong phiên mới (${result.error}).\n` +
      `💾 Bản backup đã lưu tại \`${result.backupPath}\`.\n\n` +
      `📋 **Nội dung handover (tin tới anh gửi kèm hoặc copy sang đều được):**\n${result.summary ?? ''}`
    )
  }

  const triggerLabel =
    result.trigger === 'auto'
      ? 'Tự động (vượt ngưỡng token tiết kiệm quota)'
      : result.trigger === 'button'
        ? '1-chạm từ nút cảnh báo'
        : 'Theo lệnh `/handover`'

  const oldShort = result.oldConversationId.slice(0, 8)
  const newShort = result.newConversationId.slice(0, 8)
  const tokenLine =
    typeof result.newContextTokens === 'number'
      ? `${Math.round(result.newContextTokens).toLocaleString('en-US')} / ${Math.round(windowTokens).toLocaleString('en-US')} tokens (**${((result.newContextTokens / windowTokens) * 100).toFixed(1)}%**) 🟢`
      : 'Phiên mới sạch sẽ 🟢'

  const preview =
    result.summary.length > 2600
      ? `${result.summary.slice(0, 2600)}\n…(xem đủ tại \`${result.backupPath}\`)`
      : result.summary

  return (
    `♻️ **Đã Handover & Mở phiên mới thành công!**\n` +
    `- **Chế độ:** ${triggerLabel}\n` +
    `- **Phiên:** \`${oldShort}…\` → \`${newShort}…\`\n` +
    `- **Context mới:** ${tokenLine}\n` +
    `- **Backup (0600):** \`${result.backupPath}\`\n\n` +
    `📋 **Tóm tắt đã nạp:**\n${preview}`
  )
}
