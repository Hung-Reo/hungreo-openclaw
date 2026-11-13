import { afterEach, describe, expect, it } from 'bun:test'
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import {
  RecentTurnBuffer,
  buildHandoverSeedPrompt,
  buildHandoverSummaryPrompt,
  buildTelegramInitialPrompt,
  executeAutoHandover,
  formatHandoverResultMessage,
} from './handover.ts'

const tempDirs: string[] = []

function makeTempHandoversDir(): string {
  const dir = mkdtempSync(join(tmpdir(), 'gemini-handover-'))
  tempDirs.push(dir)
  return join(dir, 'handovers')
}

afterEach(() => {
  while (tempDirs.length > 0) {
    rmSync(tempDirs.pop()!, { recursive: true, force: true })
  }
})

describe('executeAutoHandover', () => {
  it('runs 3-step handover, redacts secrets in 0600 backup, clears old thread, and seeds new thread', async () => {
    const handoversDir = makeTempHandoversDir()
    const calls: string[] = []
    let clearedChatId: string | undefined
    let committed: { chatId: string; conversationId: string; totalTokens?: number } | undefined

    const res = await executeAutoHandover({
      chatId: '111222333',
      trigger: 'auto',
      oldConversationId: 'old-conv-11112222',
      modelId: 'gemini-4-hydrogen-high',
      handoversDir,
      summarizeTurn: async (convId, prompt) => {
        calls.push(`summarize:${convId}`)
        expect(prompt).toContain('HANDOVER')
        expect(prompt).toContain('KHÔNG chạy lệnh shell')
        return {
          ok: true,
          text: '1. Đã xong test\n2. Token mẫu bị lộ sk-proj-secret1234567890abcdef sẽ bị redact.',
        }
      },
      clearOldThreadState: chatId => {
        calls.push(`clear:${chatId}`)
        clearedChatId = chatId
      },
      seedNewTurn: async prompt => {
        calls.push('seed')
        expect(prompt).toContain('HANDOVER_AUTO')
        expect(prompt).not.toContain('sk-proj-secret1234567890abcdef')
        return {
          ok: true,
          conversationId: 'new-conv-99998888',
          reply: 'Đã nạp handover.',
          totalTokens: 28_500,
          durationSeconds: 3.4,
        }
      },
      commitNewThreadState: input => {
        calls.push(`commit:${input.conversationId}`)
        committed = input
      },
    })

    expect(calls).toEqual(['summarize:old-conv-11112222', 'clear:111222333', 'seed', 'commit:new-conv-99998888'])
    expect(clearedChatId).toBe('111222333')
    expect(committed?.conversationId).toBe('new-conv-99998888')
    expect(res.ok).toBe(true)
    if (!res.ok) {return}

    expect(existsSync(res.backupPath)).toBe(true)
    expect(statSync(res.backupPath).mode & 0o777).toBe(0o600)
    const diskText = readFileSync(res.backupPath, 'utf8')
    expect(diskText).not.toContain('sk-proj-secret1234567890abcdef')
    expect(res.summary).not.toContain('sk-proj-secret1234567890abcdef')

    const msg = formatHandoverResultMessage(res, 1_048_576)
    expect(msg).toContain('Tự động (vượt ngưỡng token tiết kiệm quota)')
    expect(msg).toContain('old-conv')
    expect(msg).toContain('new-conv')
    expect(msg).toContain('28,500 / 1,048,576')
  })

  it('returns no_thread without touching state when no active conversation exists', async () => {
    const handoversDir = makeTempHandoversDir()
    let cleared = false
    const res = await executeAutoHandover({
      chatId: '111222333',
      trigger: 'command',
      oldConversationId: undefined,
      modelId: 'gemini-4-hydrogen-high',
      handoversDir,
      summarizeTurn: async () => ({ ok: true, text: 'unused' }),
      seedNewTurn: async () => ({ ok: true, conversationId: 'unused' }),
      clearOldThreadState: () => {
        cleared = true
      },
      commitNewThreadState: () => {},
    })

    expect(res.ok).toBe(false)
    if (res.ok) {return}
    expect(res.stage).toBe('no_thread')
    expect(cleared).toBe(false)
  })

  it('preserves old thread intact when summarization fails (fail-safe)', async () => {
    const handoversDir = makeTempHandoversDir()
    let cleared = false
    let seeded = false

    const res = await executeAutoHandover({
      chatId: '111222333',
      trigger: 'button',
      oldConversationId: 'old-conv-keep-me',
      modelId: 'gemini-4-hydrogen-high',
      handoversDir,
      summarizeTurn: async () => {
        throw new Error('idle timeout')
      },
      seedNewTurn: async () => {
        seeded = true
        return { ok: true, conversationId: 'new-conv' }
      },
      clearOldThreadState: () => {
        cleared = true
      },
      commitNewThreadState: () => {},
    })

    expect(res.ok).toBe(false)
    if (res.ok) {return}
    expect(res.stage).toBe('summarize')
    expect(cleared).toBe(false)
    expect(seeded).toBe(false)

    const msg = formatHandoverResultMessage(res)
    expect(msg).toContain('Phiên cũ vẫn được giữ nguyên')
    expect(msg).toContain('idle timeout')
  })

  it('keeps 0600 backup and reports summary if seeding the new thread fails', async () => {
    const handoversDir = makeTempHandoversDir()
    let cleared = false
    let committed = false

    const res = await executeAutoHandover({
      chatId: '111222333',
      trigger: 'auto',
      oldConversationId: 'old-conv-1234',
      modelId: 'gemini-4-hydrogen-high',
      handoversDir,
      summarizeTurn: async () => ({ ok: true, text: 'Handover summary ready.' }),
      seedNewTurn: async () => ({ ok: false, error: 'network error' }),
      clearOldThreadState: () => {
        cleared = true
      },
      commitNewThreadState: () => {
        committed = true
      },
    })

    expect(res.ok).toBe(false)
    if (res.ok) {return}
    expect(res.stage).toBe('seed')
    expect(cleared).toBe(true)
    expect(committed).toBe(false)
    expect(res.backupPath && existsSync(res.backupPath)).toBe(true)

    const msg = formatHandoverResultMessage(res)
    expect(msg).toContain('Đã lưu handover & xoá phiên cũ')
    expect(msg).toContain('Handover summary ready.')
  })
})

