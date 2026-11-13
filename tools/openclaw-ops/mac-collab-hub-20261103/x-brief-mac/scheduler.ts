import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'

export type LocalScheduleParts = {
  dateKey: string // YYYY-MM-DD in target timezone
  hour: number
  minute: number
}

export type ScheduleState = {
  lastAttemptDate?: string
  lastSuccessDate?: string
  lastStatus?: 'running' | 'ok' | 'error'
  updatedAt?: string
}

/**
 * Extracts calendar date and clock hour/minute in the given IANA timezone without external deps.
 */
export function getLocalScheduleParts(
  now: Date = new Date(),
  timeZone = 'Asia/Ho_Chi_Minh',
): LocalScheduleParts {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  })
  const parts = Object.fromEntries(formatter.formatToParts(now).map(p => [p.type, p.value]))
  const hour = Number(parts.hour === '24' ? '0' : parts.hour)
  const minute = Number(parts.minute)
  return {
    dateKey: `${parts.year}-${parts.month}-${parts.day}`,
    hour,
    minute,
  }
}

/**
 * Fires once per calendar day within a bounded grace window starting at `targetHour:targetMinute`
 * (default 06:30..06:59 Asia/Ho_Chi_Minh), so missed-boot late triggers after 07:00 won't surprise the user.
 */
export function shouldTriggerDailyBrief(params: {
  now?: Date
  lastAttemptDate?: string
  targetHour?: number
  targetMinute?: number
  windowMinutes?: number
  timeZone?: string
}): { shouldRun: boolean; dateKey: string } {
  const targetHour = params.targetHour ?? 6
  const targetMinute = params.targetMinute ?? 30
  const windowMinutes = params.windowMinutes ?? 30
  const local = getLocalScheduleParts(params.now, params.timeZone ?? 'Asia/Ho_Chi_Minh')

  if (params.lastAttemptDate === local.dateKey) {
    return { shouldRun: false, dateKey: local.dateKey }
  }

  const nowTotalMins = local.hour * 60 + local.minute
  const targetTotalMins = targetHour * 60 + targetMinute
  const inWindow = nowTotalMins >= targetTotalMins && nowTotalMins < targetTotalMins + windowMinutes
  return { shouldRun: inWindow, dateKey: local.dateKey }
}

export function loadScheduleState(statePath: string): ScheduleState {
  if (!existsSync(statePath)) {return {}}
  try {
    return JSON.parse(readFileSync(statePath, 'utf8')) as ScheduleState
  } catch {
    return {}
  }
}

export function saveScheduleState(statePath: string, state: ScheduleState): void {
  mkdirSync(dirname(statePath), { recursive: true, mode: 0o700 })
  const tmpPath = `${statePath}.tmp`
  writeFileSync(tmpPath, JSON.stringify(state, null, 2) + '\n', { mode: 0o600 })
  renameSync(tmpPath, statePath)
}

export function startXBriefScheduler(params: {
  statePath: string
  targetHour?: number
  targetMinute?: number
  intervalMs?: number
  onTrigger: (dateKey: string) => Promise<void>
  log?: (msg: string) => void
}): { stop: () => void } {
  let active = false
  let stopped = false

  const tick = async () => {
    if (stopped || active) {return}
    const state = loadScheduleState(params.statePath)
    const verdict = shouldTriggerDailyBrief({
      lastAttemptDate: state.lastAttemptDate,
      targetHour: params.targetHour ?? 6,
      targetMinute: params.targetMinute ?? 30,
    })
    if (!verdict.shouldRun) {return}

    active = true
    saveScheduleState(params.statePath, {
      ...state,
      lastAttemptDate: verdict.dateKey,
      lastStatus: 'running',
      updatedAt: new Date().toISOString(),
    })
    params.log?.(`⏰ trigger scheduled X brief for ${verdict.dateKey}`)
    try {
      await params.onTrigger(verdict.dateKey)
      saveScheduleState(params.statePath, {
        ...loadScheduleState(params.statePath),
        lastAttemptDate: verdict.dateKey,
        lastSuccessDate: verdict.dateKey,
        lastStatus: 'ok',
        updatedAt: new Date().toISOString(),
      })
    } catch (err) {
      params.log?.(`⚠️ scheduled X brief failed: ${err instanceof Error ? err.message : String(err)}`)
      saveScheduleState(params.statePath, {
        ...loadScheduleState(params.statePath),
        lastAttemptDate: verdict.dateKey,
        lastStatus: 'error',
        updatedAt: new Date().toISOString(),
      })
    } finally {
      active = false
    }
  }

  const timer = setInterval(() => {
    void tick()
  }, params.intervalMs ?? 30_000)
  timer.unref?.()

  return {
    stop: () => {
      stopped = true
      clearInterval(timer)
    },
  }
}
