import { mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { basename, join, posix } from 'node:path'
import type { AgyStreamResult, ToolStepRecord } from './stream-logger.ts'

export type ModelPresetKey = 'hydrogen' | 'orchestrator' | 'argon' | 'flash'

export type ModelPreset = {
  key: ModelPresetKey
  id: string
  label: string
  shortLabel: string
}

export const MODEL_PRESETS: Record<ModelPresetKey, ModelPreset> = {
  hydrogen: {
    key: 'hydrogen',
    id: 'gemini-4-hydrogen-high',
    label: 'Gemini 4 Hydrogen (High)',
    shortLabel: 'Hydrogen High',
  },
  orchestrator: {
    key: 'orchestrator',
    id: 'gemini-pro-orchestrator-g1-pro',
    label: 'Orchestrator (Argon)',
    shortLabel: 'Orchestrator (Argon)',
  },
  argon: {
    key: 'argon',
    id: 'gemini-4-argon-high',
    label: 'Gemini 4 Argon (High)',
    shortLabel: 'Argon High',
  },
  flash: {
    key: 'flash',
    id: 'gemini-3.8-flash-high',
    label: 'Gemini 3.8 Flash (High)',
    shortLabel: 'Flash 3.8 High',
  },
}

export function resolveModelPreset(raw: string): ModelPreset | undefined {
  const key = raw.trim().toLowerCase() as ModelPresetKey
  if (key in MODEL_PRESETS) {return MODEL_PRESETS[key]}
  return Object.values(MODEL_PRESETS).find(p => p.id.toLowerCase() === key)
}

export function findModelPresetById(modelId: string): ModelPreset | undefined {
  const normalized = modelId.trim().toLowerCase()
  return Object.values(MODEL_PRESETS).find(p => p.id.toLowerCase() === normalized)
}

const SUBCOMMAND_CLIS = new Set([
  'git',
  'gh',
  'npm',
  'pnpm',
  'bun',
  'docker',
  'kubectl',
  'cargo',
])

const DANGEROUS_SHELL_RE = /&&|\|\||[;|`<>]|[\r\n]|\$\(/
const EXPLICIT_RULE_RE = /(command|read_file|write_file)\(([^()]+)\)/
const PERMISSION_ERROR_RE =
  /permission\s+denied|action\s+blocked|blocked\s+by.*policy|requires?\s+(?:user\s+)?approval|headless\s+policy|ask\s+rule/i

export function formatHardDenyNotice(params: {
  reason: string
  toolName?: string
  rawInput?: string
}): string {
  const lines = [`🔒 Thao tác bị từ chối cứng: ${params.reason}.`]
  if (params.toolName && params.toolName !== 'unknown') {
    lines.push(`• Công cụ: \`${params.toolName.replace(/`/g, "'")}\``)
  }
  const detail = params.rawInput?.replace(/\s+/g, ' ').trim()
  if (detail) {
    const safeDetail = (detail.length > 180 ? `${detail.slice(0, 179)}…` : detail).replace(/`/g, "'")
    lines.push(`• Lệnh/mục tiêu: \`${safeDetail}\``)
  }
  return lines.join('\n')
}

export function hasPermissionDenial(res: AgyStreamResult): boolean {
  if (res.deniedActions && res.deniedActions.length > 0) {return true}
  return Boolean(
    res.toolSteps?.some(
      step => step.state === 'ERROR' && typeof step.errorMessage === 'string' && PERMISSION_ERROR_RE.test(step.errorMessage),
    ),
  )
}

function tokenizeCommandLine(commandLine: string): string[] {
  const tokens: string[] = []
  let current = ''
  let quote: '"' | "'" | null = null
  for (let i = 0; i < commandLine.length; i++) {
    const ch = commandLine[i]
    if (quote) {
      if (ch === quote) {
        quote = null
      } else {
        current += ch
      }
      continue
    }
    if (ch === '"' || ch === "'") {
      quote = ch
      continue
    }
    if (/\s/.test(ch)) {
      if (current) {
        tokens.push(current)
        current = ''
      }
      continue
    }
    current += ch
  }
  if (current) {tokens.push(current)}
  return tokens
}

