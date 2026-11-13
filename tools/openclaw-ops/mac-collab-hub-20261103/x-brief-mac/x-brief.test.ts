import { describe, expect, it } from 'bun:test'
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { isRuleBlockedByDeny } from '../gemini-telegram-bridge/permissions.ts'
import { redactSensitiveOutput } from '../lib/collab-gate.ts'
import {
  checkApifyCredits,
  resolveApifyToken,
  runApifyCollection,
  verifyApifyActorPricing,
  type FetchLike,
} from './apify-client.ts'
import { parseAndValidateEditorialItems } from './editor.ts'
import { formatXBriefTelegramMessage } from './formatter.ts'
import {
  DEFAULT_X_BRIEF_QUERIES,
  appendHistory,
  buildApifySearchTerms,
  loadHistory,
  normalizeTweetItem,
  selectBalancedCandidates,
} from './queries.ts'
import { runXBriefPipeline } from './runner.ts'
import { shouldTriggerDailyBrief } from './scheduler.ts'
import type { NormalizedTweet } from './types.ts'

function makeTweet(overrides: Partial<NormalizedTweet> & { id: string }): NormalizedTweet {
  return {
    id: overrides.id,
    url: overrides.url ?? `https://x.com/OpenAIDevs/status/${overrides.id}`,
    authorHandle: overrides.authorHandle ?? 'OpenAIDevs',
    authorName: overrides.authorName ?? 'OpenAI Devs',
    isVerified: overrides.isVerified ?? true,
    text: overrides.text ?? 'Shipping major new coding agent improvements for developer workflows today.',
    createdAtIso: overrides.createdAtIso ?? '2026-11-13T10:00:00.000Z',
    createdAtMs: overrides.createdAtMs ?? Date.parse('2026-11-13T10:00:00.000Z'),
    isRecent12h: overrides.isRecent12h ?? true,
    likes: overrides.likes ?? 500,
    retweets: overrides.retweets ?? 100,
    replies: overrides.replies ?? 20,
    bookmarks: overrides.bookmarks ?? 120,
    views: overrides.views ?? 20000,
    primaryUrl: overrides.primaryUrl,
    axis: overrides.axis ?? 'coding',
    score: overrides.score ?? 80,
    eventKey: overrides.eventKey ?? `txt:event-${overrides.id}`,
  }
}

function makeMockFetch(handlers: Record<string, (url: string, init?: RequestInit) => unknown>): FetchLike {
  return (async (input: string | URL | Request, init?: RequestInit) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url
    for (const [pattern, fn] of Object.entries(handlers)) {
      if (url.includes(pattern)) {
        const body = fn(url, init)
        return new Response(JSON.stringify(body), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      }
    }
    return new Response(JSON.stringify({ error: `unexpected url ${url}` }), { status: 404 })
  }) as FetchLike
}

describe('collab-gate Apify token redaction', () => {
  it('redacts apify_api_ tokens cleanly', () => {
    const out = redactSensitiveOutput('Bearer apify_api_SecretToken1234567890 in logs')
    expect(out).toBe('Bearer [REDACTED_APIFY_TOKEN] in logs')
  })
})

