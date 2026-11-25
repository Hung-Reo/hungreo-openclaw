import { describe, expect, it } from 'bun:test'
import {
  MediaGroupBatcher,
  extractImageSpec,
  formatMediaPrompt,
  mergeAlbumCaptions,
  pickAlbumRepresentative,
} from './media.ts'

describe('extractImageSpec', () => {
  it('picks highest resolution photo', () => {
    const spec = extractImageSpec({
      photo: [
        { file_id: 'small', file_unique_id: 'u1', file_size: 100 },
        { file_id: 'large', file_unique_id: 'u2', file_size: 9000 },
      ],
    })
    expect(spec).toEqual({
      fileId: 'large',
      fileUniqueId: 'u2',
      fallbackExt: 'jpg',
      fileSize: 9000,
    })
  })

  it('accepts uncompressed image document and ignores non-image document', () => {
    expect(
      extractImageSpec({
        document: { file_id: 'doc1', file_unique_id: 'du1', mime_type: 'image/png', file_size: 5000 },
      }),
    ).toEqual({
      fileId: 'doc1',
      fileUniqueId: 'du1',
      fallbackExt: 'png',
      fileSize: 5000,
    })

    expect(
      extractImageSpec({
        document: { file_id: 'pdf1', file_unique_id: 'pu1', mime_type: 'application/pdf', file_size: 5000 },
      }),
    ).toBeNull()
  })
})

describe('album helpers', () => {
  it('picks item with caption+entities as representative for gate check', () => {
    const items = [
      { message: { message_id: 1 } },
      {
        message: {
          message_id: 2,
          caption: '@hungreo_gemini_bot xem giúp',
          caption_entities: [{ type: 'mention', offset: 0, length: 19 }],
        },
      },
      { message: { message_id: 3 } },
    ]
    expect(pickAlbumRepresentative(items).message?.message_id).toBe(2)
    expect(mergeAlbumCaptions(items)).toBe('@hungreo_gemini_bot xem giúp')
  })

  it('formats multi-photo album prompt', () => {
    const prompt = formatMediaPrompt({
      rawText: 'So sánh 3 ảnh này',
      photoPaths: ['/tmp/p1.jpg', '/tmp/p2.jpg', '/tmp/p3.jpg'],
    })
    expect(prompt).toContain('So sánh 3 ảnh này')
    expect(prompt).toContain('Album 3 ảnh đính kèm')
    expect(prompt).toContain('1. /tmp/p1.jpg')
    expect(prompt).toContain('3. /tmp/p3.jpg')
    expect(prompt).toContain('toàn bộ 3 ảnh trên')
  })

  it('formats voice prompt with mandatory transcript header instruction', () => {
    const prompt = formatMediaPrompt({
      rawText: '',
      voicePath: '/tmp/voice-1.ogg',
      voiceDuration: 18,
    })
    expect(prompt).toContain('/tmp/voice-1.ogg')
    expect(prompt).toContain('voice 18s')
    expect(prompt).toContain('read_file')
    expect(prompt).toContain('🎙️ **Em nghe được (voice 18s):**')
  })

  it('batches items in MediaGroupBatcher within debounce window', async () => {
    const batcher = new MediaGroupBatcher<number>(40, 5)
    const flushed: number[][] = []
    batcher.enqueue('g1', 1, items => flushed.push(items))
    batcher.enqueue('g1', 2, items => flushed.push(items))
    batcher.enqueue('g1', 3, items => flushed.push(items))
    expect(flushed).toHaveLength(0)
    await new Promise(r => setTimeout(r, 80))
    expect(flushed).toEqual([[1, 2, 3]])
  })

  it('flushes immediately when hitting maxItems', () => {
    const batcher = new MediaGroupBatcher<number>(500, 3)
    const flushed: number[][] = []
    batcher.enqueue('g2', 10, items => flushed.push(items))
    batcher.enqueue('g2', 20, items => flushed.push(items))
    batcher.enqueue('g2', 30, items => flushed.push(items))
    expect(flushed).toEqual([[10, 20, 30]])
    batcher.clearAll()
  })
})
