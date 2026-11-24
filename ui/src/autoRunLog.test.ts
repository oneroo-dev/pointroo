// R38: the auto-start log panel's store actions (read the newest 50 lines, keep them, forget them on Hide).
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

// The store and the bridge file read `window` when they load, and this runs in plain node.
vi.hoisted(() => {
  ;(globalThis as { window?: unknown }).window = globalThis
})

import type { Bridge } from './bridge'
import { createFakeBridge } from './fakeBridge'
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

describe('the auto-start log', () => {
  it('it_asks_for_50_lines_and_keeps_them', async () => {
    const fake = createFakeBridge()
    const callSpy = vi.spyOn(fake, 'call')
    const store = createStore(fake)
    expect(store.autoRunLog).toBeUndefined()
    await settle(store.loadAutoRunLog())
    expect(callSpy).toHaveBeenCalledWith('autoRuns.log', { lines: 50 })
    expect(store.autoRunLog?.length).toBe(3)
    expect(store.autoRunLog?.[2]).toContain('shoproo')
    expect(store.autoRunLogLoading).toBe(false)
  })

  it('it_keeps_an_empty_log_as_an_empty_list', async () => {
    const fake = createFakeBridge()
    const emptyBridge: Bridge = {
      on: (name, handler) => fake.on(name, handler),
      call: (method, params) => (method === 'autoRuns.log' ? Promise.resolve({ lines: [] } as never) : fake.call(method, params)),
    }
    const store = createStore(emptyBridge)
    await store.loadAutoRunLog()
    expect(store.autoRunLog).toEqual([])
  })

  it('it_forgets_the_lines_on_hide', async () => {
    const store = createStore(createFakeBridge())
    await settle(store.loadAutoRunLog())
    expect(store.autoRunLog).toBeDefined()
    store.hideAutoRunLog()
    expect(store.autoRunLog).toBeUndefined()
  })

  it('it_shows_the_usual_toast_and_stays_closed_when_the_read_fails', async () => {
    const fake = createFakeBridge()
    const failingBridge: Bridge = {
      on: (name, handler) => fake.on(name, handler),
      call: (method, params) => (method === 'autoRuns.log' ? Promise.reject(new Error('The log is not there.')) : fake.call(method, params)),
    }
    const store = createStore(failingBridge)
    await store.loadAutoRunLog()
    expect(store.autoRunLog).toBeUndefined()
    expect(store.autoRunLogLoading).toBe(false)
    expect(store.toast?.tone).toBe('warn')
  })
})
