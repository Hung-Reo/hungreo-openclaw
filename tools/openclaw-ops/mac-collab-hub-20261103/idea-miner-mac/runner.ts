import { existsSync, mkdirSync, renameSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { redactSensitiveOutput } from '../lib/collab-gate.ts'
import { collectWeeklyDigest } from './collector.ts'
import { formatIdeaMinerTelegramMessage } from './formatter.ts'
import { buildDeterministicFallbackReport, buildIdeaMinerPrompt, parseAndValidateIdeaMinerOutput } from './prompt.ts'
import type { IdeaMinerMode, IdeaMinerReport, RunIdeaMinerResult } from './types.ts'

export type IdeaMinerPromptRunner = (prompt: string) => Promise<{ ok: boolean; text?: string; error?: string }>

function writeAtomic0600(filePath: string, content: string): void {
  mkdirSync(dirname(filePath), { recursive: true, mode: 0o700 })
  const tmpPath = `${filePath}.tmp`
  writeFileSync(tmpPath, redactSensitiveOutput(content), { mode: 0o600 })
  renameSync(tmpPath, filePath)
}

function writeJsonAtomic(filePath: string, data: unknown): void {
  writeAtomic0600(filePath, JSON.stringify(data, null, 2) + '\n')
}

export async function runIdeaMinerPipeline(params: {
  stateDir: string
  mode: IdeaMinerMode
  brainDir?: string
  lessonsDir?: string
  runEditorPrompt?: IdeaMinerPromptRunner
  nowMs?: number
  windowDays?: number
}): Promise<RunIdeaMinerResult> {
  const startedAt = Date.now()
  const nowMs = params.nowMs ?? Date.now()
  const handoversDir = join(params.stateDir, 'handovers')

  let digest
  try {
    digest = collectWeeklyDigest({
      handoversDir,
      brainDir: params.brainDir,
      lessonsDir: params.lessonsDir,
      nowMs,
      windowDays: params.windowDays ?? 7,
    })
  } catch (err) {
    return {
      ok: false,
      stage: 'collect',
      error: redactSensitiveOutput(err instanceof Error ? err.message : String(err)),
      durationSeconds: (Date.now() - startedAt) / 1000,
    }
  }

  const runFolderKey = params.mode === 'scheduled' ? digest.weekKey : `${digest.weekKey}-${params.mode}`
  const runDir = join(params.stateDir, 'idea-miner', 'runs', runFolderKey)
  const reportPath = join(runDir, 'report.md')

  if (params.mode === 'scheduled' && existsSync(reportPath)) {
    return {
      ok: true,
      skipped: true,
      skipReason: `Báo cáo Idea Miner tuần ${digest.weekKey} đã được gửi trước đó.`,
      durationSeconds: (Date.now() - startedAt) / 1000,
    }
  }

  mkdirSync(runDir, { recursive: true, mode: 0o700 })
  writeJsonAtomic(join(runDir, 'digest.json'), digest)

  let report: IdeaMinerReport
  if (params.mode === 'dry-run' || !params.runEditorPrompt) {
    report = buildDeterministicFallbackReport(digest)
  } else {
    const prompt = buildIdeaMinerPrompt(digest)
    try {
      const editorRes = await params.runEditorPrompt(prompt)
      report =
        editorRes.ok && editorRes.text
          ? parseAndValidateIdeaMinerOutput(editorRes.text, digest)
          : buildDeterministicFallbackReport(digest)
    } catch {
      report = buildDeterministicFallbackReport(digest)
    }
  }

  const durationSeconds = (Date.now() - startedAt) / 1000
  const message = formatIdeaMinerTelegramMessage({
    mode: params.mode,
    report,
    durationSeconds,
  })

  writeJsonAtomic(join(runDir, 'report.json'), report)
  writeAtomic0600(reportPath, `${message}\n`)

  return {
    ok: true,
    skipped: false,
    report,
    message,
    reportPath,
    durationSeconds,
  }
}
