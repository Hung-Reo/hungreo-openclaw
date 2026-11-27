import { describe, expect, it } from 'bun:test'
import { FW_PYTHON, FW_WORKER, WHISPER, sttCommand } from '../plugin/voice-stt.ts'

describe('sttCommand (VOICE-QUALITY-20261127)', () => {
  it('có venv + worker → faster-whisper, python -I', () => {
    const c = sttCommand('/m.bin', '/in.wav', () => true)
    expect(c).toEqual({ cmd: FW_PYTHON, args: ['-I', FW_WORKER, '/in.wav'], engine: 'faster-whisper' })
  })
  it('thiếu venv hoặc worker → whisper.cpp như cũ, KHÔNG có --prompt (bịa câu trong A/B)', () => {
    for (const missing of [FW_PYTHON, FW_WORKER]) {
      const c = sttCommand('/m.bin', '/in.wav', p => p !== missing)
      expect(c.engine).toBe('whisper.cpp')
      expect(c.cmd).toBe(WHISPER)
      expect(c.args).toEqual(['-m', '/m.bin', '-f', '/in.wav', '-l', 'vi', '-nt', '-np'])
      expect(c.args).not.toContain('--prompt')
    }
  })
})
