import { afterEach, describe, expect, it } from 'bun:test'
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import {
  MODEL_PRESETS,
  PendingPermissionStore,
  canAlwaysAllowRule,
  createEphemeralSettingsWithRule,
  derivePermissionCandidate,
  formatHardDenyNotice,
  formatPermissionDmMessage,
  grantPermissionRuleInFile,
  hasPermissionDenial,
  isRuleBlockedByDeny,
  resolveModelPreset,
  resolveTurnExecutionPolicy,
} from './permissions.ts'
import type { AgyStreamResult } from './stream-logger.ts'

const tempDirs: string[] = []

function makeTempSettings(
  overrides: {
    allow?: string[]
    ask?: string[]
    deny?: string[]
  } = {},
): string {
  const dir = mkdtempSync(join(tmpdir(), 'gemini-perm-test-'))
  tempDirs.push(dir)
  const settingsPath = join(dir, 'gemini-collab-settings.json')
  const data = {
    permissions: {
      allow: overrides.allow ?? ['read_file(/tmp/gemini-telegram-inbox)'],
      ask: overrides.ask ?? ['command(curl)', 'command(wget)'],
      deny: overrides.deny ?? [
        'read_file(/Users/hungdinh/.ssh)',
        'write_file(/Users/hungdinh/.ssh)',
        'write_file(/Users/hungdinh/Development/hungreo-openclaw/.env)',
        'write_file(/Users/hungdinh/Development/hungreo-openclaw/tools/openclaw-ops/mac-collab-hub-20261103/gemini-collab-settings.json)',
        'command(git push)',
        'command(rm)',
        'command(ssh)',
        'command(env)',
      ],
    },
  }
  writeFileSync(settingsPath, JSON.stringify(data, null, 2) + '\n', 'utf8')
  return settingsPath
}

afterEach(() => {
  while (tempDirs.length > 0) {
    const dir = tempDirs.pop()!
    rmSync(dir, { recursive: true, force: true })
  }
})

describe('derivePermissionCandidate', () => {
  it('derives command(<bin> <sub>) for subcommand CLIs and command(<bin>) for standalone commands', () => {
    const gitBranchRes: AgyStreamResult = {
      conversationId: 'c1',
      response: '',
      status: 'SUCCESS',
      deniedActions: [{ action: 'command', displayName: 'Bash' }],
      toolSteps: [
        {
          toolName: 'run_command',
          parameters: { CommandLine: 'git branch -a' },
          state: 'ERROR',
          errorMessage: 'Action blocked by headless policy',
        },
      ],
    }
    const r1 = derivePermissionCandidate(gitBranchRes)
    expect(r1.ok).toBe(true)
    if (r1.ok) {
      expect(r1.candidate.rule).toBe('command(git branch)')
    }

    const curlRes: AgyStreamResult = {
      conversationId: 'c2',
      response: '',
      status: 'SUCCESS',
      deniedActions: [{ action: 'command', displayName: 'Bash' }],
      toolSteps: [
        {
          toolName: 'run_command',
          parameters: { CommandLine: 'curl -I https://example.com' },
          state: 'ERROR',
        },
      ],
    }
    const r2 = derivePermissionCandidate(curlRes)
    expect(r2.ok).toBe(true)
    if (r2.ok) {
      expect(r2.candidate.rule).toBe('command(curl)')
    }
  })

  it('rejects shell chaining or subshell expressions', () => {
    const chainedRes: AgyStreamResult = {
      conversationId: 'c3',
      response: '',
      status: 'SUCCESS',
      deniedActions: [{ action: 'command', displayName: 'Bash' }],
      toolSteps: [
        {
          toolName: 'run_command',
          parameters: { CommandLine: 'git status && rm -rf /' },
          state: 'ERROR',
        },
      ],
    }
    const r = derivePermissionCandidate(chainedRes)
    expect(r.ok).toBe(false)
    if (!r.ok) {
      expect(r.blockedReason).toBe('shell_chain_not_allowed')
    }
  })
})

