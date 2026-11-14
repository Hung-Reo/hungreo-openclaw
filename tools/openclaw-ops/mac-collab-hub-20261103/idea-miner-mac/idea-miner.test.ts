import { describe, expect, it } from 'bun:test'
import { mkdtempSync, mkdirSync, readFileSync, rmSync, utimesSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { isRuleBlockedByDeny } from '../gemini-telegram-bridge/permissions.ts'
import { collectWeeklyDigest, getIsoWeekParts } from './collector.ts'
import { formatIdeaMinerTelegramMessage } from './formatter.ts'
import { buildDeterministicFallbackReport, buildIdeaMinerPrompt, parseAndValidateIdeaMinerOutput } from './prompt.ts'
import { runIdeaMinerPipeline } from './runner.ts'
import {
  getWeeklyScheduleParts,
  loadWeeklyScheduleState,
  saveWeeklyScheduleState,
  shouldTriggerWeeklyMiner,
} from './scheduler.ts'

describe('idea-miner weekly scheduler', () => {
  it('triggers only on Monday 07:30-07:59 Asia/Ho_Chi_Minh and avoids duplicate runs in the same ISO week', () => {
    // 2026-11-16 is Monday in Asia/Ho_Chi_Minh (UTC+7)
    const mon0729 = new Date('2026-11-16T00:29:00.000Z')
    const mon0730 = new Date('2026-11-16T00:30:00.000Z')
    const mon0759 = new Date('2026-11-16T00:59:00.000Z')
    const mon0800 = new Date('2026-11-16T01:00:00.000Z')
    const tue0730 = new Date('2026-11-17T00:30:00.000Z')

    const parts = getWeeklyScheduleParts(mon0730)
    expect(parts.weekday).toBe('Mon')
    expect(parts.dateKey).toBe('2026-11-16')
    expect(parts.weekKey).toBe('2026-W47')

    expect(shouldTriggerWeeklyMiner({ now: mon0729 }).shouldRun).toBe(false)
    expect(shouldTriggerWeeklyMiner({ now: mon0730 }).shouldRun).toBe(true)
    expect(shouldTriggerWeeklyMiner({ now: mon0759 }).shouldRun).toBe(true)
    expect(shouldTriggerWeeklyMiner({ now: mon0800 }).shouldRun).toBe(false)
    expect(shouldTriggerWeeklyMiner({ now: tue0730 }).shouldRun).toBe(false)
    expect(
      shouldTriggerWeeklyMiner({
        now: mon0730,
        lastAttemptWeekKey: parts.weekKey,
      }).shouldRun,
    ).toBe(false)
  })

  it('persists and reloads weekly schedule state atomically', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'idea-miner-sched-'))
    try {
      const statePath = join(tmp, 'idea-miner', 'schedule-state.json')
      expect(loadWeeklyScheduleState(statePath)).toEqual({})
      saveWeeklyScheduleState(statePath, {
        lastAttemptWeekKey: '2026-W47',
        lastSuccessWeekKey: '2026-W47',
        lastAttemptDate: '2026-11-16',
        lastStatus: 'ok',
      })
      expect(loadWeeklyScheduleState(statePath)).toMatchObject({
        lastAttemptWeekKey: '2026-W47',
        lastStatus: 'ok',
      })
    } finally {
      rmSync(tmp, { recursive: true, force: true })
    }
  })
})

