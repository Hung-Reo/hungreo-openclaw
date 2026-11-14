import type { BottleneckNote, IdeaEntry, IdeaMinerReport, SkillProposalEntry, WeeklyDigest } from './types.ts'

const MAX_IDEAS = 2
const MAX_SKILL_PROPOSALS = 2

/**
 * Builds a strict read-only grounding prompt for Gemini on Mac so it synthesizes the weekly
 * Idea & Retro brief solely from the redacted digest without invoking tools or modifying files.
 */
export function buildIdeaMinerPrompt(digest: WeeklyDigest): string {
  return (
    `Bạn là trợ lý phân tích tuần (Idea & Retro Miner) cho anh Hưng (founder công nghệ, dùng RUUME, OpenClaw, Antigravity, Claude Code).\n` +
    `TUYỆT ĐỐI KHÔNG gọi bất kỳ tool, lệnh shell, đọc hay sửa file nào. Chỉ dùng đúng JSON digest dưới đây.\n\n` +
    `Nhiệm vụ:\n` +
    `1. "ideas" (tối đa ${MAX_IDEAS} mục): nhặt lại ý tưởng sản phẩm/quy trình giá trị nhất anh Hưng từng nêu trong tuần, giữ nguyên lý do gốc ("whyFromOwner"), đề xuất 1 bước thử nhỏ nhất (< 1 ngày), kèm nguồn ngắn gọn ("sourceRef").\n` +
    `2. "skillProposals" (tối đa ${MAX_SKILL_PROPOSALS} mục): tìm điểm bot bị sửa/nhắc lại hoặc vướng quyền lặp lại, viết bản nháp rule/skill ngắn gọn để chờ anh Hưng duyệt GO (không tự ý áp dụng).\n` +
    `3. "bottleneck": chỉ ra 1 điểm nghẽn hiệu suất rõ nhất tuần qua và 1 gợi ý khắc phục gọn.\n` +
    `- Viết bằng tiếng Việt súc tích, thực tế, không hoa mỹ.\n` +
    `- Không lặp lại bài học đã có sẵn trong "recentLessons" trừ khi tuần này tái diễn.\n\n` +
    `Trả về DUY NHẤT 1 JSON object hợp lệ (không thêm chữ ngoài JSON):\n` +
    `{\n` +
    `  "ideas": [{"projectTag":"...","title":"...","whyFromOwner":"...","smallestNextStep":"...","sourceRef":"..."}],\n` +
    `  "skillProposals": [{"repeatTag":"...","issueTitle":"...","draftRuleOrSkill":"...","targetRef":"..."}],\n` +
    `  "bottleneck": {"summary":"...","suggestion":"..."}\n` +
    `}\n\n` +
    `Digest tuần ${digest.weekKey} (${digest.windowStartDate}..${digest.windowEndDate}):\n` +
    JSON.stringify(digest, null, 2)
  )
}

function extractJsonObjectSlice(raw: string): Record<string, unknown> | null {
  const trimmed = raw.trim()
  const fenceMatch = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/i)
  const candidate = (fenceMatch ? fenceMatch[1] : trimmed).trim()
  const start = candidate.indexOf('{')
  const end = candidate.lastIndexOf('}')
  if (start === -1 || end <= start) {
    return null
  }
  try {
    const parsed = JSON.parse(candidate.slice(start, end + 1)) as unknown
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? (parsed as Record<string, unknown>) : null
  } catch {
    return null
  }
}

export function buildDeterministicFallbackReport(digest: WeeklyDigest): IdeaMinerReport {
  const totalDenials = digest.sessions.reduce((sum, s) => sum + s.toolDenialCount, 0)
  const totalErrors = digest.sessions.reduce((sum, s) => sum + s.errorStepCount, 0)
  const topSession = digest.sessions[0]
  const topHandover = digest.handovers[0]

  const ideas: IdeaEntry[] = []
  if (topSession && topSession.userHighlights[0]) {
    ideas.push({
      projectTag: 'Workflow',
      title: 'Rà soát lại mạch trao đổi trọng tâm tuần qua',
      whyFromOwner: topSession.userHighlights[0].slice(0, 180),
      smallestNextStep: 'Xem lại handover/transcript phiên mới nhất và chốt 1 việc làm trước.',
      sourceRef: `phiên ${topSession.sessionId}`,
    })
  } else if (topHandover) {
    ideas.push({
      projectTag: 'Handover',
      title: 'Theo tiếp đầu việc còn mở trong handover gần nhất',
      whyFromOwner: topHandover.excerpt.slice(0, 180),
      smallestNextStep: 'Chọn 1 đầu việc nhỏ nhất để kiểm chứng trong ngày.',
      sourceRef: topHandover.sourceName,
    })
  }

  const skillProposals: SkillProposalEntry[] = []
  if (totalDenials > 0) {
    skillProposals.push({
      repeatTag: `Chặn quyền ${totalDenials} lần`,
      issueTitle: 'Giảm lệnh shell chạm deny/ask khi đọc code',
      draftRuleOrSkill:
        'Ưu tiên dùng read_file đọc code theo dải dòng thay vì chạy rg/grep có ký tự "|" hoặc lệnh ngoài allowlist.',
      targetRef: 'Chờ anh GO vào skill/rule',
    })
  }

  const bottleneck: BottleneckNote =
    totalDenials > 0 || totalErrors > 0
      ? {
          summary: `Tuần qua ghi nhận ${totalDenials} lần chạm permission denial và ${totalErrors} bước lỗi/huỷ.`,
          suggestion: 'Kiểm tra gemini-collab-settings.json trước khi chạy lệnh shell và ưu tiên read_file.',
        }
      : {
          summary: `Đã quét ${digest.sessions.length} phiên và ${digest.handovers.length} handover; chưa thấy lỗi lặp đáng kể.`,
          suggestion: 'Giữ nguyên nhịp handover và kiểm tra định kỳ mỗi sáng Thứ 2.',
        }

  return {
    weekKey: digest.weekKey,
    weekNumber: digest.weekNumber,
    isoYear: digest.isoYear,
    windowStartDate: digest.windowStartDate,
    windowEndDate: digest.windowEndDate,
    sessionsScanned: digest.sessions.length,
    handoversScanned: digest.handovers.length,
    ideas,
    skillProposals,
    bottleneck,
    usedFallbackEditor: true,
  }
}