describe('isRuleBlockedByDeny', () => {
  it('hard-blocks deny-listed commands, paths, parent paths, and shell chains', () => {
    const settingsPath = makeTempSettings()

    expect(isRuleBlockedByDeny(settingsPath, 'command(git push)', 'git push origin main').blocked).toBe(true)
    expect(isRuleBlockedByDeny(settingsPath, 'command(git)', 'git').blocked).toBe(true)
    expect(isRuleBlockedByDeny(settingsPath, 'command(rm)', 'rm -rf /tmp/x').blocked).toBe(true)
    expect(isRuleBlockedByDeny(settingsPath, 'command(/bin/rm)', '/bin/rm /tmp/x').blocked).toBe(true)
    expect(isRuleBlockedByDeny(settingsPath, 'command(ssh)', 'ssh root@vps').blocked).toBe(true)
    expect(isRuleBlockedByDeny(settingsPath, 'read_file(/Users/hungdinh/.ssh/id_ed25519)').blocked).toBe(true)
    expect(isRuleBlockedByDeny(settingsPath, 'read_file(~/.ssh/config)', undefined, '/Users/hungdinh').blocked).toBe(
      true,
    )
    expect(
      isRuleBlockedByDeny(
        settingsPath,
        'write_file(/Users/hungdinh/Development/hungreo-openclaw/tools/openclaw-ops/mac-collab-hub-20261103/gemini-collab-settings.json)',
      ).blocked,
    ).toBe(true)
    expect(isRuleBlockedByDeny(settingsPath, 'command(git status && rm -rf /)').blocked).toBe(true)
    expect(isRuleBlockedByDeny('/nonexistent/settings.json', 'command(git branch)').blocked).toBe(true)
  })

  it('allows safe rules that do not conflict with deny list', () => {
    const settingsPath = makeTempSettings()
    expect(isRuleBlockedByDeny(settingsPath, 'command(git branch)', 'git branch -a').blocked).toBe(false)
    expect(isRuleBlockedByDeny(settingsPath, 'command(curl)', 'curl -I https://example.com').blocked).toBe(false)
  })
})

describe('grantPermissionRuleInFile', () => {
  it('appends rule to allow, removes matching ask entry, and preserves deny list', () => {
    const settingsPath = makeTempSettings()

    const res = grantPermissionRuleInFile(settingsPath, 'command(curl)', 'curl -I https://example.com')
    expect(res).toEqual({ ok: true, added: true })

    const updated = JSON.parse(readFileSync(settingsPath, 'utf8')) as {
      permissions: { allow: string[]; ask: string[]; deny: string[] }
    }
    expect(updated.permissions.allow).toContain('command(curl)')
    expect(updated.permissions.ask).not.toContain('command(curl)')
    expect(updated.permissions.ask).toContain('command(wget)')
    expect(updated.permissions.deny).toContain('command(git push)')

    // Idempotent second call
    const res2 = grantPermissionRuleInFile(settingsPath, 'command(curl)', 'curl -I https://example.com')
    expect(res2).toEqual({ ok: true, added: false })

    // Refuses deny-listed rule
    const denied = grantPermissionRuleInFile(settingsPath, 'command(git push)', 'git push origin main')
    expect(denied.ok).toBe(false)
  })
})

describe('createEphemeralSettingsWithRule', () => {
  it('creates 0600 temp settings with one-time rule, never mutates base settings, and cleans up', () => {
    const settingsPath = makeTempSettings()
    const baseBefore = readFileSync(settingsPath, 'utf8')
    const tempDir = join(mkdtempSync(join(tmpdir(), 'gemini-ephem-')), 'tmp-perms')
    tempDirs.push(tempDir)

    const ephem = createEphemeralSettingsWithRule({
      settingsPath,
      tempDir,
      requestId: 'abcde',
      rule: 'command(curl)',
      rawInput: 'curl -I https://example.com',
    })
    expect(ephem.ok).toBe(true)
    if (!ephem.ok) {
      return
    }

    // Base settings stays untouched
    expect(readFileSync(settingsPath, 'utf8')).toBe(baseBefore)
    expect(statSync(ephem.tempSettingsPath).mode & 0o777).toBe(0o600)

    const parsed = JSON.parse(readFileSync(ephem.tempSettingsPath, 'utf8')) as {
      permissions: { allow: string[]; ask: string[]; deny: string[] }
    }
    expect(parsed.permissions.allow).toContain('command(curl)')
    expect(parsed.permissions.ask).not.toContain('command(curl)')
    expect(parsed.permissions.deny).toContain('command(rm)')

    ephem.cleanup()
    expect(existsSync(ephem.tempSettingsPath)).toBe(false)

    // Blocks deny-listed rules
    const denied = createEphemeralSettingsWithRule({
      settingsPath,
      tempDir,
      requestId: 'bcdef',
      rule: 'command(rm)',
      rawInput: 'rm -rf /tmp/x',
    })
    expect(denied.ok).toBe(false)
  })
})

