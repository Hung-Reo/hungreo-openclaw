import { existsSync, mkdirSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { redactSensitiveOutput } from '../lib/collab-gate.ts'
import {
  resolveApifyToken,
  runApifyCollection,
  type FetchLike,
} from './apify-client.ts'
import {
  buildEditorialPrompt,
  parseAndValidateEditorialItems,
} from './editor.ts'
import { formatXBriefTelegramMessage } from './formatter.ts'
import {
  appendHistory,
  loadHistory,
  selectBalancedCandidates,
} from './queries.ts'
import { getLocalScheduleParts } from './scheduler.ts'
import type {
  ApifyCollectResult,
  NormalizedTweet,
  RunXBriefResult,
  XBriefMode,
} from './types.ts'

export type EditorRunnerFn = (prompt: string) => Promise<{ ok: boolean; text?: string; error?: string }>

function writeJsonAtomic(filePath: string, data: unknown): void {
  writeFileSync(filePath, redactSensitiveOutput(JSON.stringify(data, null, 2)) + '\n', { mode: 0o600 })
}

function buildDryRunSampleTweets(nowMs: number): NormalizedTweet[] {
  return [
    {
      id: 'dry-1',
      url: 'https://x.com/GoogleDeepMind/status/900000000000000001',
      authorHandle: 'GoogleDeepMind',
      authorName: 'Google DeepMind',
      isVerified: true,
      text: 'Introducing Gemini 4 Hydrogen: faster reasoning and stronger coding agent workflows in Antigravity.',
      createdAtIso: new Date(nowMs - 2 * 3600_000).toISOString(),
      createdAtMs: nowMs - 2 * 3600_000,
      isRecent12h: true,
      likes: 2400,
      retweets: 520,
      replies: 110,
      bookmarks: 800,
      views: 150000,
      primaryUrl: 'https://deepmind.google/gemini-4-hydrogen',
      axis: 'coding',
      score: 95,
      eventKey: 'url:deepmind.google/gemini-4-hydrogen',
    },
    {
      id: 'dry-2',
      url: 'https://x.com/ClaudeDevs/status/900000000000000002',
      authorHandle: 'ClaudeDevs',
      authorName: 'Claude Developers',
      isVerified: true,
      text: 'Claude Code adds parallel subagent worktree isolation and faster MCP tool discovery.',
      createdAtIso: new Date(nowMs - 4 * 3600_000).toISOString(),
      createdAtMs: nowMs - 4 * 3600_000,
      isRecent12h: true,
      likes: 1850,
      retweets: 410,
      replies: 85,
      bookmarks: 640,
      views: 98000,
      primaryUrl: 'https://docs.anthropic.com/claude-code',
      axis: 'coding',
      score: 91,
      eventKey: 'url:docs.anthropic.com/claude-code',
    },
    {
      id: 'dry-3',
      url: 'https://x.com/OpenAIDevs/status/900000000000000003',
      authorHandle: 'OpenAIDevs',
      authorName: 'OpenAI Developers',
      isVerified: true,
      text: 'Codex CLI now supports structured project specs and deterministic sandbox approvals across multi-repo workspaces.',
      createdAtIso: new Date(nowMs - 6 * 3600_000).toISOString(),
      createdAtMs: nowMs - 6 * 3600_000,
      isRecent12h: true,
      likes: 1400,
      retweets: 290,
      replies: 60,
      bookmarks: 510,
      views: 74000,
      axis: 'coding',
      score: 88,
      eventKey: 'txt:codex-cli-supports-structured-project-specs',
    },
    {
      id: 'dry-4',
      url: 'https://x.com/openai/status/900000000000000004',
      authorHandle: 'openai',
      authorName: 'OpenAI',
      isVerified: true,
      text: 'Rolling out shared team memory workspaces for faster project collaboration across product and engineering.',
      createdAtIso: new Date(nowMs - 9 * 3600_000).toISOString(),
      createdAtMs: nowMs - 9 * 3600_000,
      isRecent12h: true,
      likes: 3100,
      retweets: 600,
      replies: 140,
      bookmarks: 900,
      views: 210000,
      axis: 'products',
      score: 86,
      eventKey: 'txt:rolling-out-shared-team-memory-workspaces',
    },
    {
      id: 'dry-5',
      url: 'https://x.com/emollick/status/900000000000000005',
      authorHandle: 'emollick',
      authorName: 'Ethan Mollick',
      isVerified: true,
      text: 'New classroom study shows structured AI critique prompts improve student retention without replacing active writing.',
      createdAtIso: new Date(nowMs - 14 * 3600_000).toISOString(),
      createdAtMs: nowMs - 14 * 3600_000,
      isRecent12h: false,
      likes: 1650,
      retweets: 350,
      replies: 72,
      bookmarks: 690,
      views: 88000,
      axis: 'human_education',
      score: 79,
      eventKey: 'txt:classroom-study-shows-structured-critique-prompts',
    },
  ]
}

export async function runXBriefPipeline(params: {
  stateDir: string
  mode: XBriefMode
  runEditorPrompt?: EditorRunnerFn
  apifyToken?: string
  fetchFn?: FetchLike
  nowMs?: number
  recordHistory?: boolean
  skipPricingCheck?: boolean
}): Promise<RunXBriefResult> {
  const startedAt = Date.now()
  const nowMs = params.nowMs ?? Date.now()
  const { dateKey } = getLocalScheduleParts(new Date(nowMs), 'Asia/Ho_Chi_Minh')
  const xBriefDir = join(params.stateDir, 'x-brief')
  const historyPath = join(xBriefDir, 'history.json')
  const dailyDir = join(xBriefDir, 'runs', dateKey)
  const artifactsDir =
    params.mode === 'scheduled' ? dailyDir : join(dailyDir, `${params.mode}-${nowMs}`)

  if (params.mode === 'scheduled' && existsSync(join(dailyDir, 'brief.md'))) {
    return {
      ok: true,
      mode: params.mode,
      dateKey,
      skipped: true,
      skipReason: `Đã có bản tin ngày ${dateKey} tại ${dailyDir}.`,
      message: '',
      items: [],
      rawItemCount: 0,
      candidateCount: 0,
      costUsd: 0,
      remainingUsd: 0,
      durationSeconds: (Date.now() - startedAt) / 1000,
      artifactsDir: dailyDir,
    }
  }

  let collectRes: ApifyCollectResult
  if (params.mode === 'dry-run') {
    const sample = buildDryRunSampleTweets(nowMs)
    collectRes = {
      ok: true,
      runId: 'dry-run',
      datasetId: 'dry-run',
      items: sample,
      rawItemCount: sample.length,
      costUsd: 0,
      creditBefore: {
        planId: 'FREE',
        maxMonthlyUsageUsd: 5,
        monthlyUsageUsd: 0.9012,
        remainingUsd: 4.0988,
        lowCreditWarning: false,
        blocked: false,
      },
      creditAfter: {
        planId: 'FREE',
        maxMonthlyUsageUsd: 5,
        monthlyUsageUsd: 0.9012,
        remainingUsd: 4.0988,
        lowCreditWarning: false,
        blocked: false,
      },
      durationMs: 5,
    }
  } else {
    const token = params.apifyToken?.trim() || resolveApifyToken()
    if (!token) {
      return {
        ok: false,
        mode: params.mode,
        dateKey,
        stage: 'token',
        error:
          'Chưa tìm thấy `APIFY_API_TOKEN` trên Mac (trong `STATE_DIR/.env` hoặc `~/.config/apify/token`).',
        durationSeconds: (Date.now() - startedAt) / 1000,
      }
    }

    try {
      collectRes = await runApifyCollection({
        token,
        nowMs,
        fetchFn: params.fetchFn,
        skipPricingCheck: params.skipPricingCheck,
      })
    } catch (err) {
      return {
        ok: false,
        mode: params.mode,
        dateKey,
        stage: 'collect',
        error: redactSensitiveOutput(err instanceof Error ? err.message : String(err)),
        durationSeconds: (Date.now() - startedAt) / 1000,
      }
    }
  }

  if (!collectRes.ok) {
    const stage = collectRes.creditBefore?.blocked ? 'credit' : 'collect'
    return {
      ok: false,
      mode: params.mode,
      dateKey,
      stage,
      error: collectRes.error ?? 'Không thu thập được dữ liệu từ Apify.',
      remainingUsd: collectRes.creditBefore?.remainingUsd,
      durationSeconds: (Date.now() - startedAt) / 1000,
    }
  }

  const history = loadHistory(historyPath, nowMs)
  const candidates = selectBalancedCandidates({
    tweets: collectRes.items,
    history,
    limit: 15,
  })

  if (candidates.length === 0) {
    return {
      ok: false,
      mode: params.mode,
      dateKey,
      stage: 'collect',
      error: `Apify trả ${collectRes.rawItemCount} tweets nhưng không còn ứng viên mới sau khi lọc 48h & chống trùng.`,
      remainingUsd: (collectRes.creditAfter ?? collectRes.creditBefore).remainingUsd,
      durationSeconds: (Date.now() - startedAt) / 1000,
    }
  }

  let rawEditorReply = ''
  if (params.runEditorPrompt) {
    const editorRes = await params.runEditorPrompt(buildEditorialPrompt(candidates)).catch(err => ({
      ok: false,
      error: err instanceof Error ? err.message : String(err),
      text: '',
    }))
    if (editorRes.ok && editorRes.text) {
      rawEditorReply = editorRes.text
    }
  }

  const { items, usedFallback } = parseAndValidateEditorialItems(rawEditorReply, candidates, 5)
  const finalCredit = collectRes.creditAfter ?? collectRes.creditBefore
  const durationSeconds = (Date.now() - startedAt) / 1000

  const message = formatXBriefTelegramMessage({
    mode: params.mode,
    dateKey,
    items,
    rawItemCount: collectRes.rawItemCount,
    costUsd: collectRes.costUsd,
    remainingUsd: finalCredit.remainingUsd,
    lowCreditWarning: finalCredit.lowCreditWarning,
    durationSeconds,
    usedFallbackEditor: usedFallback,
  })

  mkdirSync(artifactsDir, { recursive: true, mode: 0o700 })
  writeJsonAtomic(join(artifactsDir, 'credit-before.json'), collectRes.creditBefore)
  writeJsonAtomic(join(artifactsDir, 'candidates.json'), candidates)
  writeJsonAtomic(join(artifactsDir, 'meta.json'), {
    mode: params.mode,
    dateKey,
    runId: collectRes.runId,
    rawItemCount: collectRes.rawItemCount,
    candidateCount: candidates.length,
    selectedCount: items.length,
    costUsd: collectRes.costUsd,
    remainingUsd: finalCredit.remainingUsd,
    usedFallbackEditor: usedFallback,
    durationSeconds: Number(durationSeconds.toFixed(2)),
  })
  writeFileSync(join(artifactsDir, 'brief.md'), redactSensitiveOutput(message) + '\n', { mode: 0o600 })

  const shouldRecordHistory = params.recordHistory ?? params.mode === 'scheduled'
  if (shouldRecordHistory) {
    const idToEvent = new Map(candidates.map(c => [c.id, c.eventKey]))
    appendHistory(
      historyPath,
      items.map(item => ({
        date: dateKey,
        url: item.url,
        eventKey: idToEvent.get(item.sourceTweetId) ?? item.sourceTweetId,
        title: item.title,
      })),
      nowMs,
    )
  }

  return {
    ok: true,
    mode: params.mode,
    dateKey,
    message: redactSensitiveOutput(message),
    items,
    rawItemCount: collectRes.rawItemCount,
    candidateCount: candidates.length,
    costUsd: collectRes.costUsd,
    remainingUsd: finalCredit.remainingUsd,
    durationSeconds,
    artifactsDir,
  }
}
