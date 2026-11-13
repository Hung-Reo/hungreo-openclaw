import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import { formatChunks, isEntityParseError, markdownToMdv2, stripMdv2 } from './claude-telegram-plugin/telegram-format.ts'

const golden = JSON.parse(readFileSync(new URL('./telegram-format.golden.json', import.meta.url), 'utf8')) as {
  samples: string[]
  mdv2: string[]
  plain: string[]
}
const split = (text: string, limit: number): string[] => {
  const out: string[] = []
  for (let i = 0; i < text.length; i += limit) {out.push(text.slice(i, i + limit))}
  return out
}

golden.samples.forEach((sample, i) => {
  test(`matches Hermes MarkdownV2 output, sample ${i}`, () => {
    assert.equal(markdownToMdv2(sample), golden.mdv2[i])
  })
  test(`matches Hermes plain fallback, sample ${i}`, () => {
    assert.equal(stripMdv2(golden.mdv2[i]), golden.plain[i])
  })
})

test('short reply stays one message with no part marker', () => {
  assert.deepEqual(formatChunks('**a**', 4096, split), ['*a*'])
})

test('long reply parts fit the limit and carry part markers', () => {
  const parts = formatChunks('a.b-c '.repeat(2000), 4096, split)
  assert.ok(parts.length > 1)
  parts.forEach((part, i) => {
    assert.ok(part.length <= 4096)
    assert.ok(part.endsWith(`\\(${i + 1}/${parts.length}\\)`))
  })
})

test('a code fence cut between parts is closed and reopened', () => {
  const parts = formatChunks(`\`\`\`bash\n${'echo x\n'.repeat(1000)}\`\`\`\nxong`, 4096, split)
  assert.ok(parts.length > 1)
  for (const part of parts) {assert.equal((part.match(/```/g) ?? []).length % 2, 0)}
  assert.ok(parts[1].startsWith('```bash'))
})

test('only entity parse errors trigger the plain fallback', () => {
  assert.equal(isEntityParseError(new Error("Bad Request: can't parse entities: x")), true)
  assert.equal(isEntityParseError(new Error('Forbidden: bot was blocked')), false)
})
