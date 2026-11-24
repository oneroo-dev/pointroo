// The "Auto-start agent" settings (A1): the choices the Settings screen shows, the defaults the app uses when nothing is
// saved (the same ones as AutoStart.swift), and small helpers so the screen and the tests read a value the same way.
import type { AutoStartChoiceKey, BridgeAutoRun, SettingsValues } from '../types'

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
const budgetSteps = [0.5, 1, 2, 5, 10, 20]

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

export function runsText(runs: BridgeAutoRun[]): string {
  if (runs.length === 0) return 'No run going'
  return runs.length === 1 ? '1 run going' : `${runs.length} runs going`
}
