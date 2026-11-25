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

  it('chọn file .jsonl mới nhất và đếm bản ghi', () => {
    const root = mkdtempSync(join(tmpdir(), 'cb-'))
    const dir = join(root, projectSlug('/w/collab-bot'))
    mkdirSync(dir)
    writeFileSync(join(dir, 'old.jsonl'), 'a\nb\n')
    writeFileSync(join(dir, 'new.jsonl'), 'x\ny\nz\n')
    writeFileSync(join(dir, 'note.txt'), 'ignore')
    utimesSync(join(dir, 'old.jsonl'), new Date(1000), new Date(1000))
    const t = latestTranscript(root, '/w/collab-bot')
    expect(t?.file).toBe('new.jsonl')
    expect(t?.records).toBe(3)
    expect(t?.bytes).toBe(6)
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

describe('buildStatusText', () => {
  const now = Date.parse('2026-11-25T12:00:00Z')
  const base: StatusInput = {
    now, pluginUptimeSec: 3 * 3600 + 5 * 60,
    transcript: { file: 'a.jsonl', bytes: 744054, records: 167, mtimeMs: now },
    voiceOn: true,
    auth: { method: 'claude.ai', expiresAt: '2026-12-24T12:00:00Z' },
    pairedAs: '@hung',
  }

  it('ca bình thường: đủ 5 dòng, không cảnh báo', () => {
    const t = buildStatusText(base)
    expect(t.split('\n').length).toBe(5)
    expect(t).toContain('@hung')
    expect(t).toContain('3 giờ 5 phút')
    expect(t).toContain('727 KB, 167 bản ghi')
    expect(t).toContain('Voice: BẬT')
    expect(t).toContain('còn 29 ngày')
    expect(t).not.toContain('⚠️')
  })

  it('cảnh báo khi transcript to và login sắp hết', () => {
    const t = buildStatusText({ ...base, transcript: { ...base.transcript!, bytes: 6 * 1024 * 1024 },
      auth: { method: 'claude.ai', expiresAt: '2026-11-28T12:00:00Z' } })
    expect(t).toContain('phiên đã dài')
    expect(t).toContain('còn 3 ngày')
    expect(t).toContain('sắp hết')
  })

  it('authMethod không phải claude.ai thì báo rõ', () => {
    expect(buildStatusText({ ...base, auth: { method: 'api_key' } })).toContain('authMethod=api_key')
  })

  it('không đọc được auth / transcript thì vẫn trả lời', () => {
    const t = buildStatusText({ ...base, auth: null, transcript: null, voiceOn: false })
    expect(t).toContain('không đọc được trạng thái')
    expect(t).toContain('chưa thấy file')
    expect(t).toContain('Voice: TẮT')
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
