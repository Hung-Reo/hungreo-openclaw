import { describe, expect, it } from 'bun:test'
import { AgyStreamParser, summarizeToolParams } from './stream-logger.ts'

describe('AgyStreamParser', () => {
  it('parses chunked stream-json events and fires timeline callbacks', () => {
    const events: string[] = []
    const parser = new AgyStreamParser({
      onInit: info => events.push(`init:${info.model}:${info.permissionMode}`),
      onToolStart: (name, detail) => events.push(`start:${name}:${detail}`),
      onToolDone: (name, dur) => events.push(`done:${name}:${dur}`),
      onToolError: (name, msg, dur) => events.push(`error:${name}:${dur}:${msg}`),
      onResult: res => events.push(`result:${res.status}:${res.durationSeconds}`),
    })

    const ndjson =
      [
        JSON.stringify({
          event: 'init',
          conversation_id: 'c1',
          init: { model: 'Gemini 4', permission_mode: 'accept-edits' },
        }),
        JSON.stringify({
          event: 'step_update',
          step_update: {
            conversation_id: 'c1',
            step_index: 1,
            state: 'ACTIVE',
            step_type: 'tool',
            tool_name: 'read_file',
            tool_info: { parameters: { Path: '/tmp/gemini-telegram-inbox/photo-1.jpg' } },
          },
        }),
        JSON.stringify({
          event: 'step_update',
          step_update: {
            conversation_id: 'c1',
            step_index: 1,
            state: 'DONE',
            step_type: 'tool',
            tool_name: 'read_file',
            duration_seconds: 0.42,
          },
        }),
        JSON.stringify({
          event: 'result',
          result: {
            conversation_id: 'c1',
            status: 'SUCCESS',
            response: 'Đã đọc xong ảnh!',
            duration_seconds: 5.5,
            num_turns: 1,
            usage: { total_tokens: 1200 },
          },
        }),
      ].join('\n') + '\n'

    // Feed in awkward partial chunks
    parser.feed(ndjson.slice(0, 50))
    parser.feed(ndjson.slice(50, 220))
    parser.feed(ndjson.slice(220))
    const final = parser.finish()

    expect(final).toEqual({
      conversationId: 'c1',
      response: 'Đã đọc xong ảnh!',
      status: 'SUCCESS',
      error: undefined,
      durationSeconds: 5.5,
      numTurns: 1,
      totalTokens: 1200,
      toolSteps: [
        {
          toolName: 'read_file',
          parameters: { Path: '/tmp/gemini-telegram-inbox/photo-1.jpg' },
          state: 'DONE',
        },
      ],
    })
    expect(events).toEqual([
      'init:Gemini 4:accept-edits',
      'start:read_file:/tmp/gemini-telegram-inbox/photo-1.jpg',
      'done:read_file:0.42',
      'result:SUCCESS:5.5',
    ])
  })

  it('summarizes command and path parameters cleanly', () => {
    expect(summarizeToolParams('run_command', { CommandLine: 'bun test ./foo.ts' })).toBe('bun test ./foo.ts')
    expect(summarizeToolParams('read_file', { Path: '/tmp/a.ogg' })).toBe('/tmp/a.ogg')
  })

  it('captures tool ERROR steps and denied_actions on headless refusal', () => {
    const errors: string[] = []
    const parser = new AgyStreamParser({
      onToolError: (name, msg, dur) => errors.push(`${name}:${dur}:${msg}`),
    })
    parser.feed(
      [
        JSON.stringify({
          event: 'step_update',
          step_update: {
            conversation_id: 'c2',
            state: 'ERROR',
            step_type: 'tool',
            tool_name: 'run_command',
            duration_seconds: 0.05,
            tool_info: { error: { message: 'Permission denied for command(git push)' } },
          },
        }),
        JSON.stringify({
          event: 'result',
          result: {
            conversation_id: 'c2',
            status: 'SUCCESS',
            response: '',
            denied_actions: [{ action: 'command', display_name: 'Bash' }],
          },
        }),
      ].join('\n') + '\n',
    )
    const res = parser.finish()
    expect(errors).toEqual(['run_command:0.05:Permission denied for command(git push)'])
    expect(res.deniedActions).toEqual([{ action: 'command', displayName: 'Bash' }])
    expect(res.toolSteps).toEqual([
      {
        toolName: 'run_command',
        state: 'ERROR',
        errorMessage: 'Permission denied for command(git push)',
      },
    ])
  })

  it('extracts per-step contextTokens (input + cache_read + output) separately from cumulative result.usage.total_tokens', () => {
    const parser = new AgyStreamParser()
    parser.feed(
      [
        // Early step in multi-step turn
        JSON.stringify({
          event: 'step_update',
          step_update: {
            conversation_id: 'c-ctx',
            step_type: 'agent_response',
            state: 'DONE',
            usage: {
              input_tokens: 15_000,
              output_tokens: 120,
              cache_read_tokens: 0,
              total_tokens: 15_120,
            },
          },
        }),
        // In-progress step should NOT overwrite completed step
        JSON.stringify({
          event: 'step_update',
          step_update: {
            conversation_id: 'c-ctx',
            step_type: 'agent_response',
            state: 'PROCESSING',
            usage: { input_tokens: 99, output_tokens: 1, cache_read_tokens: 0, total_tokens: 100 },
          },
        }),
        // Latest DONE agent_response step represents true context window occupancy
        JSON.stringify({
          event: 'step_update',
          step_update: {
            conversation_id: 'c-ctx',
            step_type: 'agent_response',
            state: 'DONE',
            usage: {
              input_tokens: 3_790,
              output_tokens: 248,
              cache_read_tokens: 15_519,
              total_tokens: 4_038,
            },
          },
        }),
        // result.usage reflects conversation-cumulative non-cached input + output
        JSON.stringify({
          event: 'result',
          result: {
            conversation_id: 'c-ctx',
            status: 'SUCCESS',
            response: 'OK',
            usage: {
              input_tokens: 26_711,
              output_tokens: 368,
              cache_read_tokens: 0,
              total_tokens: 27_079,
            },
          },
        }),
      ].join('\n') + '\n',
    )

    const res = parser.finish()
    expect(res.contextTokens).toBe(3_790 + 15_519 + 248) // 19,557 real context window tokens
    expect(res.totalTokens).toBe(27_079) // cumulative reported by agy
    expect(res.usage).toEqual({
      inputTokens: 26_711,
      outputTokens: 368,
      cacheReadTokens: 0,
      totalTokens: 27_079,
    })
  })
})