function parseRule(rule: string): { kind: 'command' | 'read_file' | 'write_file'; target: string } | undefined {
  const m = /^(command|read_file|write_file)\((.+)\)$/.exec(rule.trim())
  if (!m) {return undefined}
  return {
    kind: m[1] as 'command' | 'read_file' | 'write_file',
    target: m[2].trim(),
  }
}

export function normalizeRulePath(rawPath: string, home = homedir()): string {
  let p = rawPath.trim()
  if (p === '~') {
    p = home
  } else if (p.startsWith('~/')) {
    p = `${home}/${p.slice(2)}`
  }
  p = posix.normalize(p)
  if (p === '/private/tmp') {
    p = '/tmp'
  } else if (p.startsWith('/private/tmp/')) {
    p = `/tmp/${p.slice('/private/tmp/'.length)}`
  }
  if (p.length > 1 && p.endsWith('/')) {
    p = p.slice(0, -1)
  }
  return p
}

export type PermissionCandidate = {
  rule: string
  toolName: string
  description: string
  inputPreview: string
  rawInput?: string
}

export type DerivePermissionResult =
  | { ok: true; candidate: PermissionCandidate }
  | { ok: false; blockedReason: string; toolName: string; description: string; inputPreview: string; rawInput?: string }

function pickBlockedStep(toolSteps: ToolStepRecord[] | undefined): ToolStepRecord | undefined {
  if (!toolSteps || toolSteps.length === 0) {return undefined}
  for (let i = toolSteps.length - 1; i >= 0; i--) {
    if (toolSteps[i].state === 'ERROR') {return toolSteps[i]}
  }
  return toolSteps[toolSteps.length - 1]
}

function extractPathParam(params: Record<string, unknown> | undefined): string {
  if (!params) {return ''}
  const raw = params.Path ?? params.TargetFile ?? params.AbsolutePath ?? params.path
  return typeof raw === 'string' ? raw.trim() : ''
}

export function derivePermissionCandidate(res: AgyStreamResult): DerivePermissionResult {
  const step = pickBlockedStep(res.toolSteps)
  const toolName =
    step?.toolName ??
    res.deniedActions?.[0]?.displayName ??
    res.deniedActions?.[0]?.action ??
    'unknown'
  const params = step?.parameters
  const cmdLine = typeof params?.CommandLine === 'string' ? params.CommandLine.trim() : ''
  const filePath = extractPathParam(params)
  const rawInput = cmdLine || filePath || undefined
  const inputPreview = params ? JSON.stringify(params) : (res.deniedActions?.map(d => d.displayName ?? d.action).join(', ') ?? '')
  const description =
    step?.errorMessage?.trim() ||
    res.deniedActions?.map(d => d.displayName ?? d.action ?? 'unknown').join(', ') ||
    'Headless policy blocked action'

  if (cmdLine && DANGEROUS_SHELL_RE.test(cmdLine)) {
    return {
      ok: false,
      blockedReason: 'shell_chain_not_allowed',
      toolName,
      description,
      inputPreview,
      rawInput,
    }
  }

  // Prefer explicit rule if present in errorMessage or deniedActions[].action
  const explicitSources = [
    step?.errorMessage ?? '',
    ...(res.deniedActions ?? []).map(d => d.action ?? ''),
  ]
  for (const src of explicitSources) {
    const match = EXPLICIT_RULE_RE.exec(src)
    if (match) {
      const rule = `${match[1]}(${match[2].trim()})`
      if (match[1] === 'command' && DANGEROUS_SHELL_RE.test(match[2])) {
        return {
          ok: false,
          blockedReason: 'shell_chain_not_allowed',
          toolName,
          description,
          inputPreview,
          rawInput,
        }
      }
      return {
        ok: true,
        candidate: {
          rule,
          toolName,
          description,
          inputPreview,
          rawInput,
        },
      }
    }
  }

  if (cmdLine) {
    const tokens = tokenizeCommandLine(cmdLine).filter(t => !/^[A-Za-z_][A-Za-z0-9_]*=/.test(t))
    if (tokens.length === 0) {
      return {
        ok: false,
        blockedReason: 'empty_command',
        toolName,
        description,
        inputPreview,
        rawInput,
      }
    }
    const bin = tokens[0]
    const binBase = basename(bin)
    const second = tokens[1]
    const ruleTarget =
      SUBCOMMAND_CLIS.has(binBase) && second && !second.startsWith('-')
        ? `${bin} ${second}`
        : bin
    return {
      ok: true,
      candidate: {
        rule: `command(${ruleTarget})`,
        toolName,
        description,
        inputPreview,
        rawInput: cmdLine,
      },
    }
  }

  if (filePath) {
    const isWrite = toolName.includes('write') || toolName.includes('edit')
    const kind = isWrite ? 'write_file' : 'read_file'
    return {
      ok: true,
      candidate: {
        rule: `${kind}(${filePath})`,
        toolName,
        description,
        inputPreview,
        rawInput: filePath,
      },
    }
  }

  return {
    ok: false,
    blockedReason: 'cannot_derive_rule',
    toolName,
    description,
    inputPreview,
    rawInput,
  }
}