describe('queries & scoring', () => {
  it('updates Gemini 4 Hydrogen query and builds UTC since operators', () => {
    const terms = buildApifySearchTerms(DEFAULT_X_BRIEF_QUERIES, Date.UTC(2026, 10, 13, 12, 0, 0), 48)
    expect(terms.some(t => t.includes('Gemini 4 Hydrogen'))).toBe(true)
    expect(terms.every(t => t.includes('since:2026-11-11_12:00:00_UTC'))).toBe(true)
  })

  it('filters retweets and tweets older than 48h while normalizing valid tweets', () => {
    const nowMs = Date.UTC(2026, 10, 13, 12, 0, 0)
    const rt = normalizeTweetItem(
      {
        id: '1',
        isRetweet: true,
        text: 'RT @someone: Great coding agent update with long enough body text.',
        url: 'https://x.com/a/status/1',
        createdAt: new Date(nowMs - 3600_000).toISOString(),
        author: { userName: 'tester' },
      },
      nowMs,
    )
    expect(rt).toBeNull()

    const oldTweet = normalizeTweetItem(
      {
        id: '2',
        text: 'This is an old tweet from three days ago about coding agents.',
        url: 'https://x.com/a/status/2',
        createdAt: new Date(nowMs - 60 * 3600_000).toISOString(),
        author: { userName: 'tester' },
      },
      nowMs,
    )
    expect(oldTweet).toBeNull()

    const valid = normalizeTweetItem(
      {
        id: '3',
        text: 'Gemini 4 Hydrogen improves Antigravity CLI workflows and coding agent precision.',
        url: 'https://twitter.com/GoogleDeepMind/status/3',
        createdAt: new Date(nowMs - 2 * 3600_000).toISOString(),
        likeCount: 1200,
        retweetCount: 300,
        bookmarkCount: 400,
        author: { userName: 'GoogleDeepMind', name: 'Google DeepMind', isBlueVerified: true },
        entities: { urls: [{ expanded_url: 'https://deepmind.google/hydrogen' }] },
      },
      nowMs,
    )
    expect(valid).not.toBeNull()
    expect(valid?.url).toBe('https://x.com/GoogleDeepMind/status/3')
    expect(valid?.axis).toBe('coding')
    expect(valid?.isRecent12h).toBe(true)
    expect(valid?.primaryUrl).toBe('https://deepmind.google/hydrogen')
  })

  it('cross-backfills slots when one axis is empty and deduplicates against 7-day history', () => {
    const tmpDir = mkdtempSync(join(tmpdir(), 'x-brief-hist-'))
    try {
      const historyPath = join(tmpDir, 'history.json')
      const nowMs = Date.UTC(2026, 10, 13, 12, 0, 0)
      appendHistory(
        historyPath,
        [{ date: '2026-11-12', url: 'https://x.com/OpenAIDevs/status/101', eventKey: 'txt:dup', title: 'Old' }],
        nowMs,
      )
      const history = loadHistory(historyPath, nowMs)
      expect(history).toHaveLength(1)

      const pool: NormalizedTweet[] = [
        makeTweet({ id: '101', eventKey: 'txt:dup', axis: 'coding', score: 99 }), // duplicate URL+event
        makeTweet({ id: '102', axis: 'coding', score: 95 }),
        makeTweet({ id: '103', axis: 'coding', score: 92 }),
        makeTweet({ id: '104', axis: 'coding', score: 90 }),
        makeTweet({ id: '105', axis: 'coding', score: 88 }),
        makeTweet({ id: '106', axis: 'products', score: 86 }),
        // Intentionally zero human_education items -> must backfill to reach limit 5
      ]

      const picked = selectBalancedCandidates({ tweets: pool, history, limit: 5 })
      expect(picked).toHaveLength(5)
      expect(picked.some(p => p.id === '101')).toBe(false)
      expect(picked.some(p => p.axis === 'products')).toBe(true)
    } finally {
      rmSync(tmpDir, { recursive: true, force: true })
    }
  })
})

