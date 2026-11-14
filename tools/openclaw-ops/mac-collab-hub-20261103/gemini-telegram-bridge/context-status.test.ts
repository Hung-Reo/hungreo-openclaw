import { afterEach, describe, expect, it } from 'bun:test'
import { mkdtempSync, readFileSync, rmSync, statSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import {
  DEFAULT_AUTO_HANDOVER_TOKENS,
  DEFAULT_CONTEXT_WINDOW_TOKENS,
  DEFAULT_WARN_TOKEN_THRESHOLDS,
  ThreadStatsStore,
  evaluateContextWarning,
  formatBridgeStartedAtVnt,
  formatContextStatusMessage,
  resolveContextWindowTokens,
  resolveQuotaPolicy,
} from './context-status.ts'

const tempDirs: string[] = []

function makeTempStatsFile(): string {
  const dir = mkdtempSync(join(tmpdir(), 'gemini-ctx-status-'))
  tempDirs.push(dir)
  return join(dir, 'thread-stats.json')
}

afterEach(() => {
  while (tempDirs.length > 0) {
    rmSync(tempDirs.pop()!, { recursive: true, force: true })
  }
})

describe('resolveContextWindowTokens & resolveQuotaPolicy', () => {
  it('returns 1M token window and 150k/225k/300k quota defaults with env overrides', () => {
    expect(resolveContextWindowTokens({})).toBe(DEFAULT_CONTEXT_WINDOW_TOKENS)
    expect(resolveContextWindowTokens({ GEMINI_CONTEXT_WINDOW_TOKENS: '200000' })).toBe(200_000)
    expect(resolveContextWindowTokens({ GEMINI_CONTEXT_WINDOW_TOKENS: 'invalid' })).toBe(DEFAULT_CONTEXT_WINDOW_TOKENS)
    expect(resolveContextWindowTokens({ GEMINI_CONTEXT_WINDOW_TOKENS: '-5' })).toBe(DEFAULT_CONTEXT_WINDOW_TOKENS)

    const defPolicy = resolveQuotaPolicy({})
    expect(defPolicy.warnTokenThresholds).toEqual([...DEFAULT_WARN_TOKEN_THRESHOLDS])
    expect(defPolicy.autoHandoverTokens).toBe(DEFAULT_AUTO_HANDOVER_TOKENS)

    const custom = resolveQuotaPolicy({
      GEMINI_WARN_TOKENS: '100000, 180000',
      GEMINI_AUTO_HANDOVER_TOKENS: '250000',
    })
    expect(custom.warnTokenThresholds).toEqual([100_000, 180_000, 250_000])
    expect(custom.autoHandoverTokens).toBe(250_000)
  })
})

describe('evaluateContextWarning', () => {
  it('warns on real context token milestones (150k, 225k) with button and triggers auto-handover at 300k', () => {
    const windowTokens = DEFAULT_CONTEXT_WINDOW_TOKENS

    const empty = evaluateContextWarning({
      contextTokens: undefined,
      contextWindowTokens: windowTokens,
      lastWarnedTokens: 0,
    })
    expect(empty.shouldWarn).toBe(false)

    const below = evaluateContextWarning({
      contextTokens: 140_000,
      contextWindowTokens: windowTokens,
      lastWarnedTokens: 0,
    })
    expect(below.shouldWarn).toBe(false)
    expect(below.nextWarnedTokens).toBe(0)
    expect(below.warningText).toBeUndefined()

    // Crosses 150k -> button tier
    const cross150 = evaluateContextWarning({
      contextTokens: 157_000,
      contextWindowTokens: windowTokens,
      lastWarnedTokens: 0,
    })
    expect(cross150.shouldWarn).toBe(true)
    expect(cross150.crossedThresholdTokens).toBe(150_000)
    expect(cross150.nextWarnedTokens).toBe(150_000)
    expect(cross150.action).toBe('button')
    expect(cross150.warningText).toContain('**157k** tokens context thực tế')
    expect(cross150.warningText).toContain('/handover')
    expect(cross150.warningText).toContain('/reset_thread')

    // Stays between 150k and 225k -> does not repeat warning
    const stay190 = evaluateContextWarning({
      contextTokens: 190_000,
      contextWindowTokens: windowTokens,
      lastWarnedTokens: cross150.nextWarnedTokens,
    })
    expect(stay190.shouldWarn).toBe(false)
    expect(stay190.nextWarnedTokens).toBe(150_000)

    // Crosses 225k -> second button warning
    const cross240 = evaluateContextWarning({
      contextTokens: 240_000,
      contextWindowTokens: windowTokens,
      lastWarnedTokens: stay190.nextWarnedTokens,
    })
    expect(cross240.shouldWarn).toBe(true)
    expect(cross240.crossedThresholdTokens).toBe(225_000)
    expect(cross240.nextWarnedTokens).toBe(225_000)
    expect(cross240.action).toBe('button')
    expect(cross240.warningText).toContain('**240k** tokens context thực tế')

    // Crosses 300k -> auto handover tier (even though < 30% of 1M window)
    const cross310 = evaluateContextWarning({
      contextTokens: 310_000,
      contextWindowTokens: windowTokens,
      lastWarnedTokens: cross240.nextWarnedTokens,
    })
    expect(cross310.shouldWarn).toBe(true)
    expect(cross310.crossedThresholdTokens).toBe(300_000)
    expect(cross310.nextWarnedTokens).toBe(300_000)
    expect(cross310.action).toBe('auto')
    expect(cross310.warningText).toContain('**310k** tokens context thực tế')
  })
})

describe('ThreadStatsStore', () => {
  it('persists separate context vs cumulative tokens with 0600 permissions and ignores cumulative-only spikes for % 1M', () => {
    const filePath = makeTempStatsFile()
    const store = new ThreadStatsStore(filePath)

    const r1 = store.recordTurn({
      chatId: '111222333',
      conversationId: 'conv-abc-123',
      modelId: 'gemini-4-hydrogen-high',
      contextTokens: 160_000,
      cumulativeTokens: 280_000,
      durationSeconds: 4.2,
    })
    expect(r1.warning.shouldWarn).toBe(true)
    expect(r1.warning.action).toBe('button')
    expect(r1.stats.turns).toBe(1)
    expect(r1.stats.lastContextTokens).toBe(160_000)
    expect(r1.stats.lastCumulativeTokens).toBe(280_000)
    expect(r1.stats.lastWarnedTokens).toBe(150_000)

    const mode = statSync(filePath).mode & 0o777
    expect(mode).toBe(0o600)

    // Reload from disk: high cumulative (420k) with low real context (185k) must NOT cross 225k or 300k!
    const store2 = new ThreadStatsStore(filePath)
    const r2 = store2.recordTurn({
      chatId: '111222333',
      conversationId: 'conv-abc-123',
      modelId: 'gemini-4-hydrogen-high',
      contextTokens: 185_000,
      cumulativeTokens: 420_000,
      durationSeconds: 3.1,
    })
    expect(r2.warning.shouldWarn).toBe(false)
    expect(r2.stats.turns).toBe(2)

    // Switching to a new conversationId resets turn counter & warning state; cumulative-only totalTokens must NOT trigger warning
    const r3 = store2.recordTurn({
      chatId: '111222333',
      conversationId: 'conv-new-456',
      modelId: 'gemini-4-hydrogen-high',
      totalTokens: 350_000,
      durationSeconds: 1.5,
    })
    expect(r3.stats.turns).toBe(1)
    expect(r3.stats.lastContextTokens).toBeUndefined()
    expect(r3.stats.lastCumulativeTokens).toBe(350_000)
    expect(r3.stats.lastWarnedTokens).toBe(0)
    expect(r3.warning.shouldWarn).toBe(false)

    // Explicit clear removes chatId entry
    store2.clear('111222333')
    expect(store2.get('111222333')).toBeUndefined()
    const raw = JSON.parse(readFileSync(filePath, 'utf8')) as Record<string, unknown>
    expect(raw['111222333']).toBeUndefined()
  })
})

describe('formatContextStatusMessage', () => {
  it('formats real context separately from cumulative tokens with 300k quota budget and health badge', () => {
    const startedLabel = formatBridgeStartedAtVnt(new Date('2026-11-14T00:58:00.000Z'))
    expect(startedLabel).toBe('07:58 14/11/2026 (VNT)')

    const msg = formatContextStatusMessage({
      botUsername: 'hungreo_gemini_bot',
      currentModelId: 'gemini-4-hydrogen-high',
      currentModelLabel: 'Gemini 4 Hydrogen (High)',
      conversationId: 'conv-1234567890abcdef',
      contextWindowTokens: 1_048_576,
      bridgeStartedLabel: startedLabel,
      stats: {
        conversationId: 'conv-1234567890abcdef',
        modelId: 'gemini-4-hydrogen-high',
        lastContextTokens: 165_000,
        lastCumulativeTokens: 412_000,
        lastTokens: 412_000,
        turns: 8,
        lastDurationSeconds: 5.4,
        lastWarnedTokens: 150_000,
        lastWarnedPct: 16,
        updatedAt: '2026-11-13T09:50:00.000Z',
      },
    })
    expect(msg).toContain('@hungreo_gemini_bot')
    expect(msg).toContain('Gemini 4 Hydrogen (High)')
    expect(msg).toContain('- **Bridge started:** `07:58 14/11/2026 (VNT)`')
    expect(msg).toContain('165,000 / 300,000')
    expect(msg).toContain('`412,000` tokens *(input mới + output, không phải kích thước context)*')
    expect(msg).toContain('Nên handover sớm')
    expect(msg).toContain('/handover')
    expect(msg).toContain('/reset_thread')

    // Legacy stats without lastContextTokens must NOT show cumulative as context budget
    const legacyCumulativeMsg = formatContextStatusMessage({
      botUsername: 'hungreo_gemini_bot',
      currentModelId: 'gemini-4-hydrogen-high',
      currentModelLabel: 'Gemini 4 Hydrogen (High)',
      conversationId: 'conv-legacy-cumulative',
      contextWindowTokens: 1_048_576,
      stats: {
        conversationId: 'conv-legacy-cumulative',
        modelId: 'gemini-4-hydrogen-high',
        lastTokens: 320_000,
        turns: 6,
        lastDurationSeconds: 3.0,
        lastWarnedTokens: 0,
        lastWarnedPct: 0,
        updatedAt: '2026-11-13T09:50:00.000Z',
      },
    })
    expect(legacyCumulativeMsg).toContain('Chưa có số liệu token')
    expect(legacyCumulativeMsg).toContain('`320,000` tokens *(input mới + output, không phải kích thước context)*')
    expect(legacyCumulativeMsg).not.toContain('320,000 / 300,000')
  })

  it('handles fresh session without conversationId and active legacy thread without stats', () => {
    const emptyMsg = formatContextStatusMessage({
      botUsername: 'hungreo_gemini_bot',
      currentModelId: 'gemini-4-hydrogen-high',
      currentModelLabel: 'Gemini 4 Hydrogen (High)',
      contextWindowTokens: 1_048_576,
    })
    expect(emptyMsg).toContain('Chưa có phiên')
    expect(emptyMsg).toContain('0 / 300k')

    const legacyMsg = formatContextStatusMessage({
      botUsername: 'hungreo_gemini_bot',
      currentModelId: 'gemini-4-hydrogen-high',
      currentModelLabel: 'Gemini 4 Hydrogen (High)',
      conversationId: 'old-conv-id-9999',
      contextWindowTokens: 1_048_576,
    })
    expect(legacyMsg).toContain('Đang mở')
    expect(legacyMsg).toContain('Chưa có số liệu token')
  })
})
