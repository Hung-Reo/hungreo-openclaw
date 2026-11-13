import { existsSync, readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { redactSensitiveOutput } from '../lib/collab-gate.ts'
import { DEFAULT_X_BRIEF_QUERIES, WINDOW_HOURS, buildApifySearchTerms, normalizeTweetItem } from './queries.ts'
import type {
  ApifyCollectResult,
  ApifyCreditSnapshot,
  ApifyPricingCheck,
  NormalizedTweet,
  XQuerySpec,
} from './types.ts'

export const APIFY_BASE_URL = 'https://api.apify.com/v2'
export const APIFY_ACTOR_ID = 'kaitoeasyapi~twitter-x-data-tweet-scraper-pay-per-result-cheapest'
export const APIFY_ACTOR_DISPLAY_NAME = 'kaitoeasyapi/twitter-x-data-tweet-scraper-pay-per-result-cheapest'
export const MAX_CHARGE_PER_RUN_USD = 0.08
export const MIN_SHARED_CREDIT_FLOOR_USD = 0.50 // preserves Rùa's $0.34 reserve+cap with buffer
export const LOW_CREDIT_WARNING_USD = 1.20
export const MAX_ALLOWED_ITEM_PRICE_USD = 0.00025

export type FetchLike = typeof fetch

export function resolveApifyToken(
  env: Record<string, string | undefined> = process.env,
  homeDir = homedir(),
): string | null {
  const fromEnv = (env.APIFY_API_TOKEN ?? env.APIFY_TOKEN ?? '').trim()
  if (fromEnv) {return fromEnv}

  const candidateFiles = [
    env.APIFY_TOKEN_FILE?.trim(),
    join(homeDir, '.config', 'apify', 'token'),
  ].filter((p): p is string => Boolean(p))

  for (const filePath of candidateFiles) {
    if (!existsSync(filePath)) {continue}
    try {
      const raw = readFileSync(filePath, 'utf8').trim()
      if (!raw) {continue}
      const match = raw.match(/^(?:APIFY_API_TOKEN\s*=\s*)?(.+)$/m)
      const val = match?.[1]?.trim()
      if (val) {return val}
    } catch {
      // Ignore unreadable candidate file
    }
  }
  return null
}

async function fetchApifyJson(
  url: string,
  token: string,
  init: RequestInit = {},
  fetchFn: FetchLike = fetch,
  timeoutMs = 30_000,
): Promise<Record<string, unknown>> {
  const res = await fetchFn(url, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(init.body ? { 'Content-Type': 'application/json' } : {}),
      ...init.headers,
    },
    signal: AbortSignal.timeout(timeoutMs),
  })
  const text = await res.text()
  if (!res.ok) {
    throw new Error(redactSensitiveOutput(`Apify HTTP ${res.status}: ${text.slice(0, 200)}`))
  }
  return JSON.parse(text) as Record<string, unknown>
}

export async function checkApifyCredits(
  token: string,
  fetchFn: FetchLike = fetch,
): Promise<ApifyCreditSnapshot> {
  const [mePayload, limitsPayload] = await Promise.all([
    fetchApifyJson(`${APIFY_BASE_URL}/users/me`, token, {}, fetchFn),
    fetchApifyJson(`${APIFY_BASE_URL}/users/me/limits`, token, {}, fetchFn),
  ])

  const meData = (mePayload.data ?? {}) as Record<string, unknown>
  const plan = (meData.plan ?? {}) as Record<string, unknown>
  const planId = String(plan.id ?? 'UNKNOWN')

  const limitsData = (limitsPayload.data ?? {}) as Record<string, unknown>
  const limits = (limitsData.limits ?? {}) as Record<string, unknown>
  const current = (limitsData.current ?? {}) as Record<string, unknown>

  const maxMonthlyUsageUsd = Number(limits.maxMonthlyUsageUsd ?? 0)
  const monthlyUsageUsd = Number(current.monthlyUsageUsd ?? 0)
  const remainingUsd = Number(Math.max(0, maxMonthlyUsageUsd - monthlyUsageUsd).toFixed(4))

  let blocked = false
  let blockReason: string | undefined
  if (planId !== 'FREE') {
    blocked = true
    blockReason = `Gói Apify hiện tại là "${planId}" (yêu cầu gói FREE để chống phát sinh phí thẻ).`
  } else if (!Number.isFinite(maxMonthlyUsageUsd) || maxMonthlyUsageUsd <= 0) {
    blocked = true
    blockReason = 'Không xác định được maxMonthlyUsageUsd từ Apify limits.'
  } else if (remainingUsd < MIN_SHARED_CREDIT_FLOOR_USD) {
    blocked = true
    blockReason = `Credit Apify còn ~$${remainingUsd.toFixed(4)} (< ngưỡng bảo vệ chung $${MIN_SHARED_CREDIT_FLOOR_USD.toFixed(2)} để chừa cho Rùa).`
  }

  return {
    planId,
    maxMonthlyUsageUsd,
    monthlyUsageUsd,
    remainingUsd,
    lowCreditWarning: remainingUsd < LOW_CREDIT_WARNING_USD,
    blocked,
    ...(blockReason ? { blockReason } : {}),
  }
}

