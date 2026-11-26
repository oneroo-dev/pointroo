// The fake bridge contract (T5): the fake bridge (fakeBridge.ts) must handle every method in types.ts BridgeMethods and
// must be able to send every event in BridgeEvents, so the plain browser (npm run dev) never lags behind the app.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

// The fake bridge reads `window` when it loads, and this runs in plain node.
vi.hoisted(() => {
  ;(globalThis as { window?: unknown }).window = globalThis
})

import { BridgeError } from './bridgeError'
import { createFakeBridge } from './fakeBridge'
import fakeSource from './fakeBridge.ts?raw'
import typesSource from './types.ts?raw'
import type { Bridge } from './bridge'
import type { BridgeEventName, BridgeMethod } from './types'

/** Methods the fake does not handle on purpose. Each one needs a reason. Empty today. */
const unhandledMethods: Record<string, string> = {}
/** Events the fake never sends. Each one needs a reason. Empty today. */
const unsentEvents: Record<string, string> = {}

/**
 * The smallest params each method accepts. The fake may still answer with a BridgeError (for example "not_found" for
 * an id that does not exist on a fresh bridge); that is a real answer. Only a missing handler is a failure.
 */
const minimalParams: Record<BridgeMethod, Record<string, unknown>> = {
  'items.list': {},
  'projects.list': {},
  'items.get': { id: 'nothing' },
  'items.reroute': { id: 'nothing', project: 'nothing' },
  'questions.list': {},
  'questions.answer': { id: 'q1', text: 'yes' },
  'settings.get': {},
  'settings.set': { key: 'sounds', value: true },
  'status.get': {},
  'permissions.ask': { which: 'microphone' },
  'items.done': { id: 'nothing' },
  'items.reopen': { id: 'nothing' },
  'items.trash': { id: 'nothing' },
  'items.unroute': { id: 'nothing' },
  'route.change': { session: 'sample' },
  'done.recent': {},
  'session.get': { session: 'sample' },
  'questions.later': { id: 'q1' },
  'clipboard.copy': { text: 'hello' },
  'window.startDrag': {},
  'server.useAnotherPort': {},
  'app.checkUpdates': {},
  'items.search': { text: 'a' },
  'recording.start': {},
  'recording.stop': {},
  'recording.cancel': {},
  'recording.get': {},
  'picker.get': {},
  'picker.pick': { path: 'nothing' },
  'picker.skip': {},
  'notices.list': {},
  'notices.seen': { ids: [] },
  'autoRuns.stop': { project: '/Users/sample/Workspace/tinkeroo' },
  'autoRuns.log': { lines: 2 },
}

/** The keys of an interface in types.ts: quoted names at the first indent level, like `  'items.list': {...}`. */
function typeKeys(interfaceName: string): string[] {
  const start = new RegExp(`export interface ${interfaceName} \\{\\n`).exec(typesSource)
  if (!start) throw new Error(`Could not find interface ${interfaceName} in types.ts`)
  const rest = typesSource.slice(start.index + start[0].length)
  const end = /^\}/m.exec(rest)
  if (!end) throw new Error(`Could not find the end of interface ${interfaceName} in types.ts`)
  const names: string[] = []
  for (const match of rest.slice(0, end.index).matchAll(/^ {2}'([A-Za-z]+(?:\.[A-Za-z]+)+)'\s*:/gm)) {
    const name = match[1]
    if (name) names.push(name)
  }
  return names
}

let bridge: Bridge

beforeEach(() => {
  // The fake answers after a short timer (60 ms), so the tests move the clock by hand.
  vi.useFakeTimers()
  bridge = createFakeBridge()
})

afterEach(() => {
  vi.useRealTimers()
})

/** Calls a method and returns what happened: the answer, or the error it rejected with. */
async function outcome(method: string, params: Record<string, unknown>): Promise<{ answered: true } | { error: unknown }> {
  const pending = (bridge.call as (name: string, value: unknown) => Promise<unknown>)(method, params).then(
    () => ({ answered: true as const }),
    (error: unknown) => ({ error }),
  )
  await vi.advanceTimersByTimeAsync(100)
  return pending
}

describe('the params table', () => {
  it('it_has_a_params_entry_for_every_method_and_nothing_else', () => {
    expect(Object.keys(minimalParams).sort()).toEqual(typeKeys('BridgeMethods').sort())
  })

  it('it_gives_every_allow_list_entry_a_reason', () => {
    for (const list of [unhandledMethods, unsentEvents]) {
      for (const [name, reason] of Object.entries(list)) {
        expect(reason.trim(), `the allow list entry ${name} needs a reason`).not.toBe('')
      }
    }
  })
})

describe('the methods', () => {
  // A method with no handler makes the fake call `undefined(...)`, which rejects with a TypeError. A handler that
  // refuses on purpose rejects with a BridgeError instead.
  it('it_handles_every_method_the_page_may_call', async () => {
    const names = typeKeys('BridgeMethods').filter((name) => !(name in unhandledMethods))
    expect(names.length).toBeGreaterThan(20)
    const unhandled: string[] = []
    for (const name of names) {
      bridge = createFakeBridge()
      const result = await outcome(name, minimalParams[name as BridgeMethod] ?? {})
      if ('error' in result && !(result.error instanceof BridgeError)) {
        unhandled.push(`${name} (${result.error instanceof Error ? result.error.message : String(result.error)})`)
      }
    }
    expect(unhandled, `The fake bridge has no working handler for: ${unhandled.join(', ')}`).toEqual([])
  })

  it('it_answers_an_unknown_method_with_a_plain_error_not_a_bridge_error', async () => {
    // Pins how the fake reports a method it does not know, so the check above stays honest.
    const result = await outcome('nothing.here', {})
    expect('error' in result && result.error instanceof TypeError).toBe(true)
  })
})

describe('the events', () => {
  it('it_sends_every_event_the_app_can_send', () => {
    const names = typeKeys('BridgeEvents').filter((name) => !(name in unsentEvents))
    expect(names.length).toBeGreaterThan(5)
    const emitted = new Set<string>()
    for (const match of fakeSource.matchAll(/\bemit\(\s*'([a-z]+(?:\.[a-z]+)+)'/g)) {
      const name = match[1]
      if (name) emitted.add(name)
    }
    const missing = names.filter((name) => !emitted.has(name))
    expect(missing, `No emit('name', ...) call in fakeBridge.ts for: ${missing.join(', ')}`).toEqual([])
  })

  it('it_only_sends_events_that_types_knows', () => {
    const known = typeKeys('BridgeEvents')
    const unknown: string[] = []
    for (const match of fakeSource.matchAll(/\bemit\(\s*'([a-z]+(?:\.[a-z]+)+)'/g)) {
      const name = match[1]
      if (name && !known.includes(name)) unknown.push(name)
    }
    expect(unknown).toEqual([])
  })

  it('it_delivers_an_event_to_a_listener_through_the_dev_helpers', async () => {
    // One live check that the emit path works: the dev helper sends item.focus.
    const received: string[] = []
    const name: BridgeEventName = 'item.focus'
    bridge.on(name, (data) => received.push(data.id))
    ;(globalThis as unknown as { pointrooDev: { focusItem(id: string): void } }).pointrooDev.focusItem('abc')
    await vi.advanceTimersByTimeAsync(10)
    expect(received).toEqual(['abc'])
  })
})
