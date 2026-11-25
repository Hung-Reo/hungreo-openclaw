#!/usr/bin/env node
// CLAUDE-BOT-CAPS-20261112 — PreToolUse owner-gate for the Telegram collab Claude session.
// Enforces Q2 (Hưng 12/11): only a delivery from Hưng (human, allowFrom; DM, or group without
// attached room-context) unlocks write / network / VPS tools. Everything else stays read/reply.
// Contract (Claude Code hooks): JSON on stdin; exit 0 = no opinion (normal permission flow),
// exit 2 = block, stderr is shown to Claude. Fail-closed on any error for elevated tools.
import { readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { resolve, sep } from 'node:path'

const HOME = homedir()
const DEFAULT_TTL_MIN = 120

// Never elevated: read-only, reply-only, or planning tools.
const SAFE_TOOLS = new Set([
  'Read', 'Glob', 'Grep', 'LS', 'NotebookRead', 'TodoWrite', 'TodoRead', 'ExitPlanMode',
  'Task', 'Agent', 'ToolSearch', 'ListMcpResourcesTool', 'ReadMcpResourceTool',
  'mcp__plugin_telegram_telegram__reply',
  'mcp__plugin_telegram_telegram__react',
  'mcp__plugin_telegram_telegram__edit_message',
  'mcp__plugin_telegram_telegram__download_attachment',
])
const WRITE_TOOLS = new Set(['Write', 'Edit', 'MultiEdit', 'NotebookEdit'])
// Bot self-learning areas stay writable for any trigger (COLLAB_PROTOCOL "Tự học").
const FREE_WRITE_DIRS = [`${HOME}/collab-bot/memory`, `${HOME}/collab-bot/.claude/skills`]
// Tiny read-only Bash allowlist usable without owner trust. No shell metacharacters allowed.
const SAFE_BASH = /^(ls|pwd|wc|head|tail|cat|rg|grep|git (log|status|diff|show|branch|rev-parse))(\s|$)/
const SHELL_META = /[;&|`$()<>\\\n\r]/

export function expandPath(p) {
  if (typeof p !== 'string' || !p) return null
  const e = p === '~' ? HOME : p.startsWith('~/') ? HOME + p.slice(1) : p
  return resolve(e)
}

export function isUnder(p, dir) {
  return p === dir || p.startsWith(dir + sep)
}

// Returns true if this call needs owner trust.
export function needsOwner(toolName, toolInput) {
  if (SAFE_TOOLS.has(toolName)) return false
  if (WRITE_TOOLS.has(toolName)) {
    const p = expandPath(toolInput?.file_path ?? toolInput?.notebook_path)
    if (p && !p.includes('..') && FREE_WRITE_DIRS.some(d => isUnder(p, d))) return false
    return true
  }
  if (toolName === 'Bash') {
    const cmd = String(toolInput?.command ?? '').trim()
    if (cmd && !SHELL_META.test(cmd) && SAFE_BASH.test(cmd)) return false
    return true
  }
  return true // WebFetch, WebSearch, unknown MCP tools, anything new: fail-closed
}

export function ownerTrusted(state, now, ttlMin = DEFAULT_TTL_MIN) {
  if (!state || state.v !== 1) return { ok: false, why: 'trust marker missing/invalid' }
  const o = state.last_owner_ts
  const u = state.last_untrusted_ts
  if (typeof o !== 'number') return { ok: false, why: 'no owner message yet' }
  if (typeof u === 'number' && u >= o) return { ok: false, why: `latest trigger is not owner (${state.last_reason})` }
  if (now - o > ttlMin * 60_000) return { ok: false, why: `owner trust expired (> ${ttlMin} min)` }
  return { ok: true, why: state.last_reason }
}

export function decide(input, state, now, ttlMin) {
  const tool = input?.tool_name
  if (typeof tool !== 'string') return { block: true, why: 'malformed hook input' }
  if (!needsOwner(tool, input.tool_input)) return { block: false, why: 'safe tool' }
  const t = ownerTrusted(state, now, ttlMin)
  return t.ok ? { block: false, why: `owner: ${t.why}` } : { block: true, why: t.why }
}

function arg(name) {
  const i = process.argv.indexOf(name)
  return i > 0 ? process.argv[i + 1] : undefined
}

function main() {
  let input = null
  let state = null
  try { input = JSON.parse(readFileSync(0, 'utf8')) } catch {}
  const trustFile = arg('--trust-file')
  try { if (trustFile) state = JSON.parse(readFileSync(trustFile, 'utf8')) } catch {}
  const ttl = Number(arg('--ttl-min') ?? DEFAULT_TTL_MIN)
  const d = decide(input, state, Date.now(), Number.isFinite(ttl) && ttl > 0 ? ttl : DEFAULT_TTL_MIN)
  if (d.block) {
    process.stderr.write(
      `owner-gate: chặn ${input?.tool_name ?? '?'} — ${d.why}. ` +
      `Quyền ghi/mạng/VPS chỉ mở khi Hưng nhắn trực tiếp (DM, hoặc group không kèm room-context). ` +
      `Hãy trả lời bằng reply và xin Hưng nhắn lại; không tìm đường vòng.\n`,
    )
    process.exit(2)
  }
  process.exit(0)
}

if (import.meta.url === `file://${process.argv[1]}`) main()
