import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'
import { getIsoWeekParts } from './collector.ts'

export type WeeklyScheduleParts = {
  dateKey: string
  weekKey: string
  weekday: string // e.g. 'Mon', 'Tue'
  hour: number
  minute: number
}

export type WeeklyScheduleState = {
  lastAttemptWeekKey?: string
  lastSuccessWeekKey?: string
  lastAttemptDate?: string
  lastStatus?: 'running' | 'ok' | 'error'
  updatedAt?: string
}

/**
 * Extracts calendar date, ISO week key, short English weekday, and clock time in IANA timezone.
 */
export function getWeeklyScheduleParts(now: Date = new Date(), timeZone = 'Asia/Ho_Chi_Minh'): WeeklyScheduleParts {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    weekday: 'short',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  })
  const parts = Object.fromEntries(formatter.formatToParts(now).map(p => [p.type, p.value]))
  const dateKey = `${parts.year}-${parts.month}-${parts.day}`
  const hour = Number(parts.hour === '24' ? '0' : parts.hour)
  const minute = Number(parts.minute)
  const { weekKey } = getIsoWeekParts(dateKey)
  return {
    dateKey,
    weekKey,
    weekday: parts.weekday ?? '',
    hour,
    minute,
  }
}

/**
 * Fires once per ISO week on the target weekday (default Monday) within a bounded 30-minute
 * window starting at `07:30 Asia/Ho_Chi_Minh`, well clear of the 06:30 Mac X brief and 07:00 Rùa watch.
 */
export function shouldTriggerWeeklyMiner(params: {
  now?: Date
  lastAttemptWeekKey?: string
  targetWeekday?: string
  targetHour?: number
  targetMinute?: number
  windowMinutes?: number
  timeZone?: string
}): { shouldRun: boolean; weekKey: string; dateKey: string } {
  const targetWeekday = params.targetWeekday ?? 'Mon'
  const targetHour = params.targetHour ?? 7
  const targetMinute = params.targetMinute ?? 30
  const windowMinutes = params.windowMinutes ?? 30
  const local = getWeeklyScheduleParts(params.now, params.timeZone ?? 'Asia/Ho_Chi_Minh')

  if (params.lastAttemptWeekKey === local.weekKey) {
    return { shouldRun: false, weekKey: local.weekKey, dateKey: local.dateKey }
  }
  if (local.weekday.toLowerCase() !== targetWeekday.toLowerCase()) {
    return { shouldRun: false, weekKey: local.weekKey, dateKey: local.dateKey }
  }

  const nowTotalMins = local.hour * 60 + local.minute
  const targetTotalMins = targetHour * 60 + targetMinute
  const inWindow = nowTotalMins >= targetTotalMins && nowTotalMins < targetTotalMins + windowMinutes
  return { shouldRun: inWindow, weekKey: local.weekKey, dateKey: local.dateKey }
}

export function loadWeeklyScheduleState(statePath: string): WeeklyScheduleState {
  if (!existsSync(statePath)) {
    return {}
  }
  try {
    return JSON.parse(readFileSync(statePath, 'utf8')) as WeeklyScheduleState
  } catch {
    return {}
  }
}

export function saveWeeklyScheduleState(statePath: string, state: WeeklyScheduleState): void {
  mkdirSync(dirname(statePath), { recursive: true, mode: 0o700 })
  const tmpPath = `${statePath}.tmp`
  writeFileSync(tmpPath, JSON.stringify(state, null, 2) + '\n', { mode: 0o600 })
  renameSync(tmpPath, statePath)
}

export function startIdeaMinerScheduler(params: {
  statePath: string
  targetWeekday?: string
  targetHour?: number
  targetMinute?: number
  intervalMs?: number
  onTrigger: (weekKey: string, dateKey: string) => Promise<void>
  log?: (msg: string) => void
}): { stop: () => void } {
  let active = false
  let stopped = false

  const tick = async () => {
    if (stopped || active) {
      return
    }
    const state = loadWeeklyScheduleState(params.statePath)
    const verdict = shouldTriggerWeeklyMiner({
      lastAttemptWeekKey: state.lastAttemptWeekKey,
      targetWeekday: params.targetWeekday ?? 'Mon',
      targetHour: params.targetHour ?? 7,
      targetMinute: params.targetMinute ?? 30,
    })
    if (!verdict.shouldRun) {
      return
    }

    active = true
    saveWeeklyScheduleState(params.statePath, {
      ...state,
      lastAttemptWeekKey: verdict.weekKey,
      lastAttemptDate: verdict.dateKey,
      lastStatus: 'running',
      updatedAt: new Date().toISOString(),
    })
    params.log?.(`⏰ trigger scheduled weekly Idea Miner for ${verdict.weekKey} (${verdict.dateKey})`)
    try {
      await params.onTrigger(verdict.weekKey, verdict.dateKey)
      saveWeeklyScheduleState(params.statePath, {
        ...loadWeeklyScheduleState(params.statePath),
        lastAttemptWeekKey: verdict.weekKey,
        lastSuccessWeekKey: verdict.weekKey,
        lastAttemptDate: verdict.dateKey,
        lastStatus: 'ok',
        updatedAt: new Date().toISOString(),
      })
    } catch (err) {
      params.log?.(`⚠️ scheduled weekly Idea Miner failed: ${err instanceof Error ? err.message : String(err)}`)
      saveWeeklyScheduleState(params.statePath, {
        ...loadWeeklyScheduleState(params.statePath),
        lastAttemptWeekKey: verdict.weekKey,
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
  }, params.intervalMs ?? 60_000)
  timer.unref?.()
  const bootTimer = setTimeout(() => {
    void tick()
  }, 5_000)
  bootTimer.unref?.()

  return {
    stop: () => {
      stopped = true
      clearInterval(timer)
      clearTimeout(bootTimer)
    },
  }
}
