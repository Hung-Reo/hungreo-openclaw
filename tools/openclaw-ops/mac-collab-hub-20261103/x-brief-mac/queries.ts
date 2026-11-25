import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'
import type { BriefAxis, HistoryEntry, NormalizedTweet, XQuerySpec } from './types.ts'

export const WINDOW_HOURS = 48
export const RECENT_12H_MS = 12 * 60 * 60 * 1000
export const HISTORY_RETENTION_DAYS = 7

/**
 * Dual-layer X search queries:
 * - Layer 1 (Watchlist / Latest): core AI labs, coding-agent builders, Gemini 4 Hydrogen, and educators.
 * - Layer 2 (Radar / Top): catches high-signal discussions outside fixed accounts without blowing item budget.
 */
export const DEFAULT_X_BRIEF_QUERIES: readonly XQuerySpec[] = [
  {
    id: 'w1_codex_builders',
    layer: 'watchlist',
    axisHint: 'coding',
    queryType: 'Latest',
    term: '(from:thsottiaux OR from:paulabartabajo_ OR from:steipete)',
    maxItems: 24,
  },
  {
    id: 'w2_claude_openai_devs',
    layer: 'watchlist',
    axisHint: 'coding',
    queryType: 'Latest',
    term: '(from:ClaudeDevs OR from:OpenAIDevs OR from:AnthropicAI)',
    maxItems: 26,
  },
  {
    id: 'w3_google_hydrogen',
    layer: 'watchlist',
    axisHint: 'products',
    queryType: 'Latest',
    term: '(from:GoogleDeepMind OR from:sundarpichai OR from:GoogleAI)',
    maxItems: 26,
  },
  {
    id: 'w4_antigravity_hydrogen',
    layer: 'watchlist',
    axisHint: 'coding',
    queryType: 'Latest',
    term: '(Antigravity OR "Gemini 4 Hydrogen" OR "Gemini Hydrogen") (Gemini OR Google OR CLI OR IDE) -filter:replies',
    maxItems: 20,
  },
  {
    id: 'w5_agentic_oss',
    layer: 'watchlist',
    axisHint: 'coding',
    queryType: 'Latest',
    term: '(from:NousResearch OR from:HermesAgentTips OR openclaw)',
    maxItems: 20,
  },
  {
    id: 'w6_ai_labs_product',
    layer: 'watchlist',
    axisHint: 'products',
    queryType: 'Latest',
    term: '(from:openai OR from:sama OR from:GoogleLabs)',
    maxItems: 24,
  },
  {
    id: 'w7_human_edu',
    layer: 'watchlist',
    axisHint: 'human_education',
    queryType: 'Latest',
    term: '(from:emollick OR from:PeterDiamandis)',
    maxItems: 20,
  },
  {
    id: 'r1_coding_agents_top',
    layer: 'radar',
    axisHint: 'coding',
    queryType: 'Top',
    term: '("Claude Code" OR "Codex" OR "coding agent" OR "MCP") (release OR launch OR benchmark OR workflow) min_faves:80 -filter:replies',
    maxItems: 24,
  },
  {
    id: 'r2_ai_products_edu_top',
    layer: 'radar',
    axisHint: 'human_education',
    queryType: 'Top',
    term: '(AI OR LLM) (education OR learning OR workflow OR workspace) min_faves:120 -filter:replies',
    maxItems: 20,
  },
]

const OFFICIAL_HANDLES = new Set([
  'openai',
  'openaidevs',
  'anthropicai',
  'claudedevs',
  'googledeepmind',
  'googleai',
  'googlelabs',
  'sundarpichai',
  'sama',
  'steipete',
  'thsottiaux',
  'paulabartabajo_',
  'nousresearch',
  'hermesagenttips',
  'emollick',
  'peterdiamandis',
])

const CODING_RE = /\b(codex|claude code|coding agent|agentic coding|antigravity|mcp|cli|sdk|ide|openclaw|repo|github|typescript|python|compiler|benchmark|debug|terminal|hermes)\b/i
const EDU_RE = /\b(education|learning|student|teacher|school|university|parenting|child|human|training|curriculum|course|tutor|study|wharton)\b/i

/**
 * Formats a UTC timestamp `since:YYYY-MM-DD_HH:MM:SS_UTC` for X advanced search operators.
 */
export function formatApifySinceOperator(dateMs: number): string {
  const iso = new Date(dateMs).toISOString()
  return `since:${iso.slice(0, 10)}_${iso.slice(11, 19)}_UTC`
}

export function buildApifySearchTerms(
  queries: readonly XQuerySpec[] = DEFAULT_X_BRIEF_QUERIES,
  nowMs = Date.now(),
  windowHours = WINDOW_HOURS,
): string[] {
  const sinceOp = formatApifySinceOperator(nowMs - windowHours * 3600_000)
  return queries.map(q => `${q.term} ${sinceOp}`)
}

