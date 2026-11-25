/**
 * NDJSON stream-json parser and live terminal timeline formatter for Antigravity CLI (`agy`).
 */

export type DeniedAction = {
  action?: string
  displayName?: string
}

export type ToolStepRecord = {
  toolName: string
  parameters?: Record<string, unknown>
  state: 'ACTIVE' | 'DONE' | 'ERROR'
  errorMessage?: string
}

export type AgyTokenUsage = {
  inputTokens?: number
  outputTokens?: number
  thinkingTokens?: number
  cacheReadTokens?: number
  totalTokens?: number
}

export type AgyStreamResult = {
  conversationId: string
  response: string
  status: string
  error?: string
  durationSeconds?: number
  numTurns?: number
  /** Current occupied context size (input + cache_read + output of latest LLM step). */
  contextTokens?: number
  /** Cumulative `(input_tokens + output_tokens)` reported by `agy` in `result.usage`. */
  totalTokens?: number
  usage?: AgyTokenUsage
  deniedActions?: DeniedAction[]
  toolSteps?: ToolStepRecord[]
}

export type StreamTimelineCallbacks = {
  onInit?: (info: { model?: string; permissionMode?: string }) => void
  onToolStart?: (toolName: string, detail: string) => void
  onToolDone?: (toolName: string, durationSeconds?: number) => void
  onToolError?: (toolName: string, message: string, durationSeconds?: number) => void
  onResult?: (res: AgyStreamResult) => void
}

export function formatClock(date = new Date()): string {
  return date.toTimeString().slice(0, 8)
}

export function truncateSingleLine(text: string, max = 90): string {
  const clean = text.replace(/\s+/g, ' ').trim()
  if (clean.length <= max) {
    return clean
  }
  return `${clean.slice(0, max - 1)}…`
}

export function summarizeToolParams(toolName: string, params: Record<string, unknown> | undefined): string {
  if (!params) {
    return ''
  }
  const candidate =
    params.CommandLine ??
    params.Path ??
    params.TargetFile ??
    params.AbsolutePath ??
    params.Url ??
    params.query ??
    params.Prompt ??
    params.Role
  if (typeof candidate === 'string' && candidate.trim()) {
    return truncateSingleLine(candidate, 80)
  }
  const keys = Object.keys(params)
  return keys.length > 0 ? truncateSingleLine(keys.join(', '), 60) : ''
}

function parseTokenUsage(raw: unknown): AgyTokenUsage | undefined {
  if (!raw || typeof raw !== 'object') {
    return undefined
  }
  const u = raw as Record<string, unknown>
  const out: AgyTokenUsage = {}
  if (typeof u.input_tokens === 'number' && Number.isFinite(u.input_tokens)) {
    out.inputTokens = u.input_tokens
  }
  if (typeof u.output_tokens === 'number' && Number.isFinite(u.output_tokens)) {
    out.outputTokens = u.output_tokens
  }
  if (typeof u.thinking_tokens === 'number' && Number.isFinite(u.thinking_tokens)) {
    out.thinkingTokens = u.thinking_tokens
  }
  if (typeof u.cache_read_tokens === 'number' && Number.isFinite(u.cache_read_tokens)) {
    out.cacheReadTokens = u.cache_read_tokens
  }
  if (typeof u.total_tokens === 'number' && Number.isFinite(u.total_tokens)) {
    out.totalTokens = u.total_tokens
  }
  return Object.keys(out).length > 0 ? out : undefined
}

function computeStepContextTokens(usage: AgyTokenUsage | undefined): number | undefined {
  if (!usage) {
    return undefined
  }
  const cacheRead = usage.cacheReadTokens ?? 0
  if (typeof usage.inputTokens === 'number') {
    return usage.inputTokens + cacheRead + (usage.outputTokens ?? 0)
  }
  if (typeof usage.totalTokens === 'number') {
    return usage.totalTokens + cacheRead
  }
  return undefined
}

/**
 * Incrementally parses NDJSON lines emitted by `agy --output-format stream-json`.
 */
export class AgyStreamParser {
  private buffer = ''
  private toolSteps: ToolStepRecord[] = []
  private lastStepContextTokens?: number
  private result: AgyStreamResult = {
    conversationId: '',
    response: '',
    status: '',
  }

  constructor(private readonly callbacks: StreamTimelineCallbacks = {}) {}

  feed(chunk: string): void {
    this.buffer += chunk
    let idx = this.buffer.indexOf('\n')
    while (idx !== -1) {
      const line = this.buffer.slice(0, idx).trim()
      this.buffer = this.buffer.slice(idx + 1)
      if (line) {
        this.handleLine(line)
      }
      idx = this.buffer.indexOf('\n')
    }
  }

  finish(): AgyStreamResult {
    const tail = this.buffer.trim()
    this.buffer = ''
    if (tail) {
      this.handleLine(tail)
    }
    if (this.toolSteps.length > 0) {
      this.result.toolSteps = [...this.toolSteps]
    }
    if (typeof this.lastStepContextTokens === 'number' && this.result.contextTokens === undefined) {
      this.result.contextTokens = this.lastStepContextTokens
    }
    return this.result
  }