describe('resolveModelPreset & PendingPermissionStore', () => {
  it('resolves hydrogen, orchestrator, argon, and flash presets', () => {
    expect(resolveModelPreset('hydrogen')?.id).toBe(MODEL_PRESETS.hydrogen.id)
    expect(resolveModelPreset('orchestrator')?.id).toBe('gemini-pro-orchestrator-g1-pro')
    expect(resolveModelPreset('argon')?.id).toBe('gemini-4-argon-high')
    expect(resolveModelPreset('flash')?.id).toBe('gemini-3.8-flash-high')
    expect(resolveModelPreset('gemini-pro-orchestrator-g1-pro')?.key).toBe('orchestrator')
    expect(resolveModelPreset('unknown')).toBeUndefined()
  })

  it('creates, retrieves, deletes, and expires pending permission entries', () => {
    const store = new PendingPermissionStore(1000)
    const entry = store.create(
      {
        rule: 'command(git branch)',
        toolName: 'run_command',
        description: 'blocked',
        inputPreview: '{"CommandLine":"git branch"}',
        rawInput: 'git branch',
        chatId: '-100123',
        messageId: 42,
        senderLabel: '@hungdinh',
        isBotSender: false,
        userText: 'check branch',
      },
      1000,
    )
    expect(entry.requestId).toMatch(/^[a-km-z]{5}$/)
    expect(store.get(entry.requestId, 1500)?.rule).toBe('command(git branch)')
    expect(store.get(entry.requestId, 2500)).toBeUndefined()
  })
})

describe('hasPermissionDenial', () => {
  it('detects deniedActions even when model also returns non-empty response text', () => {
    expect(
      hasPermissionDenial({
        conversationId: 'c1',
        response: 'Lệnh curl bị chặn rồi ạ.',
        status: 'SUCCESS',
        deniedActions: [{ action: 'command(curl)', displayName: 'Bash' }],
      }),
    ).toBe(true)
  })

  it('detects permission errors in toolSteps when deniedActions is omitted, without false-triggering on normal errors', () => {
    expect(
      hasPermissionDenial({
        conversationId: 'c2',
        response: 'Em không có quyền chạy curl.',
        status: 'SUCCESS',
        toolSteps: [
          {
            toolName: 'run_command',
            parameters: { CommandLine: 'curl -I https://example.com' },
            state: 'ERROR',
            errorMessage: 'Permission denied for command(curl)',
          },
        ],
      }),
    ).toBe(true)

    expect(
      hasPermissionDenial({
        conversationId: 'c3',
        response: 'Không tìm thấy file.',
        status: 'SUCCESS',
        toolSteps: [
          {
            toolName: 'read_file',
            parameters: { Path: '/tmp/missing.txt' },
            state: 'ERROR',
            errorMessage: 'ENOENT: no such file or directory',
          },
        ],
      }),
    ).toBe(false)
  })
})

describe('formatHardDenyNotice', () => {
  it('includes toolName and sanitized command/target detail when available', () => {
    const msg = formatHardDenyNotice({
      reason: 'lệnh ghép chuỗi/chuyển hướng shell không được phép duyệt tự động',
      toolName: 'run_command',
      rawInput: 'rg -n "DEFAULT_" context-status.ts | head -n 5',
    })
    expect(msg).toContain('🔒 Thao tác bị từ chối cứng')
    expect(msg).toContain('`run_command`')
    expect(msg).toContain('`rg -n "DEFAULT_" context-status.ts | head -n 5`')

    const msgBackticks = formatHardDenyNotice({
      reason: 'test',
      rawInput: 'echo `whoami`',
    })
    expect(msgBackticks).toContain("`echo 'whoami'`")
    expect(msgBackticks).not.toContain('Công cụ:')
  })
})