export type SettingsPermissionsFile = {
  permissions?: {
    allow?: string[]
    ask?: string[]
    deny?: string[]
  }
  [key: string]: unknown
}

export function isRuleBlockedByDeny(
  settingsPath: string,
  rule: string,
  rawInput?: string,
  home = homedir(),
): { blocked: boolean; matchedDeny?: string } {
  const parsedRule = parseRule(rule)
  if (!parsedRule) {return { blocked: true, matchedDeny: 'invalid_rule_syntax' }}

  if (parsedRule.kind === 'command') {
    if (DANGEROUS_SHELL_RE.test(parsedRule.target) || (rawInput && DANGEROUS_SHELL_RE.test(rawInput))) {
      return { blocked: true, matchedDeny: 'shell_chain_not_allowed' }
    }
  }

  if (!settingsPath) {return { blocked: true, matchedDeny: 'settings_unreadable' }}

  let settings: SettingsPermissionsFile
  try {
    settings = JSON.parse(readFileSync(settingsPath, 'utf8')) as SettingsPermissionsFile
  } catch {
    return { blocked: true, matchedDeny: 'settings_unreadable' }
  }

  const denyList = settings.permissions?.deny
  if (!Array.isArray(denyList)) {
    return { blocked: true, matchedDeny: 'settings_missing_deny' }
  }

  for (const denyEntry of denyList) {
    if (typeof denyEntry !== 'string') {continue}
    const parsedDeny = parseRule(denyEntry)
    if (!parsedDeny) {continue}

    if (parsedRule.kind === 'command' && parsedDeny.kind === 'command') {
      const cmd = parsedRule.target
      const cmdBase = basename(cmd.split(/\s+/)[0] ?? '') + (cmd.includes(' ') ? ` ${cmd.split(/\s+/).slice(1).join(' ')}` : '')
      const d = parsedDeny.target
      const candidates = [cmd, cmdBase]
      if (rawInput) {candidates.push(rawInput.trim())}
      for (const c of candidates) {
        if (c === d || c.startsWith(`${d} `) || d.startsWith(`${c} `)) {
          return { blocked: true, matchedDeny: denyEntry }
        }
      }
      continue
    }

    if (
      (parsedRule.kind === 'read_file' || parsedRule.kind === 'write_file') &&
      parsedDeny.kind === parsedRule.kind
    ) {
      const p = normalizeRulePath(parsedRule.target, home)
      const d = normalizeRulePath(parsedDeny.target, home)
      if (p === d || p.startsWith(`${d}/`) || d.startsWith(`${p}/`)) {
        return { blocked: true, matchedDeny: denyEntry }
      }
    }
  }

  return { blocked: false }
}

function prepareSettingsWithRule(params: {
  settingsPath: string
  rule: string
  rawInput?: string
  home?: string
}): { ok: true; settings: SettingsPermissionsFile; added: boolean } | { ok: false; reason: string } {
  const { settingsPath, rule, rawInput, home = homedir() } = params
  const denyCheck = isRuleBlockedByDeny(settingsPath, rule, rawInput, home)
  if (denyCheck.blocked) {
    return { ok: false, reason: `blocked_by_deny:${denyCheck.matchedDeny ?? 'unknown'}` }
  }

  let settings: SettingsPermissionsFile
  try {
    settings = JSON.parse(readFileSync(settingsPath, 'utf8')) as SettingsPermissionsFile
  } catch {
    return { ok: false, reason: 'settings_unreadable' }
  }

  const perms = settings.permissions && typeof settings.permissions === 'object' ? { ...settings.permissions } : {}
  const allow = Array.isArray(perms.allow) ? [...perms.allow] : []
  let added = false
  if (!allow.includes(rule)) {
    allow.push(rule)
    added = true
  }
  perms.allow = allow

  if (Array.isArray(perms.ask)) {
    perms.ask = perms.ask.filter(item => item !== rule)
  }

  return {
    ok: true,
    settings: { ...settings, permissions: perms },
    added,
  }
}

