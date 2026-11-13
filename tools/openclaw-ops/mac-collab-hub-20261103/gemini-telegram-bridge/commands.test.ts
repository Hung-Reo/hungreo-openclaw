import { describe, expect, it } from 'bun:test'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import {
  GEMINI_BOT_COMMANDS,
  registerGeminiBotCommands,
  type TelegramBotCommand,
  type TelegramCommandScope,
} from './commands.ts'

describe('GEMINI_BOT_COMMANDS', () => {
  it('matches every bot.command handler defined in server.ts and Telegram naming rules', () => {
    const serverSource = readFileSync(join(import.meta.dir, 'server.ts'), 'utf8')
    const handlerNames = [...serverSource.matchAll(/bot\.command\('([a-z0-9_]+)'/g)].map(m => m[1])
    const menuNames = GEMINI_BOT_COMMANDS.map(c => c.command)

    expect(handlerNames.length).toBeGreaterThan(0)
    expect(new Set(menuNames)).toEqual(new Set(handlerNames))

    for (const entry of GEMINI_BOT_COMMANDS) {
      expect(entry.command).toMatch(/^[a-z0-9_]{1,32}$/)
      expect(entry.description.length).toBeGreaterThanOrEqual(3)
      expect(entry.description.length).toBeLessThanOrEqual(256)
    }
  })
})

describe('registerGeminiBotCommands', () => {
  it('registers commands for all_private_chats and returns true on success', async () => {
    let capturedCommands: TelegramBotCommand[] | undefined
    let capturedScope: TelegramCommandScope | undefined

    const ok = await registerGeminiBotCommands({
      setMyCommands: async (commands, other) => {
        capturedCommands = commands
        capturedScope = other?.scope
      },
    })

    expect(ok).toBe(true)
    expect(capturedScope).toEqual({ type: 'all_private_chats' })
    expect(capturedCommands).toEqual([...GEMINI_BOT_COMMANDS])
    expect(capturedCommands).not.toBe(GEMINI_BOT_COMMANDS)
  })

  it('catches API errors, forwards to onError, and returns false without throwing', async () => {
    let seenError: unknown
    const ok = await registerGeminiBotCommands(
      {
        setMyCommands: async () => {
          throw new Error('429 Too Many Requests')
        },
      },
      err => {
        seenError = err
      },
    )

    expect(ok).toBe(false)
    expect(seenError).toBeInstanceOf(Error)
    expect((seenError as Error).message).toBe('429 Too Many Requests')
  })
})
