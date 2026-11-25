import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'
import { redactSensitiveOutput } from '../lib/collab-gate.ts'
import type { CollectedHandoverItem, CollectedLessonItem, CollectedSessionItem, WeeklyDigest } from './types.ts'

const DAY_MS = 24 * 60 * 60 * 1000
const DEFAULT_WINDOW_DAYS = 7
const DEFAULT_MAX_HANDOVERS = 6
const DEFAULT_MAX_SESSIONS = 10
const DEFAULT_MAX_LESSONS = 6
const DEFAULT_MAX_USER_HIGHLIGHTS = 4
const DEFAULT_MAX_FRICTION_HIGHLIGHTS = 3

function sanitizeText(raw: string, maxChars: number): string {
  const redacted = redactSensitiveOutput(raw)
    .replace(/\b\d{8,13}\b/g, '[ID]')
    .replace(/\s+/g, ' ')
    .trim()
  if (redacted.length <= maxChars) {
    return redacted
  }
  return `${redacted.slice(0, Math.max(1, maxChars - 1)).trim()}…`
}

function toIsoDateInTimeZone(ms: number, timeZone = 'Asia/Ho_Chi_Minh'): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date(ms))
  const map = Object.fromEntries(parts.map(p => [p.type, p.value]))
  return `${map.year}-${map.month}-${map.day}`
}

/**
 * Computes ISO-8601 week key (`YYYY-Www`) and numeric year/week for a `YYYY-MM-DD` date key.
 */
export function getIsoWeekParts(dateKey: string): { isoYear: number; weekNumber: number; weekKey: string } {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateKey)
  const date = m ? new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]))) : new Date()
  const dayNum = date.getUTCDay() || 7
  date.setUTCDate(date.getUTCDate() + 4 - dayNum)
  const isoYear = date.getUTCFullYear()
  const yearStart = new Date(Date.UTC(isoYear, 0, 1))
  const weekNumber = Math.ceil(((date.getTime() - yearStart.getTime()) / DAY_MS + 1) / 7)
  return {
    isoYear,
    weekNumber,
    weekKey: `${isoYear}-W${String(weekNumber).padStart(2, '0')}`,
  }
}

function collectHandovers(params: {
  handoversDir?: string
  cutoffMs: number
  maxItems: number
}): CollectedHandoverItem[] {
  if (!params.handoversDir || !existsSync(params.handoversDir)) {
    return []
  }

  const entries: Array<{ mtimeMs: number; item: CollectedHandoverItem }> = []
  let files: string[]
  try {
    files = readdirSync(params.handoversDir).filter(f => f.endsWith('.md'))
  } catch {
    return []
  }

  for (const fileName of files) {
    const fullPath = join(params.handoversDir, fileName)
    try {
      const st = statSync(fullPath)
      if (!st.isFile() || st.mtimeMs < params.cutoffMs) {
        continue
      }
      const raw = readFileSync(fullPath, 'utf8')
      const excerpt = sanitizeText(raw, 1100)
      if (!excerpt) {
        continue
      }
      const safeName = fileName.replace(/-?\d{7,}/g, 'chat').replace(/\.md$/, '')
      entries.push({
        mtimeMs: st.mtimeMs,
        item: {
          sourceName: safeName || 'handover',
          updatedAtIso: new Date(st.mtimeMs).toISOString(),
          excerpt,
        },
      })
    } catch {
      continue
    }
  }

  return entries
    .toSorted((a, b) => b.mtimeMs - a.mtimeMs)
    .slice(0, params.maxItems)
    .map(e => e.item)
}

type TranscriptLine = {
  type?: string
  status?: string
  content?: string
  created_at?: string
}