describe('canAlwaysAllowRule & interpreter/shell protections', () => {
  it('blocks permanent always-allow for shells and script interpreters while allowing once-only ephemeral grant for interpreters', () => {
    for (const rule of [
      'command(bash)',
      'command(sh)',
      'command(zsh)',
      'command(osascript)',
      'command(python)',
      'command(python3)',
      'command(/usr/bin/python3)',
      'command(node)',
      'command(bun)',
      'command(deno)',
      'command(perl)',
      'command(ruby)',
      'command(php)',
      'command(lua)',
    ]) {
      expect(canAlwaysAllowRule(rule).allowed).toBe(false)
    }
    expect(canAlwaysAllowRule('command(curl)').allowed).toBe(true)
    expect(canAlwaysAllowRule('command(git status)').allowed).toBe(true)

    const settingsPath = makeTempSettings({
      deny: ['command(bash)', 'command(sh)'],
    })

    // Permanent grant MUST reject interpreters
    const pyPerm = grantPermissionRuleInFile(settingsPath, 'command(python3)', 'python3 -c "print(1)"')
    expect(pyPerm.ok).toBe(false)

    // Once-only ephemeral grant MUST still work for python3/bun if not in deny
    const ephem = createEphemeralSettingsWithRule({
      settingsPath,
      tempDir: tmpdir(),
      requestId: 'once-py-1',
      rule: 'command(python3)',
      rawInput: 'python3 -c "print(1)"',
    })
    expect(ephem.ok).toBe(true)
    if (ephem.ok) {
      const parsed = JSON.parse(readFileSync(ephem.tempSettingsPath, 'utf8')) as {
        permissions: { allow: string[] }
      }
      expect(parsed.permissions.allow).toContain('command(python3)')
      ephem.cleanup()
    }

    // Hard-denied shell MUST stay blocked even for once-only
    const shEphem = createEphemeralSettingsWithRule({
      settingsPath,
      tempDir: tmpdir(),
      requestId: 'once-bash-1',
      rule: 'command(bash)',
      rawInput: 'bash -c id',
    })
    expect(shEphem.ok).toBe(false)
  })
})

describe('resolveTurnExecutionPolicy', () => {
  it('keeps human private DM in accept-edits and locks all groups, channels, and bot senders to plan + readonly settings', () => {
    const dmHuman = resolveTurnExecutionPolicy({
      chatType: 'private',
      isBotSender: false,
      defaultMode: 'accept-edits',
      defaultSettingsPath: '/tmp/collab.json',
      readonlySettingsPath: '/tmp/group-readonly.json',
      dangerouslySkipPermissions: true,
    })
    expect(dmHuman).toEqual({
      mode: 'accept-edits',
      settingsPath: '/tmp/collab.json',
      dangerouslySkipPermissions: true,
      isReadOnly: false,
    })

    for (const scenario of [
      { chatType: 'group' as const, isBotSender: false },
      { chatType: 'supergroup' as const, isBotSender: false },
      { chatType: 'channel' as const, isBotSender: true },
      { chatType: 'private' as const, isBotSender: true },
    ]) {
      const policy = resolveTurnExecutionPolicy({
        chatType: scenario.chatType,
        isBotSender: scenario.isBotSender,
        defaultMode: 'accept-edits',
        defaultSettingsPath: '/tmp/collab.json',
        readonlySettingsPath: '/tmp/group-readonly.json',
        dangerouslySkipPermissions: true,
      })
      expect(policy).toEqual({
        mode: 'plan',
        settingsPath: '/tmp/group-readonly.json',
        dangerouslySkipPermissions: false,
        isReadOnly: true,
      })
    }
  })
})

describe('formatPermissionDmMessage', () => {
  it('renders redacted full command/target inline on initial DM prompt and warns when always-allow is disabled', () => {
    const fakeToken = ['apify', 'api', 'demo000000000000'].join('_')
    const msg = formatPermissionDmMessage({
      rule: 'command(python3)',
      senderLabel: '@user_demo',
      chatId: '900001',
      rawInput: `python3 fetch.py --token ${fakeToken}`,
      inputPreview: '{"CommandLine":"python3 fetch.py"}',
      canAlwaysAllow: false,
    })
    expect(msg).toContain('🔐 Permission (Gemini): command(python3)')
    expect(msg).toContain('Chi tiết đầy đủ:')
    expect(msg).toContain('python3 fetch.py --token [REDACTED_APIFY_TOKEN]')
    expect(msg).not.toContain(fakeToken)
    expect(msg).toContain('Chỉ hỗ trợ Allow (1 lần)')
  })
})