  private upsertToolStep(
    toolName: string,
    state: 'ACTIVE' | 'DONE' | 'ERROR',
    parameters?: Record<string, unknown>,
    errorMessage?: string,
  ): void {
    if (state === 'ACTIVE') {
      this.toolSteps.push({
        toolName,
        ...(parameters ? { parameters } : {}),
        state,
      })
      return
    }
    for (let i = this.toolSteps.length - 1; i >= 0; i--) {
      const rec = this.toolSteps[i]
      if (rec.toolName === toolName && rec.state === 'ACTIVE') {
        rec.state = state
        if (parameters && !rec.parameters) {
          rec.parameters = parameters
        }
        if (errorMessage) {
          rec.errorMessage = errorMessage
        }
        return
      }
    }
    this.toolSteps.push({
      toolName,
      ...(parameters ? { parameters } : {}),
      state,
      ...(errorMessage ? { errorMessage } : {}),
    })
  }

  private handleLine(line: string): void {
    if (!line.startsWith('{') || !line.endsWith('}')) {
      return
    }
    let obj: Record<string, unknown>
    try {
      obj = JSON.parse(line) as Record<string, unknown>
    } catch {
      return
    }

    if (typeof obj.conversation_id === 'string' && obj.conversation_id) {
      this.result.conversationId = obj.conversation_id
    }

    const event = obj.event
    if (event === 'init' && obj.init && typeof obj.init === 'object') {
      const init = obj.init as Record<string, unknown>
      this.callbacks.onInit?.({
        model: typeof init.model === 'string' ? init.model : undefined,
        permissionMode: typeof init.permission_mode === 'string' ? init.permission_mode : undefined,
      })
      return
    }

    if (event === 'step_update' && obj.step_update && typeof obj.step_update === 'object') {
      const su = obj.step_update as Record<string, unknown>
      if (typeof su.conversation_id === 'string' && su.conversation_id) {
        this.result.conversationId = su.conversation_id
      }
      if (su.step_type === 'agent_response' && su.state === 'DONE') {
        const stepUsage = parseTokenUsage(su.usage)
        const ctxTokens = computeStepContextTokens(stepUsage)
        if (typeof ctxTokens === 'number') {
          this.lastStepContextTokens = ctxTokens
        }
        return
      }
      if (su.step_type === 'tool') {
        const toolName = typeof su.tool_name === 'string' ? su.tool_name : 'tool'
        const toolInfo =
          su.tool_info && typeof su.tool_info === 'object' ? (su.tool_info as Record<string, unknown>) : undefined
        const params =
          toolInfo?.parameters && typeof toolInfo.parameters === 'object'
            ? (toolInfo.parameters as Record<string, unknown>)
            : undefined
        if (su.state === 'ACTIVE') {
          this.upsertToolStep(toolName, 'ACTIVE', params)
          this.callbacks.onToolStart?.(toolName, summarizeToolParams(toolName, params))
        } else if (su.state === 'DONE') {
          const dur = typeof su.duration_seconds === 'number' ? su.duration_seconds : undefined
          this.upsertToolStep(toolName, 'DONE', params)
          this.callbacks.onToolDone?.(toolName, dur)
        } else if (su.state === 'ERROR') {
          const dur = typeof su.duration_seconds === 'number' ? su.duration_seconds : undefined
          const errObj =
            toolInfo?.error && typeof toolInfo.error === 'object'
              ? (toolInfo.error as Record<string, unknown>)
              : undefined
          const errMsg = typeof errObj?.message === 'string' ? errObj.message : 'tool_error'
          this.upsertToolStep(toolName, 'ERROR', params, errMsg)
          this.callbacks.onToolError?.(toolName, truncateSingleLine(errMsg, 120), dur)
        }
      }
      return
    }

    if (event === 'result' && obj.result && typeof obj.result === 'object') {
      const r = obj.result as Record<string, unknown>
      const usage = parseTokenUsage(r.usage)
      const hasDetailedUsage = Boolean(
        usage &&
        (typeof usage.inputTokens === 'number' ||
          typeof usage.outputTokens === 'number' ||
          typeof usage.cacheReadTokens === 'number'),
      )
      const deniedActions = Array.isArray(r.denied_actions)
        ? r.denied_actions
            .filter((item): item is Record<string, unknown> => Boolean(item && typeof item === 'object'))
            .map(item => ({
              action: typeof item.action === 'string' ? item.action : undefined,
              displayName: typeof item.display_name === 'string' ? item.display_name : undefined,
            }))
        : undefined
      this.result = {
        conversationId:
          typeof r.conversation_id === 'string' && r.conversation_id ? r.conversation_id : this.result.conversationId,
        response: typeof r.response === 'string' ? r.response.trim() : '',
        status: typeof r.status === 'string' ? r.status : '',
        error: typeof r.error === 'string' ? r.error : undefined,
        durationSeconds: typeof r.duration_seconds === 'number' ? r.duration_seconds : undefined,
        numTurns: typeof r.num_turns === 'number' ? r.num_turns : undefined,
        ...(typeof this.lastStepContextTokens === 'number' ? { contextTokens: this.lastStepContextTokens } : {}),
        totalTokens: usage?.totalTokens,
        ...(hasDetailedUsage && usage ? { usage } : {}),
        ...(deniedActions && deniedActions.length > 0 ? { deniedActions } : {}),
        ...(this.toolSteps.length > 0 ? { toolSteps: [...this.toolSteps] } : {}),
      }
      this.callbacks.onResult?.(this.result)
      return
    }

    // Fallback compatibility with --output-format json
    if (typeof obj.response === 'string' && obj.response.trim()) {
      this.result.response = obj.response.trim()
    }
  }
}