describe('handover prompt builders', () => {
  it('builds detailed non-tool summary prompt preserving formats, paths, and latest requests', () => {
    const prompt = buildHandoverSummaryPrompt()
    expect(prompt).toContain('TUYỆT ĐỐI KHÔNG chạy lệnh shell')
    expect(prompt).not.toContain('10–15 dòng')
    expect(prompt).toContain('format')
    expect(prompt).toContain('đường dẫn')
    expect(prompt).toContain('gần nhất')

    const seed = buildHandoverSeedPrompt('1. Done X', [
      {
        senderLabel: '@hungdinh',
        userText: 'Giữ nguyên format Rùa với token mẫu sk-proj-secret1234567890abcdef',
        assistantReply: 'Em đã ghi nhận format Rùa.',
      },
    ])
    expect(seed).toContain('HANDOVER_AUTO')
    expect(seed).toContain('1. Done X')
    expect(seed).toContain('Ngữ cảnh trao đổi gần nhất')
    expect(seed).toContain('@hungdinh')
    expect(seed).toContain('Em đã ghi nhận format Rùa.')
    expect(seed).not.toContain('sk-proj-secret1234567890abcdef')

    const initial = buildTelegramInitialPrompt('@hungdinh', 'Xin chào')
    expect(initial).toContain('&&')
  })

  it('retains bounded redacted recent turns in RecentTurnBuffer and clears by chatId', () => {
    const buf = new RecentTurnBuffer(2, 40)
    buf.record('chat1', { senderLabel: '@a', userText: 'turn 1', assistantReply: 'reply 1' })
    buf.record('chat1', {
      senderLabel: '@b',
      userText: 'turn 2 sk-proj-secret1234567890abcdef',
      assistantReply: 'reply 2',
    })
    buf.record('chat1', {
      senderLabel: '@c',
      userText: 'turn 3 ' + 'x'.repeat(80),
      assistantReply: 'reply 3',
    })

    const turns = buf.get('chat1')
    expect(turns).toHaveLength(2)
    expect(turns[0].senderLabel).toBe('@b')
    expect(turns[0].userText).not.toContain('sk-proj-secret1234567890abcdef')
    expect(turns[1].senderLabel).toBe('@c')
    expect(turns[1].userText.length).toBeLessThanOrEqual(41)

    buf.clear('chat1')
    expect(buf.get('chat1')).toEqual([])
  })

  it('forwards recentTurns into seed prompt during executeAutoHandover', async () => {
    const handoversDir = makeTempHandoversDir()
    let capturedSeedPrompt = ''
    const res = await executeAutoHandover({
      chatId: '111222333',
      trigger: 'command',
      oldConversationId: 'old-conv-5555',
      modelId: 'gemini-4-hydrogen-high',
      handoversDir,
      recentTurns: [
        {
          senderLabel: '@hungdinh',
          userText: 'So sánh format Rùa với Phương án 1',
          assistantReply: 'Đã phân tích 2 phương án.',
        },
      ],
      summarizeTurn: async () => ({ ok: true, text: 'Summary body' }),
      seedNewTurn: async prompt => {
        capturedSeedPrompt = prompt
        return { ok: true, conversationId: 'new-conv-6666', reply: 'Sẵn sàng.' }
      },
      clearOldThreadState: () => {},
      commitNewThreadState: () => {},
    })

    expect(res.ok).toBe(true)
    expect(capturedSeedPrompt).toContain('So sánh format Rùa với Phương án 1')
    expect(capturedSeedPrompt).toContain('Đã phân tích 2 phương án.')
  })
})
