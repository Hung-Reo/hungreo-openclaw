// Standard Markdown -> Telegram MarkdownV2, ported from Hermes Agent v0.22.5
// (plugins/platforms/telegram/adapter.py format_message, _strip_mdv2;
// gateway/platforms/helpers.py table rendering). Hermes is MIT, (c) 2025 Nous Research.
// Keep behaviour in step with Hermes: telegram-format.golden.json holds its real output.

const ESCAPE_RE = /([_*\[\]()~`>#+\-=|{}.!\\])/g
const TABLE_SEPARATOR_RE = /^\s*\|?\s*:?-+:?\s*(?:\|\s*:?-+:?\s*){1,}\|?\s*$/

export function escapeMdv2(text: string): string {
  return text.replace(ESCAPE_RE, '\\$1')
}

// Plain-text fallback used when Telegram rejects the MarkdownV2 entities.
export function stripMdv2(text: string): string {
  return text
    .replace(/\\([_*\[\]()~`>#+\-=|{}.!\\])/g, '$1')
    .replace(/\*\*([^*]+)\*\*/g, '$1')
    .replace(/\*([^*]+)\*/g, '$1')
    .replace(/(?<!\w)_([^_]+)_(?!\w)/g, '$1')
    .replace(/~([^~]+)~/g, '$1')
    .replace(/\|\|([^|]+)\|\|/g, '$1')
}

function splitTableRow(line: string): string[] {
  let row = line.trim()
  if (row.startsWith('|')) row = row.slice(1)
  if (row.endsWith('|') && !row.endsWith('\\|')) row = row.slice(0, -1)
  return row.split(/(?<!\\)\|/).map(cell => cell.trim().replace(/\\\|/g, '|'))
}

function renderTableBlock(block: string[]): string {
  const headers = block.length >= 3 ? splitTableRow(block[0]!) : []
  if (headers.length < 2) return block.join('\n')
  const hasRowLabel = splitTableRow(block[2]!).length === headers.length + 1
  const groups = block.slice(2).map((row, i) => {
    const cells = splitTableRow(row)
    const fallback = `Row ${i + 1}`
    const heading = hasRowLabel ? cells[0] || fallback : cells.find(Boolean) ?? fallback
    const data = [...(hasRowLabel ? cells.slice(1) : cells), ...headers.map(() => '')].slice(0, headers.length)
    const bullets = headers
      .map((header, k) => ({ header, value: data[k]! }))
      .filter(({ value }) => hasRowLabel || value !== heading)
      .map(({ header, value }) => `• ${header}: ${value}`)
    return [`**${heading}**`, ...bullets].join('\n')
  })
  return groups.join('\n\n')
}

function tablesToBullets(text: string): string {
  if (!text.includes('|') || !text.includes('-')) return text
  const lines = text.split('\n')
  const out: string[] = []
  let inFence = false
  for (let i = 0; i < lines.length; ) {
    const line = lines[i]!
    const isFence = line.trimStart().startsWith('```')
    if (isFence) inFence = !inFence
    if (!inFence && !isFence && line.includes('|') && i + 1 < lines.length && TABLE_SEPARATOR_RE.test(lines[i + 1]!)) {
      let j = i + 2
      while (j < lines.length && lines[j]!.trim().includes('|')) j++
      out.push(renderTableBlock(lines.slice(i, j)))
      i = j
    } else {
      out.push(line)
      i++
    }
  }
  return out.join('\n')
}

function escapeBareBracket(ch: string, s: number, seg: string): string {
  if (s > 0 && seg[s - 1] === '\\') return ch
  if (ch === '(' && s > 0 && seg[s - 1] === ']') return ch
  if (ch === ')' && seg.slice(0, s).includes('](')) {
    let depth = 0
    for (let j = s - 1; j > Math.max(s - 2000, -1); j--) {
      if (seg[j] === '(') {
        depth--
        if (depth < 0) {
          if (j > 0 && seg[j - 1] === ']') return ch
          break
        }
      } else if (seg[j] === ')') {
        depth++
      }
    }
  }
  return `\\${ch}`
}

export function markdownToMdv2(content: string): string {
  if (!content) return content
  const stash: Array<[string, string]> = []
  const ph = (value: string): string => {
    const key = `\x00PH${stash.length}\x00`
    stash.push([key, value])
    return key
  }

  let text = tablesToBullets(content)
  text = text.replace(
    /^((?:(?!```)[^\n])*)(```[^`\n]*\n)([\s\S]*?)(^[ \t]*```)[ \t]*\r?$/gm,
    (_m, prefix: string, open: string, body: string, close: string) =>
      prefix + ph(open + body.replace(/\\/g, '\\\\').replace(/`/g, '\\`') + close),
  )
  text = text.replace(/(`[^`]+`)/g, m => ph(m.replace(/\\/g, '\\\\')))
  text = text.replace(/\[([^\]]+)\]\(([^()]*(?:\([^()]*\)[^()]*)*)\)/g, (_m, label: string, url: string) =>
    ph(`[${escapeMdv2(label)}](${url.replace(/\\/g, '\\\\').replace(/\)/g, '\\)')})`),
  )
  text = text.replace(/^#{1,6}[ \t]+(.+)$/gm, (_m, title: string) =>
    ph(`*${escapeMdv2(title.trim().replace(/\*\*(.+?)\*\*/g, '$1'))}*`),
  )
  text = text.replace(/\*\*(.+?)\*\*/g, (_m, s: string) => ph(`*${escapeMdv2(s)}*`))
  text = text.replace(/\*([^*\n]+)\*/g, (_m, s: string) => ph(`_${escapeMdv2(s)}_`))
  text = text.replace(/~~(.+?)~~/g, (_m, s: string) => ph(`~${escapeMdv2(s)}~`))
  text = text.replace(/\|\|(.+?)\|\|/g, (_m, s: string) => ph(`||${escapeMdv2(s)}||`))
  text = text.replace(/^((?:\*\*)?>{1,3}) (.+)$/gm, (_m, prefix: string, s: string) =>
    prefix.startsWith('**') && s.endsWith('||')
      ? ph(`${prefix} ${escapeMdv2(s.slice(0, -2))}||`)
      : ph(`${prefix} ${escapeMdv2(s)}`),
  )
  text = escapeMdv2(text)
  for (const [key, value] of [...stash].reverse()) text = text.split(key).join(value)

  return text
    .split(/(```[\s\S]*?```|`[^`]+`)/)
    .map((seg, i) => (i % 2 === 1 ? seg : seg.replace(/[(){}]/g, (ch, s: number) => escapeBareBracket(ch, s, seg))))
    .join('')
}

// A cut inside a code fence would leave unbalanced ``` in both parts, so close and reopen it.
function balanceFences(chunks: string[]): string[] {
  let open: string | null = null
  return chunks.map(part => {
    let out = open ? `${open}\n${part}` : part
    for (const line of part.split('\n')) {
      if (line.trimStart().startsWith('```')) open = open ? null : line.trim()
    }
    if (open) out += '\n```'
    return out
  })
}

// Splits on the Markdown source (so entities are not cut), then converts each part.
// Escaping grows the text, so retry with a smaller source limit until every part fits.
export function formatChunks(
  text: string,
  limit: number,
  split: (text: string, limit: number) => string[],
): string[] {
  const reserve = 16 // room for the " (12/34)" marker and a reopened fence
  for (let sourceLimit = limit; sourceLimit >= 256; sourceLimit = Math.floor(sourceLimit * 0.75)) {
    const parts = balanceFences(split(text, sourceLimit))
    const formatted = parts.map(markdownToMdv2)
    if (formatted.every(part => part.length <= limit - reserve)) {
      if (formatted.length === 1) return formatted
      return formatted.map((part, i) => {
        const marker = `\\(${i + 1}/${formatted.length}\\)`
        return part.endsWith('```') ? `${part}\n${marker}` : `${part} ${marker}`
      })
    }
  }
  throw new Error('markdown reply could not be split to fit Telegram limit')
}

export function isEntityParseError(err: unknown): boolean {
  return err instanceof Error && /can't parse entities|can't find end of/i.test(err.message)
}
