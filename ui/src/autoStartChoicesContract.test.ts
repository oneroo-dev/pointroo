// The auto-start choices contract (T7): the Settings screen (parts/autoStart.ts) and the app (AutoStart.swift) must offer
// the same choices, the same defaults and the same budget limits. The test reads the Swift files as plain text, so a
// change on one side only fails here.
import { describe, expect, it } from 'vitest'

import autoStartSource from '../../Sources/PointAndYap/AutoStart.swift?raw'
import webBridgeSource from '../../Sources/PointAndYap/WebBridge.swift?raw'
import { autoStartChoices, budgetFallback, budgetSteps } from './parts/autoStart'

function findOrFail(source: string, pattern: RegExp, label: string): RegExpExecArray {
  const match = pattern.exec(source)
  if (!match) throw new Error(`Could not find ${label} in the Swift file`)
  return match
}

/** The strings of `static let <name> = ["a", "b"]`. */
function swiftList(name: string): string[] {
  const match = findOrFail(autoStartSource, new RegExp(`static let ${name}\\s*=\\s*\\[([^\\]]*)\\]`), `the list ${name}`)
  const body = match[1] ?? ''
  const values = [...body.matchAll(/"([^"]*)"/g)].map((item) => item[1] ?? '')
  if (values.length === 0) throw new Error(`The list ${name} has no values`)
  return values
}

function swiftStringDefault(name: string): string {
  const match = findOrFail(autoStartSource, new RegExp(`static let ${name}\\s*=\\s*"([^"]*)"`), `the default ${name}`)
  return match[1] ?? ''
}

function swiftNumber(pattern: RegExp, label: string): number {
  const match = findOrFail(autoStartSource, pattern, label)
  const value = Number(match[1])
  if (!Number.isFinite(value)) throw new Error(`${label} is not a number`)
  return value
}

const swiftLists = {
  autoStartAgent: swiftList('agents'),
  autoStartModel: swiftList('models'),
  autoStartEffort: swiftList('efforts'),
  autoStartPermission: swiftList('permissions'),
}

const swiftDefaults = {
  autoStartAgent: swiftStringDefault('defaultAgent'),
  autoStartModel: swiftStringDefault('defaultModel'),
  autoStartEffort: swiftStringDefault('defaultEffort'),
  autoStartPermission: swiftStringDefault('defaultPermission'),
}

const swiftBudgetDefault = swiftNumber(/static let defaultBudget\s*=\s*([0-9.]+)/, 'the default defaultBudget')
const swiftBudgetLow = swiftNumber(/static let budgetRange:\s*ClosedRange<Double>\s*=\s*([0-9.]+)\.\.\./, 'the start of budgetRange')
const swiftBudgetHigh = swiftNumber(/static let budgetRange:\s*ClosedRange<Double>\s*=\s*[0-9.]+?\.\.\.([0-9.]+)/, 'the end of budgetRange')

const choiceKeys = Object.keys(swiftLists) as (keyof typeof swiftLists)[]

describe('auto-start choices contract', () => {
  it('it_reads_every_swift_list_and_default', () => {
    expect(choiceKeys).toHaveLength(4)
    expect(swiftBudgetLow).toBeLessThan(swiftBudgetHigh)
  })

  it('it_offers_the_same_options_in_the_same_order_as_swift', () => {
    for (const key of choiceKeys) {
      const values = autoStartChoices[key].options.map((option) => option.value)
      expect(values, key).toEqual(swiftLists[key])
    }
  })

  it('it_uses_the_swift_default_as_each_fallback', () => {
    for (const key of choiceKeys) {
      expect(autoStartChoices[key].fallback, key).toBe(swiftDefaults[key])
    }
  })

  it('it_uses_the_swift_default_budget_as_the_budget_fallback', () => {
    expect(budgetFallback).toBe(swiftBudgetDefault)
  })

  it('it_keeps_every_budget_step_inside_the_swift_range', () => {
    for (const step of budgetSteps) {
      expect(step).toBeGreaterThanOrEqual(swiftBudgetLow)
      expect(step).toBeLessThanOrEqual(swiftBudgetHigh)
    }
  })

  it('it_has_both_ends_of_the_swift_range_as_steps_and_the_default_too', () => {
    expect(budgetSteps).toContain(swiftBudgetLow)
    expect(budgetSteps).toContain(swiftBudgetHigh)
    expect(budgetSteps).toContain(swiftBudgetDefault)
  })

  it('it_offers_bypassPermissions_on_neither_side', () => {
    expect(swiftLists.autoStartPermission).not.toContain('bypassPermissions')
    const uiValues = autoStartChoices.autoStartPermission.options.map((option) => option.value)
    expect(uiValues).not.toContain('bypassPermissions')
  })

  it('it_lets_the_swift_bridge_allow_only_the_autostart_lists', () => {
    const expected: Record<string, string> = {
      autoStartAgent: '.choice(allowed: AutoStart.agents,',
      autoStartModel: '.choice(allowed: AutoStart.models,',
      autoStartEffort: '.choice(allowed: AutoStart.efforts,',
      autoStartBudget: '.number(range: AutoStart.budgetRange,',
      autoStartPermission: '.choice(allowed: AutoStart.permissions,',
    }
    for (const [key, reference] of Object.entries(expected)) {
      const line = findOrFail(webBridgeSource, new RegExp(`^.*\\("${key}",.*$`, 'm'), `the allowedSettings line for ${key}`)
      expect(line[0], key).toContain(reference)
    }
  })
})
