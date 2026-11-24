// R35: the Last run text, the "ago" words, and the Stop button's store action (it calls the bridge, then reads the status again).
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

// The store and the bridge file read `window` when they load, and this runs in plain node.
vi.hoisted(() => {
  ;(globalThis as { window?: unknown }).window = globalThis
})

import { createFakeBridge } from './fakeBridge'
import { lastRunNote, lastRunText, projectShortName, relativeTime, runLineText } from './parts/autoStart'
import { createStore } from './store'

const now = Date.parse('2026-11-24T12:00:00Z')

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

describe('the "ago" words', () => {
  it('it_says_just_now_minutes_hours_and_days', () => {
    expect(relativeTime('2026-11-24T11:59:40Z', now)).toBe('just now')
    expect(relativeTime('2026-11-24T11:50:00Z', now)).toBe('10 min ago')
    expect(relativeTime('2026-11-24T11:00:00Z', now)).toBe('1 hour ago')
    expect(relativeTime('2026-11-24T09:00:00Z', now)).toBe('3 hours ago')
    expect(relativeTime('2026-11-23T12:00:00Z', now)).toBe('1 day ago')
    expect(relativeTime('2026-11-20T12:00:00Z', now)).toBe('4 days ago')
  })

  it('it_treats_a_date_in_the_future_as_just_now_and_a_bad_date_as_nothing', () => {
    expect(relativeTime('2026-11-24T12:05:00Z', now)).toBe('just now')
    expect(relativeTime('not a date', now)).toBe('')
  })
})

describe('the project name', () => {
  it('it_uses_the_last_folder_part', () => {
    expect(projectShortName('/Users/sample/Workspace/tinkeroo')).toBe('tinkeroo')
    expect(projectShortName('/Users/sample/Workspace/tinkeroo/')).toBe('tinkeroo')
    expect(projectShortName('tinkeroo')).toBe('tinkeroo')
  })

  it('it_shows_a_going_run_with_its_start_time', () => {
    expect(runLineText({ project: '/work/tinkeroo', startedAt: '2026-11-24T11:58:00Z' }, now)).toBe('tinkeroo, started 2 min ago')
  })
})

describe('the Last run row', () => {
  const base = { project: '/work/tinkeroo', endedAt: '2026-11-24T11:50:00Z' }

  it('it_shows_the_project_the_time_and_the_cost', () => {
    expect(lastRunText({ ...base, exitCode: 0, cost: 0.42 }, now)).toBe('tinkeroo, 10 min ago, $0.42')
    expect(lastRunNote({ ...base, exitCode: 0, cost: 0.42 })).toBeUndefined()
  })

  it('it_leaves_the_cost_out_when_it_is_missing', () => {
    expect(lastRunText({ ...base, exitCode: 0 }, now)).toBe('tinkeroo, 10 min ago')
  })

  it('it_marks_an_error_and_a_run_that_could_not_start', () => {
    expect(lastRunNote({ ...base, exitCode: 1 })).toBe('ended with an error')
    expect(lastRunNote({ ...base, exitCode: -1 })).toBe('could not start')
  })
})

describe('the Stop button', () => {
  it('it_stops_the_run_and_reads_the_status_again', async () => {
    const store = createStore(createFakeBridge())
    await settle(store.openSettings())
    await settle(store.setSetting('autoStartAgent', 'claude', 'Auto-start agent: Claude'))
    await settle(store.openSettings())
    expect(store.status?.autoRuns.length).toBe(1)
    await settle(store.stopAutoRun('/Users/sample/Workspace/tinkeroo'))
    expect(store.status?.autoRuns).toEqual([])
    expect(store.stoppingRuns).toEqual([])
    expect(store.toast?.message).not.toBe('That run already ended')
  })

  it('it_shows_a_quiet_toast_when_the_run_already_ended', async () => {
    const store = createStore(createFakeBridge())
    await settle(store.openSettings())
    await settle(store.setSetting('autoStartAgent', 'claude', 'Auto-start agent: Claude'))
    await settle(store.stopAutoRun('/Users/sample/Workspace/tinkeroo'))
    await settle(store.stopAutoRun('/Users/sample/Workspace/tinkeroo'))
    expect(store.toast?.message).toBe('That run already ended')
    expect(store.toast?.tone).toBe('muted')
  })
})
