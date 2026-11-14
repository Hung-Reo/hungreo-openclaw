import { redactSensitiveOutput } from '../lib/collab-gate.ts'
import type { IdeaMinerMode, IdeaMinerReport } from './types.ts'

function formatDayMonth(dateKey: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateKey)
  if (!m) {
    return dateKey
  }
  return `${m[3]}/${m[2]}`
}

/**
 * Formats the weekly Idea & Retro report into concise, mobile-friendly Telegram Markdown.
 */
export function formatIdeaMinerTelegramMessage(params: {
  mode: IdeaMinerMode
  report: IdeaMinerReport
  durationSeconds: number
}): string {
  const { report } = params
  const modeTag = params.mode === 'test' ? ' [TEST]' : params.mode === 'dry-run' ? ' [DRY-RUN]' : ''
  const weekLabel = `Tuần ${String(report.weekNumber).padStart(2, '0')}/${report.isoYear}`
  const rangeLabel = `${formatDayMonth(report.windowStartDate)}–${formatDayMonth(report.windowEndDate)}`

  const lines: string[] = []
  lines.push(`🧠 **IDEA & RETRO TUẦN${modeTag} — ${weekLabel} (${rangeLabel})**`)
  lines.push('')

  lines.push('1️⃣ 💡 **Ý tưởng của anh ("What to build next")**')
  if (report.ideas.length === 0) {
    lines.push('• Tuần này chưa ghi nhận ý tưởng sản phẩm mới nổi bật trong log.')
  } else {
    for (const idea of report.ideas) {
      lines.push(`• **[${idea.projectTag}] ${idea.title}**`)
      lines.push(`  ↳ *Lý do gốc:* ${idea.whyFromOwner}`)
      lines.push(`  ↳ *Bước thử nhỏ nhất:* ${idea.smallestNextStep}`)
      lines.push(`  ↳ *Nguồn:* ${idea.sourceRef}`)
    }
  }
  lines.push('')

  lines.push('2️⃣ 🛠️ **Đề xuất Skill / Rule cho Bot** *(chờ anh GO)*')
  if (report.skillProposals.length === 0) {
    lines.push('• Tuần này chưa phát hiện thao tác lặp cần đóng gói thành rule/skill mới.')
  } else {
    for (const prop of report.skillProposals) {
      lines.push(`• **[${prop.repeatTag}] ${prop.issueTitle}**`)
      lines.push(`  ↳ *Đề xuất:* ${prop.draftRuleOrSkill}`)
      lines.push(`  ↳ *Phạm vi:* ${prop.targetRef}`)
    }
  }
  lines.push('')

  lines.push('3️⃣ 🩺 **Điểm nghẽn tuần qua**')
  lines.push(`• ${report.bottleneck.summary}`)
  lines.push(`• *Gợi ý:* ${report.bottleneck.suggestion}`)
  lines.push('')
  lines.push('---')

  const fallbackTag = report.usedFallbackEditor ? ' · fallback-summary' : ''
  lines.push(
    `📊 **Tổng hợp:** Đọc ${report.sessionsScanned} phiên · ${report.handoversScanned} handover · Xong trong ${params.durationSeconds.toFixed(1)}s · Mode: \`plan\` (chỉ đọc) · 0đ API${fallbackTag}`,
  )
  lines.push('👉 Nhắn **"GO mục ..."** để em áp dụng, hoặc góp ý để chỉnh form vòng sau.')

  return redactSensitiveOutput(lines.join('\n').trim())
}
