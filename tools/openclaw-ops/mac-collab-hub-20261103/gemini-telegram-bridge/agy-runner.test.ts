import { describe, expect, it } from 'bun:test'
import { EventEmitter } from 'node:events'
import type { ChildProcess } from 'node:child_process'
import {
  buildAgyArgs,
  DEFAULT_IDLE_TIMEOUT_MS,
  DEFAULT_MAX_TIMEOUT_MS,
  resolveAgyTimeoutConfig,
  runAgyProcess,
} from './agy-runner.ts'

class FakeChildProcess extends EventEmitter {
  stdout = new EventEmitter()
  stderr = new EventEmitter()
  killedSignals: string[] = []
  autoCloseOnKill = true

  kill(signal: NodeJS.Signals = 'SIGTERM'): boolean {
    this.killedSignals.push(signal)
    if (this.autoCloseOnKill) {
      queueMicrotask(() => this.emit('close', null))
    }
    return true
  }
}

describe('resolveAgyTimeoutConfig', () => {
  it('uses extended defaults (15m max, 5m idle) when env vars are unset', () => {
    const cfg = resolveAgyTimeoutConfig({})
    expect(cfg.maxTimeoutMs).toBe(DEFAULT_MAX_TIMEOUT_MS)
    expect(cfg.idleTimeoutMs).toBe(DEFAULT_IDLE_TIMEOUT_MS)
    expect(cfg.maxTimeoutMs).toBe(900_000)
    expect(cfg.idleTimeoutMs).toBe(300_000)
  })

  it('respects GEMINI_MAX_TIMEOUT_MS, GEMINI_TIMEOUT_MS, and GEMINI_IDLE_TIMEOUT_MS', () => {
    expect(resolveAgyTimeoutConfig({ GEMINI_TIMEOUT_MS: '600000' })).toEqual({
      maxTimeoutMs: 600_000,
      idleTimeoutMs: 300_000,
      killGraceMs: 5_000,
    })

    expect(
      resolveAgyTimeoutConfig({
        GEMINI_MAX_TIMEOUT_MS: '1200000',
        GEMINI_TIMEOUT_MS: '600000',
        GEMINI_IDLE_TIMEOUT_MS: '450000',
      }),
    ).toEqual({
      maxTimeoutMs: 1_200_000,
      idleTimeoutMs: 450_000,
      killGraceMs: 5_000,
    })
  })

  it('allows disabling idle timeout with 0 and clamps idle <= max', () => {
    expect(resolveAgyTimeoutConfig({ GEMINI_IDLE_TIMEOUT_MS: '0', GEMINI_MAX_TIMEOUT_MS: '120000' })).toEqual({
      maxTimeoutMs: 120_000,
      idleTimeoutMs: 0,
      killGraceMs: 5_000,
    })

    expect(resolveAgyTimeoutConfig({ GEMINI_IDLE_TIMEOUT_MS: '500000', GEMINI_MAX_TIMEOUT_MS: '120000' })).toEqual({
      maxTimeoutMs: 120_000,
      idleTimeoutMs: 120_000,
      killGraceMs: 5_000,
    })
  })
})

describe('buildAgyArgs', () => {
  it('defaults to sandbox + accept-edits + settings without dangerously-skip-permissions', () => {
    const args = buildAgyArgs({
      model: 'gemini-4-hydrogen-high',
      conversationId: 'conv-123',
      settingsPath: '/tmp/gemini-collab-settings.json',
      prompt: 'Xin chào',
    })
    expect(args).toEqual([
      '--output-format',
      'stream-json',
      '--sandbox',
      '--mode',
      'accept-edits',
      '--settings',
      '/tmp/gemini-collab-settings.json',
      '--model',
      'gemini-4-hydrogen-high',
      '--conversation',
      'conv-123',
      '-p',
      'Xin chào',
    ])
  })

  it('supports explicit dangerouslySkipPermissions opt-in while keeping settings', () => {
    const args = buildAgyArgs({
      dangerouslySkipPermissions: true,
      settingsPath: '/tmp/gemini-collab-settings.json',
      prompt: 'Hi',
    })
    expect(args).toEqual([
      '--output-format',
      'stream-json',
      '--sandbox',
      '--dangerously-skip-permissions',
      '--settings',
      '/tmp/gemini-collab-settings.json',
      '-p',
      'Hi',
    ])
  })
})

describe('runAgyProcess', () => {
  it('resets idle timeout on streaming activity and completes beyond idle window up to maxTimeout', async () => {
    const child = new FakeChildProcess()
    const logs: string[] = []

    const promise = runAgyProcess({
      agyBin: '/fake/agy',
      args: ['--output-format', 'stream-json', '-p', 'hi'],
      cwd: '/tmp',
      env: {},
      timeouts: { maxTimeoutMs: 500, idleTimeoutMs: 60, killGraceMs: 20 },
      log: line => logs.push(line),
      spawnFn: () => child as unknown as ChildProcess,
    })

    // Emit periodic stream-json events every 35ms (total ~105ms > 60ms idleTimeout)
    setTimeout(() => {
      child.stdout.emit(
        'data',
        JSON.stringify({ event: 'init', conversation_id: 'c1', init: { model: 'g4', permission_mode: 'auto' } }) +
          '\n',
      )
    }, 20)

    setTimeout(() => {
      child.stdout.emit(
        'data',
        JSON.stringify({
          event: 'step_update',
          step_update: {
            conversation_id: 'c1',
            state: 'ACTIVE',
            step_type: 'tool',
            tool_name: 'read_file',
            tool_info: { parameters: { Path: '/tmp/a.ts' } },
          },
        }) + '\n',
      )
    }, 55)

    setTimeout(() => {
      child.stdout.emit(
        'data',
        JSON.stringify({
          event: 'result',
          result: { conversation_id: 'c1', status: 'SUCCESS', response: 'Xong rồi!', duration_seconds: 0.1 },
        }) + '\n',
      )
      child.emit('close', 0)
    }, 95)

    const res = await promise
    expect(res.conversationId).toBe('c1')
    expect(res.response).toBe('Xong rồi!')
    expect(child.killedSignals).toEqual([])
    expect(logs.some(l => l.includes('read_file'))).toBe(true)
  })

  it('rejects with idle timeout when process stays silent', async () => {
    const child = new FakeChildProcess()
    const promise = runAgyProcess({
      agyBin: '/fake/agy',
      args: ['-p', 'hang'],
      cwd: '/tmp',
      env: {},
      timeouts: { maxTimeoutMs: 500, idleTimeoutMs: 40, killGraceMs: 20 },
      spawnFn: () => child as unknown as ChildProcess,
    })

    await expect(promise).rejects.toThrow(/idle timeout/i)
    expect(child.killedSignals).toContain('SIGTERM')
  })

  it('rejects with max timeout even when process keeps emitting output', async () => {
    const child = new FakeChildProcess()
    const interval = setInterval(() => {
      child.stdout.emit('data', '{"event":"ping"}\n')
    }, 20)

    try {
      const promise = runAgyProcess({
        agyBin: '/fake/agy',
        args: ['-p', 'long'],
        cwd: '/tmp',
        env: {},
        timeouts: { maxTimeoutMs: 75, idleTimeoutMs: 50, killGraceMs: 20 },
        spawnFn: () => child as unknown as ChildProcess,
      })

      await expect(promise).rejects.toThrow(/max timeout/i)
      expect(child.killedSignals).toContain('SIGTERM')
    } finally {
      clearInterval(interval)
    }
  })
})