export function classifyAxis(text: string, authorHandle: string, fallbackAxis: BriefAxis = 'products'): BriefAxis {
  const handle = authorHandle.toLowerCase().replace(/^@/, '')
  if (handle === 'emollick' || handle === 'peterdiamandis') {
    return EDU_RE.test(text) ? 'human_education' : 'products'
  }
  if (CODING_RE.test(text)) {return 'coding'}
  if (EDU_RE.test(text)) {return 'human_education'}
  return fallbackAxis
}

export function canonicalizeXUrl(rawUrl: string): string {
  const trimmed = rawUrl.trim()
  if (!trimmed) {return ''}
  try {
    const parsed = new URL(trimmed)
    const host = parsed.hostname.toLowerCase() === 'twitter.com' ? 'x.com' : parsed.hostname.toLowerCase()
    const cleanPath = parsed.pathname.replace(/\/+$/, '')
    return `https://${host}${cleanPath}`
  } catch {
    return trimmed
  }
}

export function extractPrimaryExternalUrl(raw: Record<string, unknown>): string | undefined {
  const entities = raw.entities as Record<string, unknown> | undefined
  const urls = Array.isArray(entities?.urls) ? entities.urls : []
  for (const entry of urls) {
    if (!entry || typeof entry !== 'object') {continue}
    const rec = entry as Record<string, unknown>
    const expanded = typeof rec.expanded_url === 'string' ? rec.expanded_url : typeof rec.url === 'string' ? rec.url : ''
    if (!expanded) {continue}
    if (/^https?:\/\/(x\.com|twitter\.com|t\.co)\//i.test(expanded)) {continue}
    return expanded
  }
  return undefined
}

export function buildEventKey(text: string, primaryUrl?: string): string {
  if (primaryUrl) {
    try {
      const u = new URL(primaryUrl)
      return `url:${u.hostname.replace(/^www\./, '').toLowerCase()}${u.pathname.replace(/\/+$/, '').toLowerCase()}`
    } catch {}
  }
  const tokens = text
    .toLowerCase()
    .replace(/https?:\/\/\S+/g, ' ')
    .replace(/[^a-z0-9\s]/g, ' ')
    .split(/\s+/)
    .filter(w => w.length >= 4 && !['with', 'that', 'this', 'from', 'have', 'just', 'more', 'your', 'about'].includes(w))
    .slice(0, 8)
  return `txt:${tokens.join('-')}`
}

export function scoreTweetCandidate(params: {
  text: string
  authorHandle: string
  isVerified: boolean
  createdAtMs: number
  nowMs: number
  likes: number
  retweets: number
  bookmarks: number
  hasPrimaryUrl: boolean
}): number {
  const ageHours = Math.max(0, (params.nowMs - params.createdAtMs) / 3600_000)
  const freshness = ageHours <= 12 ? 30 : ageHours <= 24 ? 20 : 10
  const engagementRaw = params.likes + params.retweets * 2 + params.bookmarks * 2.5
  const engagementScore = Math.min(40, Math.log10(1 + Math.max(0, engagementRaw)) * 12)
  const officialBonus = OFFICIAL_HANDLES.has(params.authorHandle.toLowerCase().replace(/^@/, '')) ? 18 : 0
  const verifiedBonus = params.isVerified ? 5 : 0
  const linkBonus = params.hasPrimaryUrl ? 8 : 0
  const substantiveBonus = params.text.trim().length >= 90 ? 6 : 0
  return Number((freshness + engagementScore + officialBonus + verifiedBonus + linkBonus + substantiveBonus).toFixed(2))
}

function toFiniteNumber(val: unknown): number {
  if (typeof val === 'number' && Number.isFinite(val)) {return val}
  if (typeof val === 'string') {
    const n = Number(val)
    if (Number.isFinite(n)) {return n}
  }
  return 0
}

export function normalizeTweetItem(
  raw: Record<string, unknown>,
  nowMs = Date.now(),
  windowHours = WINDOW_HOURS,
): NormalizedTweet | null {
  if (raw.isRetweet === true || raw.retweeted_tweet) {return null}

  const text = String(raw.text ?? raw.fullText ?? '').trim()
  if (!text || /^RT @/i.test(text) || text.length < 30) {return null}

  const rawUrl = String(raw.url ?? raw.twitterUrl ?? '')
  const canonicalUrl = canonicalizeXUrl(rawUrl)
  if (!/^https:\/\/(x\.com|twitter\.com)\/.+\/status\/\d+/i.test(canonicalUrl)) {return null}

  const authorObj = (raw.author && typeof raw.author === 'object' ? raw.author : {}) as Record<string, unknown>
  const authorHandle = String(authorObj.userName ?? authorObj.username ?? raw.username ?? '')
    .replace(/^@/, '')
    .trim()
  if (!authorHandle) {return null}

  const createdRaw = String(raw.createdAt ?? '')
  const createdAtMs = createdRaw ? Date.parse(createdRaw) : Number.NaN
  if (!Number.isFinite(createdAtMs)) {return null}
  if (nowMs - createdAtMs > windowHours * 3600_000) {return null}

  const id = String(raw.id ?? canonicalUrl.split('/').pop() ?? '').trim()
  if (!id) {return null}

  const likes = toFiniteNumber(raw.likeCount ?? raw.likes)
  const retweets = toFiniteNumber(raw.retweetCount ?? raw.retweets)
  const replies = toFiniteNumber(raw.replyCount ?? raw.replies)
  const bookmarks = toFiniteNumber(raw.bookmarkCount ?? raw.bookmarks)
  const views = toFiniteNumber(raw.viewCount ?? raw.views)
  const isVerified = Boolean(authorObj.isBlueVerified ?? authorObj.isVerified ?? false)
  const primaryUrl = extractPrimaryExternalUrl(raw)
  const axis = classifyAxis(text, authorHandle)
  const score = scoreTweetCandidate({
    text,
    authorHandle,
    isVerified,
    createdAtMs,
    nowMs,
    likes,
    retweets,
    bookmarks,
    hasPrimaryUrl: Boolean(primaryUrl),
  })

  return {
    id,
    url: canonicalUrl,
    authorHandle,
    authorName: String(authorObj.name ?? authorHandle).trim(),
    isVerified,
    text,
    createdAtIso: new Date(createdAtMs).toISOString(),
    createdAtMs,
    isRecent12h: nowMs - createdAtMs <= RECENT_12H_MS,
    likes,
    retweets,
    replies,
    bookmarks,
    views,
    primaryUrl,
    axis,
    score,
    eventKey: buildEventKey(text, primaryUrl),
  }
}

/**
 * Deduplicates by tweet ID, canonical URL, and historical event keys, then picks
 * balanced top candidates across the 3 axes with cross-axis backfill when an axis is sparse.
 */
export function selectBalancedCandidates(params: {
  tweets: readonly NormalizedTweet[]
  history: readonly HistoryEntry[]
  limit?: number
}): NormalizedTweet[] {
  const limit = params.limit ?? 15
  const seenUrls = new Set(params.history.map(h => canonicalizeXUrl(h.url)))
  const seenEvents = new Set(params.history.map(h => h.eventKey))
  const seenIds = new Set<string>()

  const unique: NormalizedTweet[] = []
  const sorted = [...params.tweets].toSorted((a, b) => b.score - a.score)

  for (const t of sorted) {
    const canon = canonicalizeXUrl(t.url)
    if (seenIds.has(t.id) || seenUrls.has(canon) || seenEvents.has(t.eventKey)) {continue}
    seenIds.add(t.id)
    seenUrls.add(canon)
    seenEvents.add(t.eventKey)
    unique.push(t)
  }

  // Reserve up to 3 top candidates per axis first, then backfill remaining slots by overall score.
  const picked: NormalizedTweet[] = []
  const pickedIds = new Set<string>()
  const axes: BriefAxis[] = ['coding', 'products', 'human_education']

  for (const axis of axes) {
    let axisCount = 0
    for (const item of unique) {
      if (item.axis !== axis || pickedIds.has(item.id)) {continue}
      picked.push(item)
      pickedIds.add(item.id)
      axisCount++
      if (axisCount >= 3 || picked.length >= limit) {break}
    }
  }

  for (const item of unique) {
    if (picked.length >= limit) {break}
    if (pickedIds.has(item.id)) {continue}
    picked.push(item)
    pickedIds.add(item.id)
  }

  return picked.toSorted((a, b) => b.score - a.score)
}

export function loadHistory(historyPath: string, nowMs = Date.now()): HistoryEntry[] {
  if (!existsSync(historyPath)) {return []}
  try {
    const raw = JSON.parse(readFileSync(historyPath, 'utf8')) as unknown
    if (!Array.isArray(raw)) {return []}
    const cutoffMs = nowMs - HISTORY_RETENTION_DAYS * 86400_000
    return raw.filter((item): item is HistoryEntry => {
      if (!item || typeof item !== 'object') {return false}
      const rec = item as Partial<HistoryEntry>
      if (!rec.date || !rec.url || !rec.eventKey) {return false}
      const parsed = Date.parse(`${rec.date}T00:00:00Z`)
      return Number.isFinite(parsed) && parsed >= cutoffMs
    })
  } catch {
    return []
  }
}

export function appendHistory(historyPath: string, entries: readonly HistoryEntry[], nowMs = Date.now()): void {
  const existing = loadHistory(historyPath, nowMs)
  const seen = new Set(existing.map(e => canonicalizeXUrl(e.url)))
  const merged = [...existing]
  for (const item of entries) {
    const canon = canonicalizeXUrl(item.url)
    if (seen.has(canon)) {continue}
    seen.add(canon)
    merged.push({ ...item, url: canon })
  }
  mkdirSync(dirname(historyPath), { recursive: true, mode: 0o700 })
  const tmpPath = `${historyPath}.tmp`
  writeFileSync(tmpPath, JSON.stringify(merged, null, 2) + '\n', { mode: 0o600 })
  renameSync(tmpPath, historyPath)
}
