import type { BriefAxis, BriefItem, NormalizedTweet } from './types.ts'

const VALID_AXES = new Set<BriefAxis>(['coding', 'products', 'human_education'])

/**
 * Builds a strict grounding prompt for Gemini on Mac so it edits top 5 items in Vietnamese
 * strictly from collected candidates without calling any shell or web tools.
 */
export function buildEditorialPrompt(candidates: readonly NormalizedTweet[]): string {
  const serialized = candidates.map((c, idx) => ({
    idx: idx + 1,
    id: c.id,
    axisHint: c.axis,
    author: `@${c.authorHandle}`,
    createdAt: c.createdAtIso,
    isRecent12h: c.isRecent12h,
    likes: c.likes,
    retweets: c.retweets,
    url: c.url,
    primaryUrl: c.primaryUrl ?? '',
    text: c.text.replace(/\s+/g, ' ').slice(0, 500),
  }))

  return (
    `Bạn là biên tập viên bản tin sáng công nghệ & AI cho anh Hưng (founder công ty công nghệ, dùng Codex / Claude Code / Antigravity / OpenClaw).\n` +
    `TUYỆT ĐỐI KHÔNG gọi bất kỳ tool, lệnh shell hay đọc file nào. Chỉ dùng đúng danh sách ứng viên JSON dưới đây.\n\n` +
    `Nhiệm vụ:\n` +
    `- Chọn đúng 5 tin giá trị nhất, KHÔNG trùng sự kiện, ưu tiên độ mới (isRecent12h) và nguồn chính chủ.\n` +
    `- Cố gắng phủ cả 3 trục ("coding", "products", "human_education"), nhưng ĐƯỢC PHÉP bù chéo nếu 1 trục thiếu tin chất lượng để luôn đạt đủ 5/5 tin.\n` +
    `- Mỗi tin viết bằng tiếng Việt tự nhiên, súc tích: "title" <= 90 ký tự; "summary" 2–3 câu ngắn đi thẳng vào cái gì mới và tác động thực tế.\n` +
    `- BẮT BUỘC giữ nguyên "id" và "url" chính xác từ ứng viên đã cho, không tự bịa URL.\n\n` +
    `Trả về DUY NHẤT một mảng JSON hợp lệ (không thêm lời bình bên ngoài), định dạng:\n` +
    `[{"id":"...","axis":"coding|products|human_education","title":"...","summary":"..."}]\n\n` +
    `Danh sách ứng viên:\n${JSON.stringify(serialized, null, 2)}`
  )
}

function summarizeTweetFallback(text: string): string {
  const cleaned = text.replace(/https?:\/\/\S+/g, '').replace(/\s+/g, ' ').trim()
  if (cleaned.length <= 210) {return cleaned}
  return `${cleaned.slice(0, 207).trim()}…`
}

export function buildDeterministicFallbackItems(
  candidates: readonly NormalizedTweet[],
  targetCount = 5,
): BriefItem[] {
  return candidates.slice(0, targetCount).map(c => {
    const firstSentence = c.text.replace(/https?:\/\/\S+/g, '').replace(/\s+/g, ' ').trim().split(/[.!?]\s/)[0] ?? ''
    const title = firstSentence.length > 15
      ? (firstSentence.length <= 85 ? firstSentence : `${firstSentence.slice(0, 82).trim()}…`)
      : `Cập nhật mới từ @${c.authorHandle}`
    return {
      axis: c.axis,
      title,
      summary: summarizeTweetFallback(c.text),
      authorHandle: c.authorHandle,
      url: c.url,
      ...(c.primaryUrl ? { primaryUrl: c.primaryUrl } : {}),
      isRecent12h: c.isRecent12h,
      sourceTweetId: c.id,
    }
  })
}

function extractJsonArraySlice(raw: string): unknown[] | null {
  const trimmed = raw.trim()
  const fenceMatch = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/i)
  const candidateText = (fenceMatch ? fenceMatch[1] : trimmed).trim()
  const start = candidateText.indexOf('[')
  const end = candidateText.lastIndexOf(']')
  if (start === -1 || end <= start) {return null}
  try {
    const parsed = JSON.parse(candidateText.slice(start, end + 1)) as unknown
    return Array.isArray(parsed) ? parsed : null
  } catch {
    return null
  }
}

/**
 * Validates model-edited JSON strictly against collected candidate IDs/URLs,
 * backfilling deterministically from top scored candidates if fewer than 5 valid items survive.
 */
export function parseAndValidateEditorialItems(
  rawResponse: string,
  candidates: readonly NormalizedTweet[],
  targetCount = 5,
): { items: BriefItem[]; usedFallback: boolean } {
  const byId = new Map(candidates.map(c => [c.id, c]))
  const parsed = extractJsonArraySlice(rawResponse)

  const selected: BriefItem[] = []
  const usedIds = new Set<string>()
  const usedEvents = new Set<string>()

  if (parsed) {
    for (const entry of parsed) {
      if (!entry || typeof entry !== 'object') {continue}
      const rec = entry as Record<string, unknown>
      const id = String(rec.id ?? '').trim()
      const matched = byId.get(id)
      if (!matched || usedIds.has(matched.id) || usedEvents.has(matched.eventKey)) {continue}

      const title = String(rec.title ?? '').trim()
      const summary = String(rec.summary ?? '').trim()
      if (!title || !summary) {continue}

      const rawAxis = String(rec.axis ?? matched.axis).trim() as BriefAxis
      const axis = VALID_AXES.has(rawAxis) ? rawAxis : matched.axis

      usedIds.add(matched.id)
      usedEvents.add(matched.eventKey)
      selected.push({
        axis,
        title: title.slice(0, 120),
        summary: summary.slice(0, 480),
        authorHandle: matched.authorHandle,
        url: matched.url,
        ...(matched.primaryUrl ? { primaryUrl: matched.primaryUrl } : {}),
        isRecent12h: matched.isRecent12h,
        sourceTweetId: matched.id,
      })
      if (selected.length >= targetCount) {break}
    }
  }

  let usedFallback = selected.length === 0
  if (selected.length < targetCount) {
    const remainingPool = candidates.filter(c => !usedIds.has(c.id) && !usedEvents.has(c.eventKey))
    const backfill = buildDeterministicFallbackItems(remainingPool, targetCount - selected.length)
    for (const item of backfill) {
      selected.push(item)
      usedFallback = true
    }
  }

  return { items: selected, usedFallback }
}