describe('apify-client guardrails', () => {
  it('resolves token from env or ~/.config/apify/token', () => {
    const tmpHome = mkdtempSync(join(tmpdir(), 'x-brief-home-'))
    try {
      mkdirSync(join(tmpHome, '.config', 'apify'), { recursive: true })
      writeFileSync(join(tmpHome, '.config', 'apify', 'token'), 'apify_api_FromFile12345\n')
      expect(resolveApifyToken({ APIFY_API_TOKEN: 'apify_api_FromEnv999' }, tmpHome)).toBe('apify_api_FromEnv999')
      expect(resolveApifyToken({}, tmpHome)).toBe('apify_api_FromFile12345')
    } finally {
      rmSync(tmpHome, { recursive: true, force: true })
    }
  })

  it('blocks when remaining credit drops below $0.50 floor or plan is not FREE', async () => {
    const lowFetch = makeMockFetch({
      '/users/me/limits': () => ({ data: { limits: { maxMonthlyUsageUsd: 5 }, current: { monthlyUsageUsd: 4.6 } } }),
      '/users/me': () => ({ data: { plan: { id: 'FREE' } } }),
    })
    const lowRes = await checkApifyCredits('apify_api_test', lowFetch)
    expect(lowRes.blocked).toBe(true)
    expect(lowRes.remainingUsd).toBeCloseTo(0.4, 4)

    const paidFetch = makeMockFetch({
      '/users/me/limits': () => ({ data: { limits: { maxMonthlyUsageUsd: 49 }, current: { monthlyUsageUsd: 1 } } }),
      '/users/me': () => ({ data: { plan: { id: 'STARTER' } } }),
    })
    const paidRes = await checkApifyCredits('apify_api_test', paidFetch)
    expect(paidRes.blocked).toBe(true)
  })

  it('blocks if actor pricing exceeds $0.00025/item', async () => {
    const expensiveFetch = makeMockFetch({
      '/acts/': () => ({
        data: {
          pricingInfos: [
            {
              pricingModel: 'PAY_PER_EVENT',
              pricingPerEvent: {
                actorChargeEvents: {
                  'apify-default-dataset-item': { eventPriceUsd: 0.002 },
                },
              },
            },
          ],
        },
      }),
    })
    const check = await verifyApifyActorPricing('apify_api_test', expensiveFetch)
    expect(check.ok).toBe(false)
  })

  it('collects and normalizes tweets when guardrails pass', async () => {
    const nowMs = Date.UTC(2026, 10, 13, 12, 0, 0)
    const okFetch = makeMockFetch({
      '/users/me/limits': () => ({ data: { limits: { maxMonthlyUsageUsd: 5 }, current: { monthlyUsageUsd: 0.9 } } }),
      '/users/me': () => ({ data: { plan: { id: 'FREE' } } }),
      '/acts/kaitoeasyapi~twitter-x-data-tweet-scraper-pay-per-result-cheapest/runs': () => ({
        data: { id: 'run_123', status: 'SUCCEEDED', defaultDatasetId: 'ds_123', usageTotalUsd: 0.045 },
      }),
      '/acts/kaitoeasyapi~twitter-x-data-tweet-scraper-pay-per-result-cheapest': () => ({
        data: {
          pricingInfos: [
            {
              pricingModel: 'PAY_PER_EVENT',
              pricingPerEvent: {
                actorChargeEvents: {
                  'apify-default-dataset-item': { eventPriceUsd: 0.00025 },
                },
              },
            },
          ],
        },
      }),
      '/datasets/ds_123/items': () => [
        {
          id: '777',
          text: 'Claude Code ships faster worktrees and Antigravity integration for coding agents.',
          url: 'https://x.com/ClaudeDevs/status/777',
          createdAt: new Date(nowMs - 3600_000).toISOString(),
          likeCount: 900,
          author: { userName: 'ClaudeDevs', name: 'Claude Devs', isBlueVerified: true },
        },
      ],
    })

    const res = await runApifyCollection({ token: 'apify_api_test', nowMs, fetchFn: okFetch })
    expect(res.ok).toBe(true)
    expect(res.costUsd).toBeCloseTo(0.045, 4)
    expect(res.items).toHaveLength(1)
    expect(res.items[0]?.id).toBe('777')
  })
})

