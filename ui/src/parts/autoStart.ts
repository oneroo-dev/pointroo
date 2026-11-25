// The "Auto-start agent" settings (A1): the choices the Settings screen shows, the defaults the app uses when nothing is
// saved (the same ones as AutoStart.swift), and small helpers so the screen and the tests read a value the same way.
import type { AutoStartChoiceKey, BridgeAutoRun, BridgeLastAutoRun, SettingsValues } from '../types'

export interface AutoStartOption {
  value: string
  label: string
}

export const autoStartChoices: Record<AutoStartChoiceKey, { label: string; fallback: string; options: AutoStartOption[] }> = {
  autoStartAgent: {
    label: 'Agent',
    fallback: 'off',
    options: [
      { value: 'off', label: 'Off' },
      { value: 'claude', label: 'Claude' },
    ],
  },
  autoStartModel: {
    label: 'Model',
    fallback: 'sonnet',
    options: [
      { value: 'sonnet', label: 'Sonnet' },
      { value: 'opus', label: 'Opus' },
      { value: 'fable', label: 'Fable' },
    ],
  },
  autoStartEffort: {
    label: 'Effort',
    fallback: 'medium',
    options: [
      { value: 'low', label: 'Low' },
      { value: 'medium', label: 'Medium' },
      { value: 'high', label: 'High' },
      { value: 'xhigh', label: 'Extra high' },
      { value: 'max', label: 'Max' },
    ],
  },
  autoStartPermission: {
    label: 'Permission',
    fallback: 'acceptEdits',
    options: [
      { value: 'acceptEdits', label: 'Edit files' },
      { value: 'dontAsk', label: 'Allowed tools only' },
      { value: 'auto', label: 'Auto' },
    ],
  },
}

export const budgetFallback = 2
export const budgetSteps = [0.5, 1, 2, 5, 10, 20]

/** The saved choice, or the app's default when the app has not sent one (or sent something that is not a choice here). */
export function choiceValue(values: SettingsValues, key: AutoStartChoiceKey): string {
  const entry = autoStartChoices[key]
  const saved = values[key]
  return typeof saved === 'string' && entry.options.some((option) => option.value === saved) ? saved : entry.fallback
}

export function budgetValue(values: SettingsValues): number {
  const saved = values.autoStartBudget
  return typeof saved === 'number' && Number.isFinite(saved) ? saved : budgetFallback
}

export function budgetLabel(dollars: number): string {
  return `$${dollars}`
}

/** The budget choices. A saved value that is not one of the steps (set another way) is added so the select can show it. */
export function budgetOptions(current: number): AutoStartOption[] {
  const steps = budgetSteps.includes(current) ? budgetSteps : [...budgetSteps, current].sort((first, second) => first - second)
  return steps.map((dollars) => ({ value: String(dollars), label: budgetLabel(dollars) }))
}

export function autoStartOn(values: SettingsValues): boolean {
  return choiceValue(values, 'autoStartAgent') !== 'off'
}

/** What the permission lets a run do, in a few words. */
const permissionPhrases: Record<string, string> = {
  acceptEdits: 'May edit files.',
  dontAsk: 'Allowed tools only.',
  auto: 'Decides by itself.',
}

/** The one line that sums up a run: "Sonnet, medium effort" with "Up to $2 a run. May edit files." under it. */
export function runSummary(values: SettingsValues): { title: string; detail: string } {
  const optionLabel = (key: AutoStartChoiceKey): string => {
    const value = choiceValue(values, key)
    return autoStartChoices[key].options.find((option) => option.value === value)?.label ?? value
  }
  const permission = permissionPhrases[choiceValue(values, 'autoStartPermission')] ?? ''
  return {
    title: `${optionLabel('autoStartModel')}, ${optionLabel('autoStartEffort').toLowerCase()} effort`,
    detail: `Up to ${budgetLabel(budgetValue(values))} a run. ${permission}`.trim(),
  }
}

/** The last folder of a project path: "/Users/sample/Workspace/tinkeroo/" gives "tinkeroo". */
export function projectShortName(project: string): string {
  const parts = project.split('/').filter((part) => part !== '')
  return parts.length === 0 ? project : (parts[parts.length - 1] ?? project)
}

/** How long ago a date (ISO text) was, as short words. `now` is in milliseconds and is passed in so tests stay the same. */
export function relativeTime(isoDate: string, now: number): string {
  const then = Date.parse(isoDate)
  if (!Number.isFinite(then)) return ''
  const minutes = Math.floor(Math.max(0, now - then) / 60000)
  if (minutes < 1) return 'just now'
  if (minutes < 60) return `${minutes} min ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return hours === 1 ? '1 hour ago' : `${hours} hours ago`
  const days = Math.floor(hours / 24)
  return days === 1 ? '1 day ago' : `${days} days ago`
}

/** One going run: "tinkeroo, started 2 min ago". */
export function runLineText(run: BridgeAutoRun, now: number): string {
  const ago = relativeTime(run.startedAt, now)
  const name = projectShortName(run.project)
  return ago === '' ? name : `${name}, started ${ago}`
}

/** The last run that ended: "tinkeroo, 10 min ago, $0.42". The cost is left out when it is not known. */
export function lastRunText(run: BridgeLastAutoRun, now: number): string {
  const pieces = [projectShortName(run.project), relativeTime(run.endedAt, now)]
  if (typeof run.cost === 'number' && Number.isFinite(run.cost)) pieces.push(`$${run.cost.toFixed(2)}`)
  return pieces.filter((piece) => piece !== '').join(', ')
}

/** The small note beside the last run: nothing when it went fine. */
export function lastRunNote(run: BridgeLastAutoRun): string | undefined {
  if (run.exitCode === -1) return 'could not start'
  return run.exitCode === 0 ? undefined : 'ended with an error'
}

export function runsText(runs: BridgeAutoRun[]): string {
  if (runs.length === 0) return 'No run going'
  return runs.length === 1 ? '1 run going' : `${runs.length} runs going`
}
