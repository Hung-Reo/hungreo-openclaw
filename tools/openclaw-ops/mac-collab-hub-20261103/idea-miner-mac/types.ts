export type IdeaMinerMode = 'scheduled' | 'test' | 'dry-run'

export type CollectedHandoverItem = {
  sourceName: string
  updatedAtIso: string
  excerpt: string
}

export type CollectedSessionItem = {
  sessionId: string
  updatedAtIso: string
  userInputsCount: number
  toolDenialCount: number
  errorStepCount: number
  userHighlights: string[]
  frictionHighlights: string[]
}

export type CollectedLessonItem = {
  fileName: string
  title: string
}

export type WeeklyDigest = {
  weekKey: string
  weekNumber: number
  isoYear: number
  windowStartDate: string
  windowEndDate: string
  generatedAtIso: string
  handovers: CollectedHandoverItem[]
  sessions: CollectedSessionItem[]
  recentLessons: CollectedLessonItem[]
}

export type IdeaEntry = {
  projectTag: string
  title: string
  whyFromOwner: string
  smallestNextStep: string
  sourceRef: string
}

export type SkillProposalEntry = {
  repeatTag: string
  issueTitle: string
  draftRuleOrSkill: string
  targetRef: string
}

export type BottleneckNote = {
  summary: string
  suggestion: string
}

export type IdeaMinerReport = {
  weekKey: string
  weekNumber: number
  isoYear: number
  windowStartDate: string
  windowEndDate: string
  sessionsScanned: number
  handoversScanned: number
  ideas: IdeaEntry[]
  skillProposals: SkillProposalEntry[]
  bottleneck: BottleneckNote
  usedFallbackEditor: boolean
}

export type RunIdeaMinerResult =
  | {
      ok: true
      skipped: true
      skipReason: string
      durationSeconds: number
    }
  | {
      ok: true
      skipped: false
      report: IdeaMinerReport
      message: string
      reportPath: string
      durationSeconds: number
    }
  | {
      ok: false
      stage: 'collect' | 'deliver'
      error: string
      durationSeconds: number
    }