export async function verifyApifyActorPricing(
  token: string,
  fetchFn: FetchLike = fetch,
): Promise<ApifyPricingCheck> {
  const payload = await fetchApifyJson(`${APIFY_BASE_URL}/acts/${APIFY_ACTOR_ID}`, token, {}, fetchFn)
  const data = (payload.data ?? {}) as Record<string, unknown>
  const pricingInfos = Array.isArray(data.pricingInfos) ? data.pricingInfos : []
  if (pricingInfos.length === 0) {
    return { ok: false, actorId: APIFY_ACTOR_DISPLAY_NAME, reason: 'Không tìm thấy pricingInfos trên actor Apify.' }
  }

  // Pick the latest active pricing info entry.
  const latestPricing = pricingInfos[pricingInfos.length - 1] as Record<string, unknown>
  const pricingModel = String(latestPricing.pricingModel ?? '')
  if (pricingModel !== 'PAY_PER_EVENT') {
    return {
      ok: false,
      actorId: APIFY_ACTOR_DISPLAY_NAME,
      reason: `Actor đổi pricingModel thành "${pricingModel}" (không còn PAY_PER_EVENT).`,
    }
  }

  const eventsObj = (latestPricing.pricingPerEvent && typeof latestPricing.pricingPerEvent === 'object'
    ? (latestPricing.pricingPerEvent as Record<string, unknown>).actorChargeEvents
    : undefined) as Record<string, unknown> | undefined
  if (!eventsObj || typeof eventsObj !== 'object') {
    return {
      ok: false,
      actorId: APIFY_ACTOR_DISPLAY_NAME,
      reason: 'Không đọc được actorChargeEvents của actor.',
    }
  }

  const eventKeys = Object.keys(eventsObj)
  if (eventKeys.length !== 1 || eventKeys[0] !== 'apify-default-dataset-item') {
    return {
      ok: false,
      actorId: APIFY_ACTOR_DISPLAY_NAME,
      reason: `Actor thay đổi danh sách charge events: [${eventKeys.join(', ')}].`,
    }
  }

  const itemEvent = eventsObj['apify-default-dataset-item'] as Record<string, unknown>
  const tiered = (itemEvent.eventTieredPricingUsd ?? {}) as Record<string, Record<string, unknown>>
  const rawPrice =
    itemEvent.eventPriceUsd ??
    tiered.FREE?.tieredEventPriceUsd ??
    tiered.BRONZE?.tieredEventPriceUsd
  const pricePerItemUsd = Number(rawPrice)

  if (!Number.isFinite(pricePerItemUsd) || pricePerItemUsd > MAX_ALLOWED_ITEM_PRICE_USD) {
    return {
      ok: false,
      actorId: APIFY_ACTOR_DISPLAY_NAME,
      reason: `Đơn giá actor ($${rawPrice}/item) vượt trần an toàn $${MAX_ALLOWED_ITEM_PRICE_USD}.`,
      ...(Number.isFinite(pricePerItemUsd) ? { pricePerItemUsd } : {}),
    }
  }

  return {
    ok: true,
    actorId: APIFY_ACTOR_DISPLAY_NAME,
    pricePerItemUsd,
  }
}

