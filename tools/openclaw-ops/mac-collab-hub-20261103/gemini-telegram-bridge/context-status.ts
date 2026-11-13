import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'

export const DEFAULT_CONTEXT_WINDOW_TOKENS = 1_048_576
export const DEFAULT_WARN_TOKEN_THRESHOLDS = [150_000, 225_000, 300_000] as const
export const DEFAULT_AUTO_HANDOVER_TOKENS = 300_000

export type ContextWarningAction = 'button' | 'auto'

export type QuotaPolicy = {
  contextWindowTokens: number
  warnTokenThresholds: readonly number[]
  autoHandoverTokens: number
}

export type ThreadStats = {
  conversationId: string
  modelId: string
  lastTokens?: number
  turns: number
  lastDurationSeconds?: number
  lastWarnedTokens?: number
  lastWarnedPct: number
  updatedAt: string
}

export type ContextWarningEvaluation = {
  usagePct: number
  shouldWarn: boolean
  crossedThresholdTokens?: number
  nextWarnedTokens: number
  nextWarnedPct: number
  action?: ContextWarningAction
  warningText?: string
}

function parsePositiveInt(raw: string | undefined, fallback: number): number {
  const trimmed = raw?.trim()
  if (!trimmed) {return fallback}
  const parsed = Number(trimmed)
  if (!Number.isFinite(parsed) || parsed <= 0) {return fallback}
  return Math.floor(parsed)
}

/**
 * Resolves the active context window capacity in tokens from environment overrides.
 */
export function resolveContextWindowTokens(env: Record<string, string | undefined> = process.env): number {
  return parsePositiveInt(env.GEMINI_CONTEXT_WINDOW_TOKENS, DEFAULT_CONTEXT_WINDOW_TOKENS)
}

/**
 * Resolves quota-saving token thresholds (defaults: warn at 150k/225k, auto-handover at 300k).
 */
export function resolveQuotaPolicy(env: Record<string, string | undefined> = process.env): QuotaPolicy {
  const contextWindowTokens = resolveContextWindowTokens(env)
  const autoHandoverTokens = parsePositiveInt(env.GEMINI_AUTO_HANDOVER_TOKENS, DEFAULT_AUTO_HANDOVER_TOKENS)

  const rawList = env.GEMINI_WARN_TOKENS?.trim()
  let warnTokenThresholds: number[] = [...DEFAULT_WARN_TOKEN_THRESHOLDS]
  if (rawList) {
    const parsedList = rawList
      .split(',')
      .map(s => Number(s.trim()))
      .filter(n => Number.isFinite(n) && n > 0)
      .map(n => Math.floor(n))
    if (parsedList.length > 0) {
      warnTokenThresholds = parsedList
    }
  }
  if (!warnTokenThresholds.includes(autoHandoverTokens)) {
    warnTokenThresholds.push(autoHandoverTokens)
  }
  warnTokenThresholds.sort((a, b) => a - b)

  return {
    contextWindowTokens,
    warnTokenThresholds,
    autoHandoverTokens,
  }
}

function formatCompactTokens(tokens: number): string {
  if (tokens >= 1_000_000) {
    return `${(tokens / 1_000_000).toFixed(2).replace(/\.?0+$/, '')}M`
  }
  if (tokens >= 1_000) {
    return `${Math.round(tokens / 1_000)}k`
  }
  return String(tokens)
}

function formatNumber(n: number): string {
  return Math.round(n).toLocaleString('en-US')
}

function buildUsageBar(ratioPct: number): string {
  const clamped = Math.max(0, Math.min(100, ratioPct))
  const filled = Math.min(10, Math.round(clamped / 10))
  const fillChar = clamped >= 75 ? '🟥' : clamped >= 50 ? '🟨' : '🟩'
  return `${fillChar.repeat(filled)}${'⬜'.repeat(10 - filled)}`
}

/**
 * Checks whether token count crossed a new absolute token milestone (default 150k / 225k / 300k)
 * so Telegram warns once per tier and auto-hands over at 300k to preserve quota.
 */
