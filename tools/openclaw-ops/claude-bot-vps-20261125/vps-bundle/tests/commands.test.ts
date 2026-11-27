import { describe, expect, it } from 'bun:test'
import { mkdtempSync, mkdirSync, writeFileSync, utimesSync } from 'node:fs'
import { readFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import {
  CLAUDE_BOT_COMMANDS,
  SLASH_PROMPTS,
  buildStatusText,
  latestTranscript,
  parseAuthStatus,
  parseTranscript,
  latestHandoverMs,
  newSessionVerdict,
  NEW_SESSION_CALLBACK,
  contextWindow,
  projectSlug,
  registerClaudeBotCommands,
  type StatusInput,
} from '../plugin/commands.ts'

const PLUGIN = join(import.meta.dir, '..', 'plugin')

describe('CLAUDE_BOT_COMMANDS', () => {
  it('khớp 1-1 với handler trong server.ts và đúng luật tên của Telegram', () => {
    const src = readFileSync(join(PLUGIN, 'server.ts'), 'utf8')
    const literal = [...src.matchAll(/bot\.command\('([a-z0-9_]+)'/g)].map(m => m[1])
    expect(src).toContain('for (const name of Object.keys(SLASH_PROMPTS) as SlashPromptName[])')
    const handlers = new Set([...literal, ...Object.keys(SLASH_PROMPTS)])
    expect(new Set(CLAUDE_BOT_COMMANDS.map(c => c.command))).toEqual(handlers)
    expect(CLAUDE_BOT_COMMANDS.length).toBe(5)
    for (const c of CLAUDE_BOT_COMMANDS) {
      expect(c.command).toMatch(/^[a-z0-9_]{1,32}$/)
      expect(c.description.length).toBeGreaterThanOrEqual(3)
      expect(c.description.length).toBeLessThanOrEqual(256)
    }
  })

  it('không có lệnh giả mà plugin không làm thật được', () => {
    const names = CLAUDE_BOT_COMMANDS.map(c => c.command)
    for (const bad of ['model', 'reset', 'reset_session', 'compact']) expect(names).not.toContain(bad)
  })

  it('server.ts đăng ký menu qua registerClaudeBotCommands, không còn danh sách upstream', () => {
    const src = readFileSync(join(PLUGIN, 'server.ts'), 'utf8')
    expect(src).toContain('registerClaudeBotCommands(bot.api')
    expect(src).not.toContain("description: 'Check your pairing status'")
  })
})

describe('registerClaudeBotCommands', () => {
  it('đăng ký cho all_private_chats, trả về bản sao', async () => {
    let cmds: unknown, scope: unknown
    const ok = await registerClaudeBotCommands({
      setMyCommands: async (c, o) => { cmds = c; scope = o?.scope },
    })
    expect(ok).toBe(true)
    expect(scope).toEqual({ type: 'all_private_chats' })
    expect(cmds).toEqual([...CLAUDE_BOT_COMMANDS])
    expect(cmds).not.toBe(CLAUDE_BOT_COMMANDS)
  })

  it('nuốt lỗi API, báo qua onError, trả false', async () => {
    let seen: unknown
    const ok = await registerClaudeBotCommands(
      { setMyCommands: async () => { throw new Error('429') } },
      e => { seen = e },
    )
    expect(ok).toBe(false)
    expect((seen as Error).message).toBe('429')
  })
})

describe('SLASH_PROMPTS', () => {
  it('chỉ thị cố định, có nhãn nguồn, chỉ ghi trong ~/collab-bot', () => {
    for (const [name, text] of Object.entries(SLASH_PROMPTS)) {
      expect(text.startsWith(`[slash_command=/${name} `)).toBe(true)
      for (const m of text.matchAll(/~\/[\w./-]+/g)) expect(m[0].startsWith('~/collab-bot/')).toBe(true)
    }
    expect(SLASH_PROMPTS.tasks).toContain('không sửa file')
  })
})

describe('projectSlug + latestTranscript', () => {
  it('slug giống thư mục thật trên VPS', () => {
    expect(projectSlug('/home/claudebot/collab-bot')).toBe('-home-claudebot-collab-bot')
  })

  it('chọn file .jsonl mới nhất', () => {
    const root = mkdtempSync(join(tmpdir(), 'cb-'))
    const dir = join(root, projectSlug('/w/collab-bot'))
    mkdirSync(dir)
    const turn = JSON.stringify({ type: 'system', subtype: 'turn_duration' })
    writeFileSync(join(dir, 'old.jsonl'), turn + '\n')
    writeFileSync(join(dir, 'new.jsonl'), [turn, turn, 'không phải json'].join('\n'))
    writeFileSync(join(dir, 'note.txt'), 'ignore')
    utimesSync(join(dir, 'old.jsonl'), new Date(1000), new Date(1000))
    const t = latestTranscript(root, '/w/collab-bot')
    expect(t?.file).toBe('new.jsonl')
    expect(t?.turns).toBe(2)
  })

  it('thiếu thư mục thì trả null, không ném lỗi', () => {
    expect(latestTranscript('/nonexistent-xyz', '/a')).toBeNull()
  })
})

describe('parseAuthStatus', () => {
  it('chỉ lấy authMethod + loginExpiresAt', () => {
    const a = parseAuthStatus(JSON.stringify({ authMethod: 'claude.ai', loginExpiresAt: '2026-12-24T00:00:00Z', email: 'x' }))
    expect(a).toEqual({ method: 'claude.ai', expiresAt: '2026-12-24T00:00:00Z' })
  })
  it('JSON hỏng hoặc thiếu trường thì null', () => {
    expect(parseAuthStatus('nope')).toBeNull()
    expect(parseAuthStatus('{}')).toBeNull()
  })
})

describe('parseTranscript (metadata thật từ VPS, không có nội dung)', () => {
  const raw = readFileSync(join(import.meta.dir, 'fixtures', 'transcript-meta.jsonl'), 'utf8')
  it('khớp số tính bằng jq trên cùng file', () => {
    const p = parseTranscript(raw)
    expect(p.turns).toBe(11)
    expect(p.cumulativeTokens).toBe(141237)
    expect(p.contextTokens).toBe(80927)
    expect(p.model).toBe('claude-sonnet-5-5')
    expect(p.lastTurnMs).toBe(Date.parse('2026-11-25T09:11:28.670Z'))
    expect(p.firstMs).toBe(Date.parse('2026-11-25T08:17:55.723Z'))
  })
  it('đếm usage 1 lần cho mỗi message.id, bỏ sidechain', () => {
    const u = { input_tokens: 10, cache_read_input_tokens: 100, cache_creation_input_tokens: 5, output_tokens: 20 }
    const rec = (o: object) => JSON.stringify({ type: 'assistant', timestamp: '2026-11-25T00:00:00Z', ...o })
    const p = parseTranscript([
      rec({ message: { id: 'a', model: 'claude-opus-5-5', usage: u } }),
      rec({ message: { id: 'a', model: 'claude-opus-5-5', usage: u } }),
      rec({ isSidechain: true, message: { id: 'b', model: 'claude-haiku-5-5', usage: u } }),
    ].join('\n'))
    expect(p.cumulativeTokens).toBe(35)
    expect(p.contextTokens).toBe(115)
    expect(p.model).toBe('claude-opus-5-5')
  })
  it('cửa sổ context', () => {
    expect(contextWindow('claude-opus-5-5')).toBe(200_000)
    expect(contextWindow('claude-opus-5-5[1m]')).toBe(1_000_000)
  })
})

describe('buildStatusText', () => {
  const now = Date.parse('2026-11-25T12:00:00Z')
  const uptime = 3 * 3600 + 5 * 60
  const start = now - uptime * 1000
  const transcript = {
    file: 'd35d7b02-8a5b.jsonl', bytes: 1, mtimeMs: now, turns: 6, model: 'claude-opus-5-5',
    contextTokens: 77_500, cumulativeTokens: 12_400, lastTurnMs: now - 12 * 60_000, firstMs: start + 30_000,
  }
  const base: StatusInput = {
    now, pluginUptimeSec: uptime, transcript, voiceOn: true,
    auth: { method: 'claude.ai', expiresAt: '2026-12-24T12:00:00Z' }, pairedAs: '@hung',
  }

  it('ca bình thường: đủ thông tin như mẫu Gemini, không cảnh báo', () => {
    const t = buildStatusText(base)
    expect(t).toContain('Model: claude-opus-5-5')
    expect(t).toContain('chạy 3 giờ 5 phút')
    expect(t).toContain('d35d7b02… · 6 lượt · lượt cuối 12 phút trước')
    expect(t).toContain('77,500 / 200,000 tokens (39%)')
    expect(t).toContain('🟨🟨🟨🟨⬜⬜⬜⬜⬜⬜')
    expect(t).toContain('Cộng dồn: 12,400 tokens')
    expect(t).toContain('Voice: BẬT')
    expect(t).toContain('còn 29 ngày')
    expect(t).toContain('Lệnh nhanh: /handover')
    expect(t).not.toContain('⚠️')
  })

  it('cảnh báo model không phải Opus, context đầy, login sắp hết', () => {
    const t = buildStatusText({ ...base,
      transcript: { ...transcript, model: 'claude-sonnet-5-5', contextTokens: 170_000 },
      auth: { method: 'claude.ai', expiresAt: '2026-11-28T12:00:00Z' } })
    expect(t).toContain('⚠️ không phải Opus')
    expect(t).toContain('(85%)')
    expect(t).toContain('nên /handover')
    expect(t).toContain('🟥')
    expect(t).toContain('còn 3 ngày')
  })

  it('transcript của phiên trước restart thì không lấy số', () => {
    const t = buildStatusText({ ...base, transcript: { ...transcript, firstMs: start - 3600_000 } })
    expect(t).toContain('Phiên: mới, chưa có lượt nào')
    expect(t).not.toContain('d35d7b02')
  })

  it('authMethod lạ thì báo rõ; không đọc được thì vẫn trả lời', () => {
    expect(buildStatusText({ ...base, auth: { method: 'api_key' } })).toContain('authMethod=api_key')
    const t = buildStatusText({ ...base, auth: null, transcript: null, voiceOn: false })
    expect(t).toContain('không đọc được trạng thái')
    expect(t).toContain('Voice: TẮT')
  })
})

describe('nút Mở phiên mới', () => {
  const now = Date.parse('2026-11-25T12:30:00Z')
  const since = now - 60_000
  it('chỉ cho mở khi có handover ghi sau lúc bấm /handover và trong 30 phút', () => {
    expect(newSessionVerdict(null, since, now).ok).toBe(false)
    expect(newSessionVerdict(since - 1, since, now).ok).toBe(false)
    expect(newSessionVerdict(since + 10_000, since, now).ok).toBe(true)
    expect(newSessionVerdict(since + 10_000, since, since + 10_000 + 31 * 60_000).ok).toBe(false)
  })
  it('latestHandoverMs chỉ xét handover-*.md', () => {
    const dir = mkdtempSync(join(tmpdir(), 'ho-'))
    writeFileSync(join(dir, 'README.md'), 'x')
    expect(latestHandoverMs(dir)).toBeNull()
    writeFileSync(join(dir, 'handover-20261125-1907.md'), 'x')
    expect(latestHandoverMs(dir)).not.toBeNull()
    expect(latestHandoverMs('/nonexistent-xyz')).toBeNull()
  })
  it('server.ts: handler nút đăng ký TRƯỚC handler perm chung, chặn người lạ, restart tách qua systemd-run', () => {
    const src = readFileSync(join(PLUGIN, 'server.ts'), 'utf8')
    const btn = src.indexOf('bot.callbackQuery(NEW_SESSION_CALLBACK')
    const perm = src.indexOf("bot.on('callback_query:data'")
    expect(btn).toBeGreaterThan(0)
    expect(btn).toBeLessThan(perm)
    const body = src.slice(btn, perm)
    expect(body).toContain("ctx.chat?.type !== 'private'")
    expect(body).toContain('access.allowFrom.includes(senderId)')
    expect(body).toContain("'systemd-run', ['--user'")
    expect(NEW_SESSION_CALLBACK).toMatch(/^[a-z:]{1,64}$/)
  })
})

describe('repo public: không chứa ID Telegram thật', () => {
  it('plugin không hardcode chat/user id (7+ chữ số trong chuỗi)', () => {
    const { readdirSync } = require('node:fs') as typeof import('node:fs')
    for (const f of readdirSync(PLUGIN).filter((n: string) => n.endsWith('.ts'))) {
      const src = readFileSync(join(PLUGIN, f), 'utf8')
      expect({ f, hits: src.match(/'-?\d{7,}'/g) ?? [] }).toEqual({ f, hits: [] })
    }
  })
})
