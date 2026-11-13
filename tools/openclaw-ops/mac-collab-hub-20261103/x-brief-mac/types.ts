export type BriefAxis = 'coding' | 'products' | 'human_education'

export type XQuerySpec = {
  id: string
  layer: 'watchlist' | 'radar'
  axisHint: BriefAxis
  queryType: 'Latest' | 'Top'
  term: string
  maxItems: number
}

export type NormalizedTweet = {
  id: string
  url: string
  authorHandle: string
  authorName: string
  isVerified: boolean
  text: string
  createdAtIso: string
  createdAtMs: number
  isRecent12h: boolean
  likes: number
  retweets: number
  replies: number
  bookmarks: number
  views: number
  primaryUrl?: string
  queryTag?: string
  axis: BriefAxis
  score: number
  eventKey: string
}

export type HistoryEntry = {
  date: string
  url: string
  eventKey: string
  title: string
}

export type ApifyCreditSnapshot = {
  planId: string
  maxMonthlyUsageUsd: number
  monthlyUsageUsd: number
  remainingUsd: number
  lowCreditWarning: boolean
  blocked: boolean
  blockReason?: string
}

export type ApifyPricingCheck = {
  ok: boolean
  actorId: string
  reason?: string
  pricePerItemUsd?: number
}

export type ApifyCollectResult = {
  ok: boolean
  runId?: string
  datasetId?: string
  items: NormalizedTweet[]
  rawItemCount: number
  costUsd: number
  creditBefore: ApifyCreditSnapshot
  creditAfter?: ApifyCreditSnapshot
  durationMs: number
  error?: string
}

export type BriefItem = {
  axis: BriefAxis
  title: string
  summary: string
  authorHandle: string
  url: string
  primaryUrl?: string
  isRecent12h: boolean
  sourceTweetId: string
}

export type XBriefMode = 'scheduled' | 'test' | 'dry-run'

export type RunXBriefResult =
  | {
      ok: true
      mode: XBriefMode
      dateKey: string
      skipped?: boolean
      skipReason?: string
      message: string
      items: BriefItem[]
      rawItemCount: number
      candidateCount: number
      costUsd: number
      remainingUsd: number
      durationSeconds: number
      artifactsDir: string
    }
  | {
      ok: false
      mode: XBriefMode
      dateKey: string
      stage: 'token' | 'credit' | 'pricing' | 'collect' | 'edit'
      error: string
      remainingUsd?: number
      durationSeconds: number
    }