export async function runApifyCollection(params: {
  token: string
  queries?: readonly XQuerySpec[]
  nowMs?: number
  fetchFn?: FetchLike
  skipPricingCheck?: boolean
}): Promise<ApifyCollectResult> {
  const startedAt = Date.now()
  const nowMs = params.nowMs ?? Date.now()
  const fetchFn = params.fetchFn ?? fetch
  const queries = params.queries ?? DEFAULT_X_BRIEF_QUERIES

  const creditBefore = await checkApifyCredits(params.token, fetchFn)
  if (creditBefore.blocked) {
    return {
      ok: false,
      items: [],
      rawItemCount: 0,
      costUsd: 0,
      creditBefore,
      durationMs: Date.now() - startedAt,
      error: creditBefore.blockReason,
    }
  }

  if (!params.skipPricingCheck) {
    const pricing = await verifyApifyActorPricing(params.token, fetchFn)
    if (!pricing.ok) {
      return {
        ok: false,
        items: [],
        rawItemCount: 0,
        costUsd: 0,
        creditBefore,
        durationMs: Date.now() - startedAt,
        error: pricing.reason,
      }
    }
  }

  // Keep per-term cap aligned with Rùa (~25-30/term, ~180-240 items total) alongside maxTotalChargeUsd=0.08.
  const searchTerms = buildApifySearchTerms(queries, nowMs, WINDOW_HOURS)
  const actorInput = {
    searchTerms,
    queryType: 'Latest',
    maxItems: 30,
    lang: 'en',
  }

  const runUrl = `${APIFY_BASE_URL}/acts/${APIFY_ACTOR_ID}/runs?waitForFinish=60&maxTotalChargeUsd=${MAX_CHARGE_PER_RUN_USD}&timeout=120&memory=256`
  let runPayload = await fetchApifyJson(
    runUrl,
    params.token,
    {
      method: 'POST',
      body: JSON.stringify(actorInput),
    },
    fetchFn,
    75_000,
  )

  let runData = (runPayload.data ?? {}) as Record<string, unknown>
  const runId = String(runData.id ?? '')
  let status = String(runData.status ?? '')

  // At most 1 follow-up wait request if the actor took > 60s; never loop blindly.
  if (runId && (status === 'READY' || status === 'RUNNING')) {
    runPayload = await fetchApifyJson(
      `${APIFY_BASE_URL}/actor-runs/${runId}?waitForFinish=60`,
      params.token,
      {},
      fetchFn,
      75_000,
    )
    runData = (runPayload.data ?? {}) as Record<string, unknown>
    status = String(runData.status ?? '')
  }

  if (status !== 'SUCCEEDED') {
    return {
      ok: false,
      runId,
      items: [],
      rawItemCount: 0,
      costUsd: Number(runData.usageTotalUsd ?? 0),
      creditBefore,
      durationMs: Date.now() - startedAt,
      error: `Apify run ${runId || 'unknown'} kết thúc với trạng thái "${status || 'UNKNOWN'}".`,
    }
  }

  const datasetId = String(runData.defaultDatasetId ?? '')
  const costUsd = Number(runData.usageTotalUsd ?? 0)
  if (!datasetId) {
    return {
      ok: false,
      runId,
      items: [],
      rawItemCount: 0,
      costUsd,
      creditBefore,
      durationMs: Date.now() - startedAt,
      error: 'Apify run thành công nhưng thiếu defaultDatasetId.',
    }
  }

  const dsRes = await fetchFn(`${APIFY_BASE_URL}/datasets/${datasetId}/items?clean=true&format=json`, {
    headers: { Authorization: `Bearer ${params.token}` },
    signal: AbortSignal.timeout(30_000),
  })
  if (!dsRes.ok) {
    throw new Error(`Không tải được dataset ${datasetId} (HTTP ${dsRes.status})`)
  }
  const rawList = (await dsRes.json()) as unknown
  const rawRecords = Array.isArray(rawList)
    ? rawList.filter((item): item is Record<string, unknown> => Boolean(item && typeof item === 'object'))
    : []

  const normalized: NormalizedTweet[] = []
  for (const rec of rawRecords) {
    const tweet = normalizeTweetItem(rec, nowMs, WINDOW_HOURS)
    if (tweet) {normalized.push(tweet)}
  }

  const creditAfter = await checkApifyCredits(params.token, fetchFn).catch(() => undefined)
  return {
    ok: true,
    runId,
    datasetId,
    items: normalized,
    rawItemCount: rawRecords.length,
    costUsd,
    creditBefore,
    ...(creditAfter ? { creditAfter } : {}),
    durationMs: Date.now() - startedAt,
  }
}