describe('collectWeeklyDigest', () => {
  it('extracts redacted handovers, recent transcripts, and lessons while skipping stale/noisy lines', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'idea-miner-collect-'))
    const nowMs = Date.parse('2026-11-16T00:30:00.000Z')
    try {
      const handoversDir = join(tmp, 'handovers')
      const brainDir = join(tmp, 'brain')
      const lessonsDir = join(tmp, 'lessons')
      mkdirSync(handoversDir, { recursive: true })
      mkdirSync(join(brainDir, 'sess-recent-001', '.system_generated', 'logs'), { recursive: true })
      mkdirSync(join(brainDir, 'sess-old-002', '.system_generated', 'logs'), { recursive: true })
      mkdirSync(join(brainDir, 'sess-self-003', '.system_generated', 'logs'), { recursive: true })
      mkdirSync(join(brainDir, 'sess-canary-004', '.system_generated', 'logs'), { recursive: true })
      mkdirSync(lessonsDir, { recursive: true })

      writeFileSync(
        join(handoversDir, '990000001.md'),
        'Mục tiêu: kiểm tra apify_api_FakeSecretToken1234567890 và tách ví Mac cho chat 990000001.',
      )

      const recentTranscript = join(brainDir, 'sess-recent-001', '.system_generated', 'logs', 'transcript.jsonl')
      writeFileSync(
        recentTranscript,
        [
          '{malformed-json',
          JSON.stringify({
            type: 'USER_INPUT',
            created_at: new Date(nowMs - 2 * 3600_000).toISOString(),
            content: 'Tin nhắn từ HANDOVER_AUTO: bỏ qua đoạn này',
          }),
          JSON.stringify({
            type: 'USER_INPUT',
            created_at: new Date(nowMs - 4000_000).toISOString(),
            content: 'ok go',
          }),
          JSON.stringify({
            type: 'USER_INPUT',
            created_at: new Date(nowMs - 3600_000).toISOString(),
            content: 'Mình muốn làm thêm bộ nhắc việc tuần cho RUUME với token sk-testSecretKey12345678901234',
          }),
          JSON.stringify({
            type: 'PLANNER_RESPONSE',
            created_at: new Date(nowMs - 2400_000).toISOString(),
            content: 'Báo cáo tuần nhắc lại lỗi permission check failed ở phiên trước',
          }),
          JSON.stringify({
            type: 'TOOL_RESULT',
            status: 'ERROR',
            created_at: new Date(nowMs - 1800_000).toISOString(),
            content: 'permission check failed for command "rg -n foo|bar"',
          }),
        ].join('\n'),
      )

      writeFileSync(
        join(brainDir, 'sess-self-003', '.system_generated', 'logs', 'transcript.jsonl'),
        [
          JSON.stringify({
            type: 'USER_INPUT',
            created_at: new Date(nowMs - 1200_000).toISOString(),
            content: '/plan Bạn là trợ lý phân tích tuần (Idea & Retro Miner) cho anh Hưng.',
          }),
          JSON.stringify({
            type: 'TOOL_RESULT',
            status: 'ERROR',
            created_at: new Date(nowMs - 1100_000).toISOString(),
            content: 'permission check failed on plan artifact',
          }),
        ].join('\n'),
      )

      writeFileSync(
        join(brainDir, 'sess-canary-004', '.system_generated', 'logs', 'transcript.jsonl'),
        JSON.stringify({
          type: 'USER_INPUT',
          created_at: new Date(nowMs - 900_000).toISOString(),
          content: '/plan Strictly test tool permissions once: try bash -c "echo canary"',
        }),
      )

      const oldTranscript = join(brainDir, 'sess-old-002', '.system_generated', 'logs', 'transcript.jsonl')
      writeFileSync(
        oldTranscript,
        JSON.stringify({
          type: 'USER_INPUT',
          created_at: new Date(nowMs - 14 * 24 * 3600_000).toISOString(),
          content: 'Old message two weeks ago',
        }),
      )
      const oldDate = new Date(nowMs - 14 * 24 * 3600_000)
      utimesSync(oldTranscript, oldDate, oldDate)

      writeFileSync(join(lessonsDir, '2026-11-12-sample.md'), '# 12/11/2026 — Sample Lesson\n')

      const digest = collectWeeklyDigest({
        handoversDir,
        brainDir,
        lessonsDir,
        nowMs,
      })

      expect(digest.weekKey).toBe('2026-W47')
      expect(digest.handovers.length).toBe(1)
      expect(digest.handovers[0]?.sourceName).toBe('chat')
      expect(digest.handovers[0]?.excerpt).not.toContain('apify_api_')
      expect(digest.handovers[0]?.excerpt).not.toContain('990000001')

      expect(digest.sessions.length).toBe(1)
      expect(digest.sessions[0]?.userInputsCount).toBe(2)
      expect(digest.sessions[0]?.toolDenialCount).toBe(1)
      expect(digest.sessions[0]?.errorStepCount).toBe(1)
      expect(digest.sessions[0]?.userHighlights).not.toContain('ok go')
      expect(digest.sessions[0]?.userHighlights[0]).not.toContain('sk-testSecretKey')
      expect(digest.recentLessons[0]?.title).toContain('Sample Lesson')
    } finally {
      rmSync(tmp, { recursive: true, force: true })
    }
  })
})

