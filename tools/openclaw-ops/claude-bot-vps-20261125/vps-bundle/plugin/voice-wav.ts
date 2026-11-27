// Duration from the RIFF 'data' chunk + 'fmt ' chunk, not from file size.
export function wavDurationSec(buf: Uint8Array): number {
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength)
  const tag = (o: number) => String.fromCharCode(buf[o], buf[o + 1], buf[o + 2], buf[o + 3])
  if (buf.length < 12 || tag(0) !== 'RIFF' || tag(8) !== 'WAVE') throw new Error('not_wav')
  let off = 12, byteRate = 0, blockAlign = 0
  while (off + 8 <= buf.length) {
    const id = tag(off), size = dv.getUint32(off + 4, true), body = off + 8
    if (id === 'fmt ') { byteRate = dv.getUint32(body + 8, true); blockAlign = dv.getUint16(body + 12, true) }
    if (id === 'data') {
      if (!byteRate || !blockAlign) throw new Error('fmt_missing')
      const avail = buf.length - body
      const dataBytes = size === 0xffffffff || size > avail ? avail : size
      return Math.floor(dataBytes / blockAlign) * blockAlign / byteRate
    }
    off = body + size + (size & 1)
  }
  throw new Error('data_missing')
}
export const MAX_VOICE_SEC = 120
export const TOLERANCE_SEC = 0.5   // Opus/ffmpeg framing slack; 120.0x s must pass
export const tooLong = (sec: number) => sec > MAX_VOICE_SEC + TOLERANCE_SEC