describe('checked-in settings hardening (items 5.1, 5.2, 5.3)', () => {
  const hubDir = join(import.meta.dir, '..')
  const collabSettingsPath = join(hubDir, 'gemini-collab-settings.json')
  const groupReadonlyPath = join(hubDir, 'gemini-group-readonly-settings.json')

  it('gemini-collab-settings.json hard-denies .git, bridge core files, LaunchAgents, and shells while leaving interpreters once-eligible', () => {
    const repoRoot = join(hubDir, '..', '..')
    for (const [rule, raw] of [
      ['write_file(/Users/hungdinh/Development)', join(repoRoot, '.git', 'config')],
      ['write_file(/Users/hungdinh/Development)', join(hubDir, 'gemini-telegram-bridge', 'server.ts')],
      ['write_file(/Users/hungdinh/Development)', join(hubDir, 'gemini-telegram-bridge', 'agy-runner.ts')],
      ['write_file(/Users/hungdinh/Development)', join(hubDir, 'gemini-telegram-bridge', 'stream-logger.ts')],
      ['write_file(/Users/hungdinh/Development)', join(hubDir, 'gemini-telegram-bridge', 'context-status.ts')],
      ['write_file(/Users/hungdinh/Development)', join(hubDir, 'gemini-telegram-bridge', 'handover.ts')],
      ['write_file(/Users/hungdinh/Development)', join(hubDir, 'gemini-telegram-bridge', 'commands.ts')],
      ['write_file(/Users/hungdinh/Development)', join(hubDir, 'gemini-telegram-bridge', 'media.ts')],
      ['write_file(/Users/hungdinh/Development)', join(hubDir, 'gemini-telegram-bridge', 'permissions.ts')],
      ['write_file(/Users/hungdinh/Development)', join(hubDir, 'lib', 'collab-gate.ts')],
      ['write_file(/Users/hungdinh/Development)', join(hubDir, 'start-gemini-collab.sh')],
      ['write_file(/Users/hungdinh/Development)', join(hubDir, 'gemini-group-readonly-settings.json')],
      ['write_file(/Users/hungdinh/Development)', join(hubDir, 'x-brief-mac', 'editor-readonly-settings.json')],
      ['write_file(/Users/hungdinh/.zshrc)', '/Users/hungdinh/.zshrc'],
      ['write_file(/Users/hungdinh/Library/LaunchAgents)', '/Users/hungdinh/Library/LaunchAgents/com.test.plist'],
      ['command(bash)', 'bash -c id'],
      ['command(sh)', 'sh -c id'],
      ['command(zsh)', 'zsh -c id'],
      ['command(osascript)', 'osascript -e "beep"'],
    ] as const) {
      expect(isRuleBlockedByDeny(collabSettingsPath, rule, raw).blocked).toBe(true)
    }

    // Interpreters remain un-denied so Allow (1 lần) in DM can work, while permanent always-allow is blocked
    expect(isRuleBlockedByDeny(collabSettingsPath, 'command(python3)', 'python3 -V').blocked).toBe(false)
    expect(canAlwaysAllowRule('command(python3)').allowed).toBe(false)
  })

  it('gemini-group-readonly-settings.json uses ask:[] and blocks writes + shells + interpreters + secrets while allowing plan.md & safe reads', () => {
    const parsed = JSON.parse(readFileSync(groupReadonlyPath, 'utf8')) as {
      permissions: { allow: string[]; ask: string[]; deny: string[] }
    }
    expect(parsed.permissions.ask).toEqual([])
    expect(parsed.permissions.allow).toContain('read_file(/Users/hungdinh/Development/hungreo-openclaw)')
    expect(parsed.permissions.allow).toContain('command(git status)')
    expect(isRuleBlockedByDeny(groupReadonlyPath, 'command(python3)', 'python3 -V').blocked).toBe(true)
    expect(isRuleBlockedByDeny(groupReadonlyPath, 'command(node)', 'node -v').blocked).toBe(true)
    expect(isRuleBlockedByDeny(groupReadonlyPath, 'command(bash)', 'bash -c id').blocked).toBe(true)
    expect(
      isRuleBlockedByDeny(groupReadonlyPath, 'read_file(/Users/hungdinh/.ssh)', '/Users/hungdinh/.ssh/id_ed25519')
        .blocked,
    ).toBe(true)
    expect(
      isRuleBlockedByDeny(
        groupReadonlyPath,
        'write_file(/Users/hungdinh/Development/hungreo-openclaw/README.md)',
        '/Users/hungdinh/Development/hungreo-openclaw/README.md',
      ).blocked,
    ).toBe(true)
    // Antigravity plan-mode artifacts under ~/.gemini/antigravity-cli/brain must stay unblocked
    expect(parsed.permissions.deny).not.toContain('write_file(/Users/hungdinh)')
    expect(parsed.permissions.deny).not.toContain('write_file(/Users/hungdinh/.gemini)')
    expect(
      isRuleBlockedByDeny(
        groupReadonlyPath,
        'write_file(/Users/hungdinh/.gemini/antigravity-cli/brain/test/plan.md)',
        '/Users/hungdinh/.gemini/antigravity-cli/brain/test/plan.md',
      ).blocked,
    ).toBe(false)
  })
})