describe('prompt parsing & formatter', () => {
  it('caps ideas and skillProposals at 2 and falls back cleanly on invalid JSON', () => {
    const digest = {
      ...collectWeeklyDigest({ nowMs: Date.parse('2026-11-16T00:30:00.000Z') }),
      sessions: [
        {
          sessionId: 'abc12345',
          updatedAtIso: '2026-11-15T10:00:00.000Z',
          userInputsCount: 3,
          toolDenialCount: 2,
          errorStepCount: 1,
          userHighlights: ['Ý tưởng đồng bộ review tuần cho RUUME'],
          frictionHighlights: ['permission check failed'],
        },
      ],
    }

    const prompt = buildIdeaMinerPrompt(digest)
    expect(prompt).toContain('TUYỆT ĐỐI KHÔNG gọi bất kỳ tool')

    const validJson = [
      '```json',
      JSON.stringify({
        ideas: [
          { projectTag: 'RUUME', title: 'Idea 1', whyFromOwner: 'Why 1', smallestNextStep: 'Step 1', sourceRef: 'S1' },
          {
            projectTag: 'OpenClaw',
            title: 'Idea 2',
            whyFromOwner: 'Why 2',
            smallestNextStep: 'Step 2',
            sourceRef: 'S2',
          },
          { projectTag: 'Extra', title: 'Idea 3', whyFromOwner: 'Why 3', smallestNextStep: 'Step 3', sourceRef: 'S3' },
        ],
        skillProposals: [
          {
            repeatTag: '2 lần',
            issueTitle: 'Fix 1',
            draftRuleOrSkill: 'Rule 1',
            targetRef: `SKILL.md ${'x'.repeat(130)}`,
          },
          { repeatTag: '3 lần', issueTitle: 'Fix 2', draftRuleOrSkill: 'Rule 2', targetRef: 'AGENTS.md' },
          { repeatTag: '4 lần', issueTitle: 'Fix 3', draftRuleOrSkill: 'Rule 3', targetRef: 'Extra' },
        ],
        bottleneck: { summary: 'Chạm deny 2 lần', suggestion: 'Dùng read_file' },
      }),
      '```',
    ].join('\n')

    const parsed = parseAndValidateIdeaMinerOutput(validJson, digest)
    expect(parsed.usedFallbackEditor).toBe(false)
    expect(parsed.ideas.length).toBe(2)
    expect(parsed.skillProposals.length).toBe(2)
    expect(parsed.skillProposals[0]?.targetRef.endsWith('…')).toBe(true)
    expect(parsed.skillProposals[0]?.targetRef.length).toBeLessThanOrEqual(120)

    const fallback = parseAndValidateIdeaMinerOutput('not json at all', digest)
    expect(fallback.usedFallbackEditor).toBe(true)
    expect(fallback.skillProposals.length).toBe(1)

    const formatted = formatIdeaMinerTelegramMessage({
      mode: 'test',
      report: buildDeterministicFallbackReport(digest),
      durationSeconds: 1.5,
    })
    expect(formatted).toContain('IDEA & RETRO TUẦN [TEST]')
    expect(formatted).toContain('Mode: `plan` (chỉ đọc)')
    expect(formatted).toContain('fallback-summary')
  })

  it('computes ISO week parts consistently across year boundary', () => {
    expect(getIsoWeekParts('2026-11-16').weekKey).toBe('2026-W47')
  })
})