describe('editor, formatter & scheduler', () => {
  it('rejects hallucinated IDs and falls back deterministically to 5 items', () => {
    const candidates = [1, 2, 3, 4, 5, 6].map(n => makeTweet({ id: String(n), score: 100 - n }))
    const raw = JSON.stringify([
      { id: '999', axis: 'coding', title: 'Fake ID', summary: 'Should be ignored' },
      { id: '1', axis: 'coding', title: 'Tin số 1 chuẩn', summary: 'Tóm tắt hợp lệ tin 1.' },
    ])
    const res = parseAndValidateEditorialItems(raw, candidates, 5)
    expect(res.items).toHaveLength(5)
    expect(res.usedFallback).toBe(true)
    expect(res.items[0]?.sourceTweetId).toBe('1')
    expect(res.items.some(i => i.sourceTweetId === '999')).toBe(false)
  })

  it('formats Telegram message with KPI footer and low-credit alert', () => {
    const msg = formatXBriefTelegramMessage({
      mode: 'test',
      dateKey: '2026-11-13',
      items: [
        {
          axis: 'coding',
          title: 'Gemini 4 Hydrogen ra mắt',
          summary: 'Cải thiện tốc độ suy luận và coding agent.',
          authorHandle: 'GoogleDeepMind',
          url: 'https://x.com/GoogleDeepMind/status/1',
          isRecent12h: true,
          sourceTweetId: '1',
        },
      ],
      rawItemCount: 195,
      costUsd: 0.0488,
      remainingUsd: 1.05,
      lowCreditWarning: true,
      durationSeconds: 18.4,
    })
    expect(msg).toContain('BẢN TIN X ĐỐI CHỨNG [TEST] — 13/11/2026')
    expect(msg).toContain('Cảnh báo credit Apify thấp')
    expect(msg).toContain('Xong trong 18.4s · 195 tweets thu về')
    expect(msg).toContain('phí $0.0488 · Free còn ~$1.0500')
  })

  it('triggers daily schedule only inside 06:30..06:59 Asia/Ho_Chi_Minh once per day', () => {
    // 06:29 VNT = 23:29 UTC previous day
    expect(
      shouldTriggerDailyBrief({
        now: new Date('2026-11-12T23:29:00Z'),
      }),
    ).toEqual({ shouldRun: false, dateKey: '2026-11-13' })

    // 06:30 VNT = 23:30 UTC previous day
    expect(
      shouldTriggerDailyBrief({
        now: new Date('2026-11-12T23:30:00Z'),
      }),
    ).toEqual({ shouldRun: true, dateKey: '2026-11-13' })

    // Already attempted today
    expect(
      shouldTriggerDailyBrief({
        now: new Date('2026-11-12T23:35:00Z'),
        lastAttemptDate: '2026-11-13',
      }),
    ).toEqual({ shouldRun: false, dateKey: '2026-11-13' })

    // 07:05 VNT = 00:05 UTC (outside 30m grace window)
    expect(
      shouldTriggerDailyBrief({
        now: new Date('2026-11-13T00:05:00Z'),
      }),
    ).toEqual({ shouldRun: false, dateKey: '2026-11-13' })
  })

  it('runs dry-run end-to-end and prevents duplicate scheduled runs on same day', async () => {
    const tmpState = mkdtempSync(join(tmpdir(), 'x-brief-state-'))
    try {
      const dry = await runXBriefPipeline({
        stateDir: tmpState,
        mode: 'dry-run',
        nowMs: Date.UTC(2026, 10, 13, 5, 0, 0),
        runEditorPrompt: async () => ({
          ok: true,
          text: JSON.stringify([
            { id: 'dry-1', axis: 'coding', title: 'Gemini 4 Hydrogen', summary: 'Bản cập nhật mới.' },
            { id: 'dry-2', axis: 'coding', title: 'Claude Code Worktrees', summary: 'Chạy song song mượt hơn.' },
            { id: 'dry-3', axis: 'coding', title: 'Codex CLI Specs', summary: 'Sandbox rõ ràng hơn.' },
            { id: 'dry-4', axis: 'products', title: 'Team Memory', summary: 'Chia sẻ context nhóm.' },
            { id: 'dry-5', axis: 'human_education', title: 'AI Critique Study', summary: 'Hiệu quả cho sinh viên.' },
          ]),
        }),
      })
      expect(dry.ok).toBe(true)
      if (dry.ok) {
        expect(dry.items).toHaveLength(5)
        expect(dry.message).toContain('BẢN TIN X ĐỐI CHỨNG [DRY-RUN]')
      }

      // First scheduled run writes daily brief.md; second scheduled run skips cleanly
      const schedFetch = makeMockFetch({
        '/users/me/limits': () => ({ data: { limits: { maxMonthlyUsageUsd: 5 }, current: { monthlyUsageUsd: 0.9 } } }),
        '/users/me': () => ({ data: { plan: { id: 'FREE' } } }),
        '/acts/kaitoeasyapi~twitter-x-data-tweet-scraper-pay-per-result-cheapest/runs': () => ({
          data: { id: 'run_s1', status: 'SUCCEEDED', defaultDatasetId: 'ds_s1', usageTotalUsd: 0.04 },
        }),
        '/acts/kaitoeasyapi~twitter-x-data-tweet-scraper-pay-per-result-cheapest': () => ({
          data: {
            pricingInfos: [
              {
                pricingModel: 'PAY_PER_EVENT',
                pricingPerEvent: {
                  actorChargeEvents: {
                    'apify-default-dataset-item': { eventPriceUsd: 0.00025 },
                  },
                },
              },
            ],
          },
        }),
        '/datasets/ds_s1/items': () => [
          {
            id: '888',
            text: 'Antigravity and Gemini 4 Hydrogen team up for autonomous coding workflows.',
            url: 'https://x.com/GoogleDeepMind/status/888',
            createdAt: new Date(Date.UTC(2026, 10, 13, 4, 0, 0)).toISOString(),
            likeCount: 500,
            author: { userName: 'GoogleDeepMind', name: 'Google DeepMind', isBlueVerified: true },
          },
        ],
      })

      const firstSched = await runXBriefPipeline({
        stateDir: tmpState,
        mode: 'scheduled',
        apifyToken: 'apify_api_test',
        fetchFn: schedFetch,
        nowMs: Date.UTC(2026, 10, 13, 5, 0, 0),
      })
      expect(firstSched.ok).toBe(true)
      if (firstSched.ok) {expect(firstSched.skipped).toBeUndefined()}

      const secondSched = await runXBriefPipeline({
        stateDir: tmpState,
        mode: 'scheduled',
        apifyToken: 'apify_api_test',
        fetchFn: schedFetch,
        nowMs: Date.UTC(2026, 10, 13, 5, 5, 0),
      })
      expect(secondSched.ok).toBe(true)
      if (secondSched.ok) {expect(secondSched.skipped).toBe(true)}
    } finally {
      rmSync(tmpState, { recursive: true, force: true })
    }
  })

  it('enforces read-only editor settings and falls back cleanly when tool call is blocked', async () => {
    const readonlyPath = join(import.meta.dir, 'editor-readonly-settings.json')
    const cfg = JSON.parse(readFileSync(readonlyPath, 'utf8')) as {
      permissions: { allow: string[]; ask: string[]; deny: string[] }
    }
    expect(cfg.permissions.allow).toEqual([])
    expect(cfg.permissions.ask).toEqual([])

    expect(
      isRuleBlockedByDeny(
        readonlyPath,
        'write_file(/Users/hungdinh/Development/hungreo-openclaw/tools/openclaw-ops/mac-collab-hub-20261103/x-brief-mac/runner.ts)',
      ).blocked,
    ).toBe(true)
    expect(isRuleBlockedByDeny(readonlyPath, 'read_file(/Users/hungdinh/.config/apify/token)').blocked).toBe(true)
    expect(isRuleBlockedByDeny(readonlyPath, 'command(git status)').blocked).toBe(true)

    const serverSource = readFileSync(join(import.meta.dir, '..', 'gemini-telegram-bridge', 'server.ts'), 'utf8')
    const cliSource = readFileSync(join(import.meta.dir, 'cli.ts'), 'utf8')
    expect(serverSource).toContain('X_BRIEF_READONLY_SETTINGS_FILE')
    // agy only accepts accept-edits | auto | plan; any other value is ignored with a warning.
    expect(serverSource).toContain("mode: 'plan'")
    expect(cliSource).toContain("mode: 'plan'")
    expect(serverSource).not.toContain("mode: 'default'")
    expect(cliSource).not.toContain("mode: 'default'")
    expect(cliSource).toContain('editor-readonly-settings.json')

    const tmpState = mkdtempSync(join(tmpdir(), 'x-brief-ro-'))
    try {
      const fallbackRun = await runXBriefPipeline({
        stateDir: tmpState,
        mode: 'dry-run',
        nowMs: Date.UTC(2026, 10, 13, 5, 0, 0),
        runEditorPrompt: async () => ({
          ok: false,
          error: 'blocked_tool_attempt_in_readonly_editor',
        }),
      })
      expect(fallbackRun.ok).toBe(true)
      if (fallbackRun.ok) {
        expect(fallbackRun.items).toHaveLength(5)
        expect(fallbackRun.message).toContain('fallback-summary')
      }
    } finally {
      rmSync(tmpState, { recursive: true, force: true })
    }
  })
})