function readTrimmedString(val: unknown, fallback = ''): string {
  return typeof val === 'string' ? val.trim() : fallback
}

function clampString(val: string, maxLen: number): string {
  if (val.length <= maxLen) {
    return val
  }
  return `${val.slice(0, Math.max(0, maxLen - 1)).trimEnd()}…`
}

function normalizeIdeas(rawIdeas: unknown): IdeaEntry[] {
  if (!Array.isArray(rawIdeas)) {
    return []
  }
  const out: IdeaEntry[] = []
  for (const item of rawIdeas) {
    if (!item || typeof item !== 'object') {
      continue
    }
    const rec = item as Record<string, unknown>
    const title = readTrimmedString(rec.title)
    const whyFromOwner = readTrimmedString(rec.whyFromOwner)
    const smallestNextStep = readTrimmedString(rec.smallestNextStep)
    if (!title || !whyFromOwner || !smallestNextStep) {
      continue
    }
    out.push({
      projectTag: clampString(readTrimmedString(rec.projectTag, 'Chung'), 40) || 'Chung',
      title: clampString(title, 140),
      whyFromOwner: clampString(whyFromOwner, 280),
      smallestNextStep: clampString(smallestNextStep, 240),
      sourceRef: clampString(readTrimmedString(rec.sourceRef, 'log tuần'), 120) || 'log tuần',
    })
    if (out.length >= MAX_IDEAS) {
      break
    }
  }
  return out
}

function normalizeSkillProposals(rawProposals: unknown): SkillProposalEntry[] {
  if (!Array.isArray(rawProposals)) {
    return []
  }
  const out: SkillProposalEntry[] = []
  for (const item of rawProposals) {
    if (!item || typeof item !== 'object') {
      continue
    }
    const rec = item as Record<string, unknown>
    const issueTitle = readTrimmedString(rec.issueTitle)
    const draftRuleOrSkill = readTrimmedString(rec.draftRuleOrSkill)
    if (!issueTitle || !draftRuleOrSkill) {
      continue
    }
    out.push({
      repeatTag: clampString(readTrimmedString(rec.repeatTag, 'Đề xuất'), 40) || 'Đề xuất',
      issueTitle: clampString(issueTitle, 140),
      draftRuleOrSkill: clampString(draftRuleOrSkill, 320),
      targetRef: clampString(readTrimmedString(rec.targetRef, 'Chờ anh GO'), 120) || 'Chờ anh GO',
    })
    if (out.length >= MAX_SKILL_PROPOSALS) {
      break
    }
  }
  return out
}

/**
 * Parses and validates model JSON output strictly; falls back deterministically if invalid or empty.
 */
export function parseAndValidateIdeaMinerOutput(rawResponse: string, digest: WeeklyDigest): IdeaMinerReport {
  const parsed = extractJsonObjectSlice(rawResponse)
  const fallback = buildDeterministicFallbackReport(digest)
  if (!parsed) {
    return fallback
  }

  const ideas = normalizeIdeas(parsed.ideas)
  const skillProposals = normalizeSkillProposals(parsed.skillProposals)

  const rawBottleneck =
    parsed.bottleneck && typeof parsed.bottleneck === 'object' && !Array.isArray(parsed.bottleneck)
      ? (parsed.bottleneck as Record<string, unknown>)
      : null
  const summary = readTrimmedString(rawBottleneck?.summary)
  const suggestion = readTrimmedString(rawBottleneck?.suggestion)

  if (ideas.length === 0 && skillProposals.length === 0 && !summary) {
    return fallback
  }

  return {
    weekKey: digest.weekKey,
    weekNumber: digest.weekNumber,
    isoYear: digest.isoYear,
    windowStartDate: digest.windowStartDate,
    windowEndDate: digest.windowEndDate,
    sessionsScanned: digest.sessions.length,
    handoversScanned: digest.handovers.length,
    ideas,
    skillProposals,
    bottleneck:
      summary && suggestion
        ? { summary: clampString(summary, 300), suggestion: clampString(suggestion, 260) }
        : fallback.bottleneck,
    usedFallbackEditor: false,
  }
}