describe('runIdeaMinerPipeline & CLI security', () => {
  it('runs dry-run and prevents duplicate scheduled delivery for the same ISO week', async () => {
    const tmp = mkdtempSync(join(tmpdir(), 'idea-miner-run-'))
    const nowMs = Date.parse('2026-11-16T00:30:00.000Z')
    try {
      const dry = await runIdeaMinerPipeline({
        stateDir: tmp,
        mode: 'dry-run',
        nowMs,
      })
      expect(dry.ok).toBe(true)
      if (!dry.ok || dry.skipped) {
        throw new Error('Expected non-skipped dry-run result')
      }
      expect(dry.report.usedFallbackEditor).toBe(true)

      const firstScheduled = await runIdeaMinerPipeline({
        stateDir: tmp,
        mode: 'scheduled',
        nowMs,
        runEditorPrompt: async () => ({
          ok: true,
          text: JSON.stringify({
            ideas: [{ projectTag: 'RUUME', title: 'T1', whyFromOwner: 'W1', smallestNextStep: 'N1', sourceRef: 'S1' }],
            skillProposals: [],
            bottleneck: { summary: 'Ổn định', suggestion: 'Tiếp tục theo dõi' },
          }),
        }),
      })
      expect(firstScheduled.ok).toBe(true)
      if (!firstScheduled.ok || firstScheduled.skipped) {
        throw new Error('Expected first scheduled run to deliver')
      }
      expect(firstScheduled.report.usedFallbackEditor).toBe(false)

      const secondScheduled = await runIdeaMinerPipeline({
        stateDir: tmp,
        mode: 'scheduled',
        nowMs,
      })
      expect(secondScheduled.ok).toBe(true)
      if (!secondScheduled.ok) {
        throw new Error('Expected skip result')
      }
      expect(secondScheduled.skipped).toBe(true)
    } finally {
      rmSync(tmp, { recursive: true, force: true })
    }
  })

  it('enforces read-only plan mode, server wiring, and editor-readonly-settings.json plan.md allowance', () => {
    const cliSource = readFileSync(join(import.meta.dir, 'cli.ts'), 'utf8')
    expect(cliSource).toContain("mode: 'plan'")
    expect(cliSource).toContain('dangerouslySkipPermissions: false')
    expect(cliSource).toContain('editor-readonly-settings.json')
    expect(cliSource).toContain('hasPermissionDenial')

    const serverSource = readFileSync(join(import.meta.dir, '..', 'gemini-telegram-bridge', 'server.ts'), 'utf8')
    expect(serverSource).toContain('runIdeaMinerPipeline')
    expect(serverSource).toContain('startIdeaMinerScheduler')
    expect(serverSource).toContain("bot.command('idea_miner'")

    const readonlySettingsPath = join(import.meta.dir, '..', 'x-brief-mac', 'editor-readonly-settings.json')
    expect(
      isRuleBlockedByDeny(
        readonlySettingsPath,
        'write_file(/Users/hungdinh/Development/hungreo-openclaw/README.md)',
        '/Users/hungdinh/Development/hungreo-openclaw/README.md',
      ).blocked,
    ).toBe(true)
    expect(isRuleBlockedByDeny(readonlySettingsPath, 'read_file(/Users/hungdinh/.ssh/id_ed25519)').blocked).toBe(true)
    expect(
      isRuleBlockedByDeny(
        readonlySettingsPath,
        'write_file(/Users/hungdinh/.gemini/antigravity-cli/brain/test/plan.md)',
        '/Users/hungdinh/.gemini/antigravity-cli/brain/test/plan.md',
      ).blocked,
    ).toBe(false)
  })
})