function isAutomatedOrCanaryInput(text: string): boolean {
  return (
    text.includes('HANDOVER_AUTO') ||
    text.includes('Idea & Retro Miner') ||
    /biên tập viên bản tin sáng công nghệ/i.test(text) ||
    /Strictly test tool permissions once|Owner-authorized (?:change|permission test)|\.decoy-canary-claude|canary-group-readonly|\/private\/tmp\/agy-probe|Không dùng tool\. Trả lời: (?:MỘT|HAI)|Call read_file on lines 1 to 5 of/i.test(
      text,
    )
  )
}

function parseTranscriptFile(params: {
  sessionId: string
  filePath: string
  mtimeMs: number
  cutoffMs: number
}): CollectedSessionItem | null {
  let raw: string
  try {
    raw = readFileSync(params.filePath, 'utf8')
  } catch {
    return null
  }

  const allUserInputs: string[] = []
  const frictionHighlights: string[] = []
  let userInputsCount = 0
  let toolDenialCount = 0
  let errorStepCount = 0
  let sawSkippedAutomatedInput = false
  let latestMs = params.mtimeMs

  for (const line of raw.split('\n')) {
    const trimmed = line.trim()
    if (!trimmed) {
      continue
    }
    let parsed: TranscriptLine
    try {
      parsed = JSON.parse(trimmed) as TranscriptLine
    } catch {
      continue
    }

    const createdMs = parsed.created_at ? Date.parse(parsed.created_at) : Number.NaN
    if (Number.isFinite(createdMs)) {
      if (createdMs < params.cutoffMs) {
        continue
      }
      if (createdMs > latestMs) {
        latestMs = createdMs
      }
    }

    if (parsed.type === 'USER_INPUT' && typeof parsed.content === 'string') {
      const text = parsed.content.trim()
      if (!text) {
        continue
      }
      if (isAutomatedOrCanaryInput(text)) {
        sawSkippedAutomatedInput = true
        continue
      }
      userInputsCount += 1
      const sanitized = sanitizeText(text, 240)
      if (sanitized) {
        allUserInputs.push(sanitized)
      }
    }

    const stepType = typeof parsed.type === 'string' ? parsed.type.toUpperCase() : ''
    const isModelOrUserText = stepType === 'USER_INPUT' || stepType === 'PLANNER_RESPONSE'
    const status = String(parsed.status ?? '').toUpperCase()
    const content = typeof parsed.content === 'string' ? parsed.content : ''
    const hasDenial =
      !isModelOrUserText && /permission check failed|user denied permission|DANGEROUS_SHELL_RE/i.test(content)
    const hasError = !isModelOrUserText && (status === 'ERROR' || /Tool execution was canceled/i.test(content))

    if (hasDenial) {
      toolDenialCount += 1
    }
    if (hasError) {
      errorStepCount += 1
    }
    if ((hasDenial || hasError) && frictionHighlights.length < DEFAULT_MAX_FRICTION_HIGHLIGHTS && content) {
      frictionHighlights.push(sanitizeText(content, 200))
    }
  }

  if (
    (sawSkippedAutomatedInput && userInputsCount === 0) ||
    (userInputsCount === 0 && toolDenialCount === 0 && errorStepCount === 0)
  ) {
    return null
  }

  const meaningfulInputs = allUserInputs.filter(t => t.length >= 15)
  const userHighlights =
    meaningfulInputs.length > 0
      ? meaningfulInputs.slice(-DEFAULT_MAX_USER_HIGHLIGHTS)
      : allUserInputs.slice(-DEFAULT_MAX_USER_HIGHLIGHTS)

  return {
    sessionId: params.sessionId.slice(0, 8),
    updatedAtIso: new Date(latestMs).toISOString(),
    userInputsCount,
    toolDenialCount,
    errorStepCount,
    userHighlights,
    frictionHighlights,
  }
}

