/**
 * Helpers for handling single & multi-image (Telegram media_group_id) and voice media inputs.
 */

export const MAX_ALBUM_PHOTOS = 10
export const ALBUM_DEBOUNCE_MS = 700

export type ImageSpec = {
  fileId: string
  fileUniqueId: string
  fallbackExt: string
  fileSize?: number
}

export type MessageMediaLike = {
  message_id?: number
  caption?: string
  media_group_id?: string
  reply_to_message?: unknown
  caption_entities?: unknown[]
  photo?: Array<{
    file_id: string
    file_unique_id: string
    file_size?: number
  }>
  document?: {
    file_id: string
    file_unique_id: string
    file_size?: number
    mime_type?: string
  }
}

const MIME_EXT_MAP: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/jpg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/gif': 'gif',
  'image/heic': 'heic',
  'image/heif': 'heif',
}

/**
 * Extracts download info if the Telegram message carries a compressed photo
 * or an uncompressed image document. Returns null for non-image documents.
 */
export function extractImageSpec(msg: MessageMediaLike | undefined): ImageSpec | null {
  if (!msg) {return null}
  if (msg.photo && msg.photo.length > 0) {
    const best = msg.photo[msg.photo.length - 1]
    return {
      fileId: best.file_id,
      fileUniqueId: best.file_unique_id,
      fallbackExt: 'jpg',
      fileSize: best.file_size,
    }
  }
  const doc = msg.document
  const mime = doc?.mime_type?.toLowerCase()
  if (doc && mime && mime.startsWith('image/')) {
    return {
      fileId: doc.file_id,
      fileUniqueId: doc.file_unique_id,
      fallbackExt: MIME_EXT_MAP[mime] ?? 'jpg',
      fileSize: doc.file_size,
    }
  }
  return null
}

/**
 * Picks the best representative item from a Telegram album for inbound gate evaluation
 * (Telegram usually attaches caption/mentions/reply_to_message to only one item).
 */
export function pickAlbumRepresentative<T extends { message?: MessageMediaLike }>(items: readonly T[]): T {
  const withCaptionAndEntities = items.find(
    it => Boolean(it.message?.caption?.trim()) && (it.message?.caption_entities?.length ?? 0) > 0,
  )
  if (withCaptionAndEntities) {return withCaptionAndEntities}
  const withCaption = items.find(it => Boolean(it.message?.caption?.trim()))
  if (withCaption) {return withCaption}
  const withReply = items.find(it => Boolean(it.message?.reply_to_message))
  if (withReply) {return withReply}
  return items[0]
}

/** Merges distinct non-empty captions from an album while preserving order. */
export function mergeAlbumCaptions(items: readonly { message?: MessageMediaLike }[]): string {
  const seen = new Set<string>()
  const parts: string[] = []
  for (const it of items) {
    const cap = it.message?.caption?.trim()
    if (cap && !seen.has(cap)) {
      seen.add(cap)
      parts.push(cap)
    }
  }
  return parts.join('\n')
}

/** Formats user text + attached media instructions for Gemini CLI. */
export function formatMediaPrompt(params: {
  rawText: string
  photoPaths?: readonly string[]
  voicePath?: string
  voiceDuration?: number
}): string {
  const sections: string[] = []
  const text = params.rawText.trim()
  if (text) {sections.push(text)}

  if (params.voicePath) {
    const dur = params.voiceDuration ?? 0
    sections.push(
      `[Tin nhắn thoại (voice ${dur}s) đính kèm tại: ${params.voicePath} — Hãy dùng tool read_file để nghe trực tiếp file âm thanh này. BẮT BUỘC mở đầu câu trả lời bằng mục:\n🎙️ **Em nghe được (voice ${dur}s):**\n_"<nguyên văn nội dung nghe được>"_\nrồi mới trả lời nội dung chính bằng tiếng Việt bên dưới.]`,
    )
  }

  const photos = params.photoPaths ?? []
  if (photos.length === 1) {
    sections.push(
      `[Ảnh đính kèm tại: ${photos[0]} — Hãy dùng tool read_file để xem trực tiếp nội dung ảnh này trước khi trả lời.]`,
    )
  } else if (photos.length > 1) {
    const list = photos.map((p, idx) => `${idx + 1}. ${p}`).join('\n')
    sections.push(
      `[Album ${photos.length} ảnh đính kèm:\n${list}\n— Hãy dùng tool read_file để xem trực tiếp toàn bộ ${photos.length} ảnh trên trước khi trả lời.]`,
    )
  }

  return sections.join('\n\n')
}

/**
 * Debounces incoming Telegram media_group_id updates into a single batch
 * so multi-photo albums are processed together in one model turn.
 */
export class MediaGroupBatcher<T> {
  private buckets = new Map<string, { items: T[]; timer: ReturnType<typeof setTimeout> }>()

  constructor(
    private readonly debounceMs = ALBUM_DEBOUNCE_MS,
    private readonly maxItems = MAX_ALBUM_PHOTOS,
  ) {}

  enqueue(key: string, item: T, onFlush: (items: T[]) => void): void {
    const existing = this.buckets.get(key)
    if (existing) {
      clearTimeout(existing.timer)
      if (existing.items.length < this.maxItems) {
        existing.items.push(item)
      }
      if (existing.items.length >= this.maxItems) {
        this.buckets.delete(key)
        onFlush(existing.items)
        return
      }
      existing.timer = setTimeout(() => this.flush(key, onFlush), this.debounceMs)
      return
    }

    const timer = setTimeout(() => this.flush(key, onFlush), this.debounceMs)
    this.buckets.set(key, { items: [item], timer })
  }

  private flush(key: string, onFlush: (items: T[]) => void): void {
    const bucket = this.buckets.get(key)
    if (!bucket) {return}
    this.buckets.delete(key)
    clearTimeout(bucket.timer)
    onFlush(bucket.items)
  }

  clearAll(): void {
    for (const bucket of this.buckets.values()) {
      clearTimeout(bucket.timer)
    }
    this.buckets.clear()
  }
}