/**
 * Permanently grants a single rule in `settingsPath` (for explicit "Always allow").
 */
export function grantPermissionRuleInFile(
  settingsPath: string,
  rule: string,
  rawInput?: string,
  home = homedir(),
): { ok: true; added: boolean } | { ok: false; reason: string } {
  const prepared = prepareSettingsWithRule({ settingsPath, rule, rawInput, home })
  if (!prepared.ok) {return prepared}

  const tmpPath = `${settingsPath}.tmp`
  writeFileSync(tmpPath, JSON.stringify(prepared.settings, null, 2) + '\n', 'utf8')
  renameSync(tmpPath, settingsPath)
  return { ok: true, added: prepared.added }
}

/**
 * Creates a temporary 0600 settings copy granting `rule` for a single retry turn without mutating `settingsPath`.
 */
export function createEphemeralSettingsWithRule(params: {
  settingsPath: string
  tempDir: string
  requestId: string
  rule: string
  rawInput?: string
  home?: string
}): { ok: true; tempSettingsPath: string; cleanup: () => void } | { ok: false; reason: string } {
  const prepared = prepareSettingsWithRule(params)
  if (!prepared.ok) {return prepared}

  mkdirSync(params.tempDir, { recursive: true, mode: 0o700 })
  const safeId = params.requestId.replace(/[^a-zA-Z0-9_-]/g, '') || 'req'
  const tempSettingsPath = join(params.tempDir, `perm-once-${safeId}-${Date.now()}.json`)
  writeFileSync(tempSettingsPath, JSON.stringify(prepared.settings, null, 2) + '\n', { mode: 0o600 })

  const cleanup = (): void => {
    try {
      rmSync(tempSettingsPath, { force: true })
    } catch {}
  }

  return { ok: true, tempSettingsPath, cleanup }
}

export type PendingPermissionEntry = {
  requestId: string
  rule: string
  toolName: string
  description: string
  inputPreview: string
  rawInput?: string
  chatId: string
  messageId: number
  senderLabel: string
  isBotSender: boolean
  userText: string
  createdAt: number
}

const REQUEST_ID_ALPHABET = 'abcdefghjkmnpqrstuvwxyz'
export const PERMISSION_TTL_MS = 15 * 60 * 1000

export class PendingPermissionStore {
  private entries = new Map<string, PendingPermissionEntry>()

  constructor(private readonly ttlMs = PERMISSION_TTL_MS) {}

  private sweep(now = Date.now()): void {
    for (const [id, entry] of this.entries) {
      if (now - entry.createdAt > this.ttlMs) {
        this.entries.delete(id)
      }
    }
  }

  private generateId(): string {
    for (let attempt = 0; attempt < 20; attempt++) {
      let id = ''
      for (let i = 0; i < 5; i++) {
        id += REQUEST_ID_ALPHABET[Math.floor(Math.random() * REQUEST_ID_ALPHABET.length)]
      }
      if (!this.entries.has(id)) {return id}
    }
    throw new Error('Failed to generate unique permission requestId')
  }

  create(input: Omit<PendingPermissionEntry, 'requestId' | 'createdAt'>, now = Date.now()): PendingPermissionEntry {
    this.sweep(now)
    const requestId = this.generateId()
    const entry: PendingPermissionEntry = {
      ...input,
      requestId,
      createdAt: now,
    }
    this.entries.set(requestId, entry)
    return entry
  }

  get(requestId: string, now = Date.now()): PendingPermissionEntry | undefined {
    this.sweep(now)
    return this.entries.get(requestId)
  }

  delete(requestId: string): boolean {
    return this.entries.delete(requestId)
  }
}
