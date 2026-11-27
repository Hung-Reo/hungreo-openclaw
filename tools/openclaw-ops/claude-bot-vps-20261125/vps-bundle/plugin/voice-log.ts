// ROOM-CHANGE-VOICELOG-20261109-01: the CLI does not keep a plugin's stderr, so collab_voice
// lines are also appended to <STATE_DIR>/logs/collab-voice.jsonl. Metadata only (same line as stderr).
// Best effort: a log failure must never break voice handling.
import { appendFileSync, chmodSync, mkdirSync, renameSync, statSync } from 'fs'
import { join } from 'path'

export const VOICE_LOG_MAX_BYTES = 5 * 1024 * 1024

export function makeVoiceLogFile(dir: string, maxBytes = VOICE_LOG_MAX_BYTES): (line: string) => void {
  const file = join(dir, 'collab-voice.jsonl')
  return line => {
    try {
      mkdirSync(dir, { recursive: true, mode: 0o700 })
      let size = 0
      try { size = statSync(file).size } catch {}
      // Keep exactly one previous file: bounded disk use, still enough history to debug.
      if (size > 0 && size + Buffer.byteLength(line) > maxBytes) renameSync(file, file + '.1')
      appendFileSync(file, line, { mode: 0o600 })
      chmodSync(file, 0o600)
    } catch {}
  }
}