export function evaluateContextWarning(params: {
  totalTokens: number
  contextWindowTokens?: number
  lastWarnedTokens?: number
  thresholdsTokens?: readonly number[]
  autoHandoverTokens?: number
}): ContextWarningEvaluation {
  const windowTokens =
    params.contextWindowTokens && params.contextWindowTokens > 0
      ? params.contextWindowTokens
      : DEFAULT_CONTEXT_WINDOW_TOKENS
  const thresholds = params.thresholdsTokens ?? DEFAULT_WARN_TOKEN_THRESHOLDS
  const autoThreshold =
    params.autoHandoverTokens && params.autoHandoverTokens > 0
      ? params.autoHandoverTokens
      : DEFAULT_AUTO_HANDOVER_TOKENS
  const prevWarnedTokens = params.lastWarnedTokens ?? 0
  const usagePct = Math.max(0, (params.totalTokens / windowTokens) * 100)
  const prevWarnedPct = Math.round((prevWarnedTokens / windowTokens) * 100)

  let highestCrossed = 0
  for (const t of thresholds) {
    if (params.totalTokens >= t && t > highestCrossed) {
      highestCrossed = t
    }
  }

  if (highestCrossed <= prevWarnedTokens) {
    return {
      usagePct,
      shouldWarn: false,
      nextWarnedTokens: prevWarnedTokens,
      nextWarnedPct: prevWarnedPct,
    }
  }

  const action: ContextWarningAction = highestCrossed >= autoThreshold ? 'auto' : 'button'
  const urgencyIcon = action === 'auto' || highestCrossed >= Math.round(autoThreshold * 0.75) ? '🔴' : '⚠️'
  const pctRounded = Math.round(usagePct)
  const warningText =
    action === 'auto'
      ? `${urgencyIcon} **Cảnh báo context:** phiên đã chạm **${formatCompactTokens(params.totalTokens)}** tokens (vượt ngưỡng auto ${formatCompactTokens(autoThreshold)} · ${pctRounded}% khung 1M) — đang tự động handover & mở phiên mới.`
      : `${urgencyIcon} **Cảnh báo context:** phiên đã đạt **${formatCompactTokens(params.totalTokens)}** tokens (${pctRounded}% khung 1M · ngưỡng auto ${formatCompactTokens(autoThreshold)}).\n` +
        `👉 Bấm nút bên dưới (hoặc gõ \`/handover\`) để dọn phiên tiết kiệm quota (hoặc \`/reset_thread\` nếu muốn xoá trắng).`

  return {
    usagePct,
    shouldWarn: true,
    crossedThresholdTokens: highestCrossed,
    nextWarnedTokens: highestCrossed,
    nextWarnedPct: Math.round((highestCrossed / windowTokens) * 100),
    action,
    warningText,
  }
}

/**
 * Persists per-chat thread token usage and warning watermarks in `STATE_DIR` (0600).
 */
export class ThreadStatsStore {
  constructor(private readonly filePath: string) {}

  private loadAll(): Record<string, ThreadStats> {
    try {
      const parsed = JSON.parse(readFileSync(this.filePath, 'utf8')) as Record<string, ThreadStats>
      return parsed && typeof parsed === 'object' ? parsed : {}
    } catch {
      return {}
    }
  }

  private saveAll(map: Record<string, ThreadStats>): void {
    mkdirSync(dirname(this.filePath), { recursive: true, mode: 0o700 })
    const tmp = `${this.filePath}.tmp`
    writeFileSync(tmp, JSON.stringify(map, null, 2) + '\n', { mode: 0o600 })
    renameSync(tmp, this.filePath)
  }

  get(chatId: string): ThreadStats | undefined {
    return this.loadAll()[chatId]
  }

  recordTurn(params: {
    chatId: string
    conversationId: string
    modelId: string
    totalTokens?: number
    durationSeconds?: number
    contextWindowTokens?: number
    thresholdsTokens?: readonly number[]
    autoHandoverTokens?: number
    nowIso?: string
  }): { stats: ThreadStats; warning: ContextWarningEvaluation } {
    const all = this.loadAll()
    const prev = all[params.chatId]
    const sameConv = Boolean(prev && prev.conversationId === params.conversationId)

    const prevTurns = sameConv ? prev.turns : 0
    const prevWarnedTokens = sameConv ? (prev.lastWarnedTokens ?? 0) : 0
    const prevWarnedPct = sameConv ? prev.lastWarnedPct : 0
    const nextTokens =
      typeof params.totalTokens === 'number' && Number.isFinite(params.totalTokens) && params.totalTokens >= 0
        ? params.totalTokens
        : sameConv
          ? prev.lastTokens
          : undefined

    const warning =
      typeof nextTokens === 'number'
        ? evaluateContextWarning({
            totalTokens: nextTokens,
            contextWindowTokens: params.contextWindowTokens,
            lastWarnedTokens: prevWarnedTokens,
            thresholdsTokens: params.thresholdsTokens,
            autoHandoverTokens: params.autoHandoverTokens,
          })
        : {
            usagePct: 0,
            shouldWarn: false,
            nextWarnedTokens: prevWarnedTokens,
            nextWarnedPct: prevWarnedPct,
          }

    const stats: ThreadStats = {
      conversationId: params.conversationId,
      modelId: params.modelId,
      ...(typeof nextTokens === 'number' ? { lastTokens: nextTokens } : {}),
      turns: prevTurns + 1,
      ...(typeof params.durationSeconds === 'number'
        ? { lastDurationSeconds: params.durationSeconds }
        : {}),
      lastWarnedTokens: warning.nextWarnedTokens,
      lastWarnedPct: warning.nextWarnedPct,
      updatedAt: params.nowIso ?? new Date().toISOString(),
    }

    all[params.chatId] = stats
    this.saveAll(all)
    return { stats, warning }
  }

