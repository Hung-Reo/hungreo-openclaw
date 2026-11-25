import { MIN_SHARED_CREDIT_FLOOR_USD } from './apify-client.ts'
import type { BriefAxis, BriefItem, XBriefMode } from './types.ts'

const AXIS_LABELS: Record<BriefAxis, string> = {
  coding: 'Coding',
  products: 'Product',
  human_education: 'AI & Edu',
}

const NUMBER_EMOJIS = ['1️⃣', '2️⃣', '3️⃣', '4️⃣', '5️⃣', '6️⃣', '7️⃣', '8️⃣', '9️⃣', '🔟']

export function formatXBriefDateLabel(dateKey: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateKey)
  if (!m) {return dateKey}
  return `${m[3]}/${m[2]}/${m[1]}`
}

export function formatXBriefTelegramMessage(params: {
  mode: XBriefMode
  dateKey: string
  items: readonly BriefItem[]
  rawItemCount: number
  costUsd: number
  remainingUsd: number
  lowCreditWarning: boolean
  durationSeconds: number
  usedFallbackEditor?: boolean
}): string {
  const modeTag = params.mode === 'test' ? ' [TEST]' : params.mode === 'dry-run' ? ' [DRY-RUN]' : ''
  const dateLabel = formatXBriefDateLabel(params.dateKey)
  const lines: string[] = []

  if (params.lowCreditWarning) {
    lines.push(
      `⚠️ **Cảnh báo credit Apify thấp:** còn ~$${params.remainingUsd.toFixed(4)} (ngưỡng tự dừng <$${MIN_SHARED_CREDIT_FLOOR_USD.toFixed(2)} để bảo vệ Rùa).`,
      '',
    )
  }

  lines.push(`⚡ **BẢN TIN X ĐỐI CHỨNG${modeTag} — ${dateLabel}**`)
  lines.push('')

  params.items.forEach((item, idx) => {
    const bullet = NUMBER_EMOJIS[idx] ?? `${idx + 1}.`
    const axisLabel = AXIS_LABELS[item.axis]
    const freshBadge = item.isRecent12h ? ' · 🆕 <12h' : ''
    lines.push(`${bullet} **[${axisLabel}] ${item.title}**${freshBadge}`)
    lines.push(item.summary)
    const linkParts = [`X (@${item.authorHandle}): ${item.url}`]
    if (item.primaryUrl) {linkParts.push(`Nguồn: ${item.primaryUrl}`)}
    lines.push(`🔗 ${linkParts.join(' · ')}`)
    lines.push('')
  })

  lines.push('---')
  const modeNote = params.usedFallbackEditor ? ' · fallback-summary' : ''
  lines.push(
    `📊 **Đối chứng:** ${params.items.length}/5 tin · Xong trong ${params.durationSeconds.toFixed(1)}s · ${params.rawItemCount} tweets thu về${modeNote}`,
  )
  lines.push(
    `💳 **Apify chung:** phí $${params.costUsd.toFixed(4)} · Free còn ~$${params.remainingUsd.toFixed(4)} (ngưỡng dừng <$${MIN_SHARED_CREDIT_FLOOR_USD.toFixed(2)})`,
  )

  return lines.join('\n').trim()
}
