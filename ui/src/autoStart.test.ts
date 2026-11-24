// The Auto-start settings (A1): the Settings rows read their values with the app's defaults, and every one of the five
// settings is saved through the store to the bridge (the fake bridge checks the values like the app does).
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

// The store and the bridge file read `window` when they load, and this runs in plain node.
vi.hoisted(() => {
  ;(globalThis as { window?: unknown }).window = globalThis
})

import { createFakeBridge } from './fakeBridge'
import { autoStartChoices, autoStartOn, budgetOptions, budgetValue, choiceValue, runsText } from './parts/autoStart'
import { createStore } from './store'

beforeEach(() => {
  vi.useFakeTimers()
})

afterEach(() => {
  vi.useRealTimers()
})

/** The fake bridge answers after a (fake) timer, so time must run while the call is awaited. */
async function settle(promise: Promise<void>): Promise<void> {
  await vi.advanceTimersByTimeAsync(500)
  await promise
}

describe('reading the auto-start values', () => {
  it('it_uses_the_apps_defaults_when_nothing_is_saved', () => {
    expect(choiceValue({}, 'autoStartAgent')).toBe('off')
    expect(choiceValue({}, 'autoStartModel')).toBe('sonnet')
    expect(choiceValue({}, 'autoStartEffort')).toBe('medium')
    expect(choiceValue({}, 'autoStartPermission')).toBe('acceptEdits')
    expect(budgetValue({})).toBe(2)
    expect(autoStartOn({})).toBe(false)
  })

  it('it_reads_saved_values_and_ignores_ones_that_are_not_choices', () => {
    expect(choiceValue({ autoStartModel: 'opus' }, 'autoStartModel')).toBe('opus')
    expect(choiceValue({ autoStartModel: 'gpt' }, 'autoStartModel')).toBe('sonnet')
    expect(choiceValue({ autoStartEffort: true }, 'autoStartEffort')).toBe('medium')
    expect(budgetValue({ autoStartBudget: 7.5 })).toBe(7.5)
    expect(budgetValue({ autoStartBudget: '7' })).toBe(2)
    expect(autoStartOn({ autoStartAgent: 'claude' })).toBe(true)
  })

  it('it_never_offers_bypass_permissions', () => {
    const values = autoStartChoices.autoStartPermission.options.map((option) => option.value)
    expect(values).toEqual(['acceptEdits', 'dontAsk', 'auto'])
  })

  it('it_adds_a_saved_budget_that_is_not_one_of_the_steps', () => {
    expect(budgetOptions(2).map((option) => option.value)).toEqual(['0.5', '1', '2', '5', '10', '20'])
    expect(budgetOptions(3).map((option) => option.value)).toEqual(['0.5', '1', '2', '3', '5', '10', '20'])
  })

  it('it_says_how_many_runs_are_going', () => {
    expect(runsText([])).toBe('No run going')
    expect(runsText([{ project: '/work/a', startedAt: '2026-11-24T10:00:00Z' }])).toBe('1 run going')
    expect(
      runsText([
        { project: '/work/a', startedAt: '2026-11-24T10:00:00Z' },
        { project: '/work/b', startedAt: '2026-11-24T10:01:00Z' },
      ]),
    ).toBe('2 runs going')
  })
})

describe('saving the auto-start settings', () => {
  it('it_loads_the_five_settings_with_their_defaults', async () => {
    const store = createStore(createFakeBridge())
    await settle(store.openSettings())
    expect(store.settings.autoStartAgent).toBe('off')
    expect(store.settings.autoStartModel).toBe('sonnet')
    expect(store.settings.autoStartEffort).toBe('medium')
    expect(store.settings.autoStartBudget).toBe(2)
    expect(store.settings.autoStartPermission).toBe('acceptEdits')
  })

  it('it_saves_each_of_the_five_settings', async () => {
    const store = createStore(createFakeBridge())
    await settle(store.openSettings())
    await settle(store.setSetting('autoStartAgent', 'claude', 'Auto-start agent: Claude'))
    await settle(store.setSetting('autoStartModel', 'opus', 'Model: Opus'))
    await settle(store.setSetting('autoStartEffort', 'xhigh', 'Effort: Extra high'))
    await settle(store.setSetting('autoStartBudget', 5, 'Budget: $5'))
    await settle(store.setSetting('autoStartPermission', 'auto', 'Permission: Auto'))
    expect(store.settings.autoStartAgent).toBe('claude')
    expect(store.settings.autoStartModel).toBe('opus')
    expect(store.settings.autoStartEffort).toBe('xhigh')
    expect(store.settings.autoStartBudget).toBe(5)
    expect(store.settings.autoStartPermission).toBe('auto')
    await settle(store.openSettings())
    expect(store.settings.autoStartBudget).toBe(5)
    expect(store.settings.autoStartAgent).toBe('claude')
  })

  it('it_puts_the_old_value_back_when_the_app_refuses_a_value', async () => {
    const store = createStore(createFakeBridge())
    await settle(store.openSettings())
    await settle(store.setSetting('autoStartPermission', 'bypassPermissions', 'Permission: bypass'))
    expect(store.settings.autoStartPermission).toBe('acceptEdits')
    await settle(store.setSetting('autoStartBudget', 99, 'Budget: $99'))
    expect(store.settings.autoStartBudget).toBe(2)
    expect(store.toast?.tone).toBe('warn')
  })

  it('it_shows_one_sample_run_once_auto_start_is_on', async () => {
    const store = createStore(createFakeBridge())
    await settle(store.openSettings())
    expect(store.status?.autoRuns).toEqual([])
    await settle(store.setSetting('autoStartAgent', 'claude', 'Auto-start agent: Claude'))
    await settle(store.openSettings())
    expect(store.status?.autoRuns.length).toBe(1)
  })
})