  clear(chatId: string): void {
    if (!existsSync(this.filePath)) {return}
    const all = this.loadAll()
    if (!(chatId in all)) {return}
    delete all[chatId]
    this.saveAll(all)
  }
}

/**
 * Formats the Telegram `/status` response with model, active thread, and token quota budget.
 */
export function formatContextStatusMessage(params: {
  botUsername?: string
  currentModelId: string
  currentModelLabel: string
  conversationId?: string
  contextWindowTokens?: number
  warnStartTokens?: number
  autoHandoverTokens?: number
  stats?: ThreadStats
}): string {
  const windowTokens =
    params.contextWindowTokens && params.contextWindowTokens > 0
      ? params.contextWindowTokens
      : DEFAULT_CONTEXT_WINDOW_TOKENS
  const autoTokens =
    params.autoHandoverTokens && params.autoHandoverTokens > 0
      ? params.autoHandoverTokens
      : DEFAULT_AUTO_HANDOVER_TOKENS
  const warnStart =
    params.warnStartTokens && params.warnStartTokens > 0
      ? params.warnStartTokens
      : DEFAULT_WARN_TOKEN_THRESHOLDS[0]
  const botHandle = params.botUsername ? `@${params.botUsername}` : '@hungreo_gemini_bot'
  const activeStats =
    params.conversationId && params.stats && params.stats.conversationId === params.conversationId
      ? params.stats
      : undefined

  const lines: string[] = [
    `📊 **Trạng thái ${botHandle}**`,
    `- **Model:** ${params.currentModelLabel} (\`${params.currentModelId}\`)`,
  ]

  if (!params.conversationId) {
    lines.push('- **Phiên:** Chưa có phiên (tin nhắn tới sẽ mở mới)')
    lines.push(`- **Context:** \`0 / ${formatCompactTokens(autoTokens)}\` ngưỡng auto (0.0% khung 1M) 🟢`)
  } else {
    const shortConv = params.conversationId.slice(0, 8)
    const turnText = activeStats ? ` · ${activeStats.turns} lượt` : ''
    lines.push(`- **Phiên:** Đang mở (\`${shortConv}…\`${turnText})`)

    if (activeStats && typeof activeStats.lastTokens === 'number') {
      const windowPct = Math.max(0, (activeStats.lastTokens / windowTokens) * 100)
      const budgetPct = Math.max(0, (activeStats.lastTokens / autoTokens) * 100)
      const nearAuto = Math.round(autoTokens * 0.75)
      const badge =
        activeStats.lastTokens >= nearAuto
          ? '🔴 Sắp auto-handover'
          : activeStats.lastTokens >= warnStart
            ? '🟡 Nên handover sớm'
            : '🟢 Dư dả'
      const bar = buildUsageBar(budgetPct)
      lines.push(
        `- **Ngân sách phiên:** \`${formatNumber(activeStats.lastTokens)} / ${formatNumber(autoTokens)}\` tokens (**${budgetPct.toFixed(0)}%** mốc auto · ${windowPct.toFixed(1)}% khung 1M) · ${badge}`,
      )
      lines.push(`  ${bar}`)
      if (typeof activeStats.lastDurationSeconds === 'number') {
        lines.push(`- **Lượt gần nhất:** ${activeStats.lastDurationSeconds.toFixed(1)}s`)
      }
    } else {
      lines.push('- **Context:** Chưa có số liệu token (gửi thêm 1 tin sau khi restart bridge để đo)')
    }
  }

  lines.push('')
  lines.push('Lệnh nhanh: `/model` đổi model · `/handover` chốt & mở phiên mới · `/reset_thread` mở context mới')
  return lines.join('\n')
}