function collectSessions(params: { brainDir?: string; cutoffMs: number; maxItems: number }): CollectedSessionItem[] {
  if (!params.brainDir || !existsSync(params.brainDir)) {
    return []
  }

  const candidates: Array<{ mtimeMs: number; sessionId: string; filePath: string }> = []
  let subdirs: string[]
  try {
    subdirs = readdirSync(params.brainDir)
  } catch {
    return []
  }

  for (const dirName of subdirs) {
    const transcriptPath = join(params.brainDir, dirName, '.system_generated', 'logs', 'transcript.jsonl')
    try {
      if (!existsSync(transcriptPath)) {
        continue
      }
      const st = statSync(transcriptPath)
      if (!st.isFile() || st.mtimeMs < params.cutoffMs) {
        continue
      }
      candidates.push({ mtimeMs: st.mtimeMs, sessionId: dirName, filePath: transcriptPath })
    } catch {
      continue
    }
  }

  const sortedCandidates = candidates.toSorted((a, b) => b.mtimeMs - a.mtimeMs)

  const items: CollectedSessionItem[] = []
  for (const c of sortedCandidates) {
    if (items.length >= params.maxItems) {
      break
    }
    const parsed = parseTranscriptFile({
      sessionId: c.sessionId,
      filePath: c.filePath,
      mtimeMs: c.mtimeMs,
      cutoffMs: params.cutoffMs,
    })
    if (parsed) {
      items.push(parsed)
    }
  }

  return items
}

function collectRecentLessons(params: { lessonsDir?: string; maxItems: number }): CollectedLessonItem[] {
  if (!params.lessonsDir || !existsSync(params.lessonsDir)) {
    return []
  }

  let files: string[]
  try {
    files = readdirSync(params.lessonsDir)
      .filter(f => f.endsWith('.md'))
      .toSorted()
      .toReversed()
      .slice(0, params.maxItems)
  } catch {
    return []
  }

  const out: CollectedLessonItem[] = []
  for (const fileName of files) {
    try {
      const firstLine = readFileSync(join(params.lessonsDir, fileName), 'utf8')
        .split('\n')
        .find(line => line.trim().startsWith('#'))
      out.push({
        fileName,
        title: sanitizeText((firstLine ?? fileName).replace(/^#+\s*/, ''), 120),
      })
    } catch {
      continue
    }
  }
  return out
}

/**
 * Collects a bounded, redacted 7-day digest from local handovers, Antigravity transcripts, and lessons.
 * Runs in trusted TypeScript runtime so the downstream LLM step stays strict read-only (`plan` mode).
 */
export function collectWeeklyDigest(params: {
  handoversDir?: string
  brainDir?: string
  lessonsDir?: string
  nowMs?: number
  windowDays?: number
  maxHandovers?: number
  maxSessions?: number
  maxLessons?: number
}): WeeklyDigest {
  const nowMs = params.nowMs ?? Date.now()
  const windowDays = params.windowDays ?? DEFAULT_WINDOW_DAYS
  const cutoffMs = nowMs - windowDays * DAY_MS

  const windowEndDate = toIsoDateInTimeZone(nowMs)
  const windowStartDate = toIsoDateInTimeZone(cutoffMs)
  const weekParts = getIsoWeekParts(windowEndDate)

  return {
    weekKey: weekParts.weekKey,
    weekNumber: weekParts.weekNumber,
    isoYear: weekParts.isoYear,
    windowStartDate,
    windowEndDate,
    generatedAtIso: new Date(nowMs).toISOString(),
    handovers: collectHandovers({
      handoversDir: params.handoversDir,
      cutoffMs,
      maxItems: params.maxHandovers ?? DEFAULT_MAX_HANDOVERS,
    }),
    sessions: collectSessions({
      brainDir: params.brainDir,
      cutoffMs,
      maxItems: params.maxSessions ?? DEFAULT_MAX_SESSIONS,
    }),
    recentLessons: collectRecentLessons({
      lessonsDir: params.lessonsDir,
      maxItems: params.maxLessons ?? DEFAULT_MAX_LESSONS,
    }),
  }
}
