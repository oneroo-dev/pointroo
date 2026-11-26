// F2: the Setup checklist, the Wake group, the wake note on items and the hint toast. The view model turns what the app sends into
// the words of the approved mockups; the store keeps the rows, runs the actions and shows the hints.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

// The store and the bridge file read `window` when they load, and this runs in plain node.
vi.hoisted(() => {
  ;(globalThis as { window?: unknown }).window = globalThis
})

import type { Bridge } from './bridge'
import { BridgeError } from './bridgeError'
import { createStore } from './store'
import type { BridgeEventName, BridgeEvents, BridgeItem, BridgeSetupRow, BridgeWakeSettings } from './types'
import { toSetupRows, toViewItem, toWakeNote, toWakeSettings } from './viewModel'

type Handler = (params: unknown) => unknown

function createStub(overrides: Record<string, Handler> = {}) {
  const calls: { method: string; params: unknown }[] = []
  const listeners = new Map<string, Set<(data: unknown) => void>>()
  const defaults: Record<string, Handler> = {
    'items.list': () => ({ groups: [] }),
    'done.recent': () => ({ items: [] }),
    'projects.list': () => ({ projects: [] }),
    'questions.list': () => ({ questions: [] }),
    'status.get': () => ({ status: { mcpRunning: true, mcpPort: 6742, mcpText: 'running', sessions: 1, agents: [], microphone: true, screenRecording: true, accessibility: true, autoRuns: [] } }),
    'recording.get': () => ({ phase: 'idle', points: 0 }),
    'picker.get': () => ({ open: false }),
    'notices.list': () => ({ notices: [] }),
  }
  const bridge: Bridge = {
    call(method, params) {
      calls.push({ method, params })
      const handler = overrides[method] ?? defaults[method]
      if (handler === undefined) return Promise.reject(new BridgeError('unknown_method', 'No such method.')) as never
      try {
        return Promise.resolve(handler(params)) as never
      } catch (error) {
        return Promise.reject(error) as never
      }
    },
    on(name, listener) {
      const set = listeners.get(name) ?? new Set<(data: unknown) => void>()
      set.add(listener as (data: unknown) => void)
      listeners.set(name, set)
      return () => {
        set.delete(listener as (data: unknown) => void)
      }
    },
  }
  function emit<Name extends BridgeEventName>(name: Name, data: BridgeEvents[Name]): void {
    listeners.get(name)?.forEach((listener) => listener(data))
  }
  return { bridge, emit, callsTo: (method: string) => calls.filter((call) => call.method === method) }
}

async function flush(): Promise<void> {
  await vi.advanceTimersByTimeAsync(0)
}

beforeEach(() => {
  vi.useFakeTimers()
})

afterEach(() => {
  vi.useRealTimers()
})

const freshRows: BridgeSetupRow[] = [
  { id: 'applications', state: 'todo', action: 'move' },
  { id: 'microphone', state: 'todo', action: 'allowMicrophone' },
  { id: 'screenRecording', state: 'todo', detail: 'denied', action: 'openScreenRecordingSettings' },
  { id: 'accessibility', state: 'done' },
  { id: 'claudeCode', state: 'todo', action: 'install' },
  { id: 'tool', state: 'todo', action: 'connect' },
  { id: 'stopHook', state: 'todo', action: 'addHook' },
  { id: 'speech', state: 'busy' },
  { id: 'wake', state: 'todo', action: 'updateClaude' },
]

const greenRows: BridgeSetupRow[] = freshRows.map((row) => ({ id: row.id, state: 'done' }))

function bridgeItem(wake?: BridgeItem['wake']): BridgeItem {
  const item: BridgeItem = { id: 'a#1', session: 'a', n: 1, title: 'Fix it', body: 'body', crops: [], cropURLs: [], status: 'open', alsoSaid: [], project: '/w/tinkeroo' }
  if (wake !== undefined) item.wake = wake
  return item
}

describe('toSetupRows', () => {
  it('it_uses_the_words_of_the_fresh_mockup_for_rows_that_are_not_done', () => {
    const rows = toSetupRows(freshRows)
    expect(rows.map((row) => [row.id, row.state, row.actionLabel ?? row.busyLabel])).toEqual([
      ['applications', 'todo', 'Move to Applications'],
      ['microphone', 'todo', 'Allow'],
      ['screenRecording', 'todo', 'Open System Settings'],
      ['accessibility', 'done', undefined],
      ['claudeCode', 'todo', 'Install Claude Code'],
      ['tool', 'todo', 'Connect'],
      ['stopHook', 'todo', 'Add'],
      ['speech', 'busy', 'Downloading...'],
      ['wake', 'todo', 'Update Claude Code for auto-wake'],
    ])
    expect(rows[2]?.description).toBe('You said no before. Turn it on in System Settings.')
    expect(rows[4]?.description).toBe('Not found.')
    expect(rows[5]?.note).toBe('Restart open Claude sessions to see it.')
  })

  it('it_uses_the_words_of_the_ready_mockup_when_every_row_is_done', () => {
    const rows = toSetupRows(greenRows)
    expect(rows.map((row) => row.doneLabel)).toEqual(['Yes', 'Allowed', 'Allowed', 'Allowed', 'Found', 'Added', 'Added', 'Ready', 'Yes'])
    expect(rows[8]?.description).toBe('Version 2.1.224 or newer.')
  })

  it('it_gives_a_failed_speech_download_a_retry_button', () => {
    const [row] = toSetupRows([{ id: 'speech', state: 'todo', detail: 'failed', action: 'retrySpeech' }])
    expect(row).toMatchObject({ description: 'The download did not finish.', state: 'todo', actionLabel: 'Retry' })
  })
})

describe('the wake note and the Wake group', () => {
  it('it_maps_each_wake_result_to_a_note', () => {
    expect(toWakeNote({ result: 'sent', name: 'Tinkeroo' })).toEqual({ kind: 'woke', name: 'Tinkeroo' })
    expect(toWakeNote({ result: 'listening' })).toEqual({ kind: 'busy' })
    expect(toWakeNote({ result: 'no owner' })).toEqual({ kind: 'no-session' })
    expect(toWakeNote({ result: 'claude code too old for wake (needs 2.1.224+)' })).toEqual({ kind: 'too-old' })
    expect(toWakeNote({ result: 'failed: could not connect' })).toEqual({ kind: 'no-session' })
    expect(toWakeNote(undefined)).toBeUndefined()
  })

  it('it_puts_the_wake_note_on_the_item_only_when_the_app_sent_one', () => {
    const now = new Date()
    expect(toViewItem(bridgeItem({ result: 'sent', name: 'Tinkeroo' }), undefined, now).wake).toEqual({ kind: 'woke', name: 'Tinkeroo' })
    expect(toViewItem(bridgeItem(), undefined, now).wake).toBeUndefined()
  })

  it('it_builds_the_wake_group_with_the_last_wake_line', () => {
    const wake: BridgeWakeSettings = {
      enabled: true,
      owners: [{ project: 'Tinkeroo', owner: 'auto' }],
      sessions: [{ id: 's1', name: 'Tinkeroo' }],
      last: { project: 'tinkeroo', name: 'Tinkeroo', at: new Date(Date.now() - 120000).toISOString() },
    }
    const view = toWakeSettings(wake, new Date())
    expect(view.owners).toEqual([{ projectId: 'Tinkeroo', name: 'Tinkeroo', owner: 'auto' }])
    expect(view.sessions).toEqual([{ value: 's1', label: 'Tinkeroo' }])
    expect(view.lastWake).toBe('Last: woke Tinkeroo for tinkeroo, 2 min ago')
    expect(toWakeSettings({ enabled: false, owners: [], sessions: [] }, new Date()).lastWake).toBeUndefined()
  })
})

describe('the store and Setup', () => {
  it('it_reads_setup_status_at_start_and_shows_the_card_on_a_fresh_install', async () => {
    const stub = createStub({ 'setup.status': () => ({ rows: freshRows }) })
    const store = createStore(stub.bridge)
    const stop = store.start()
    await flush()
    expect(store.setupRows.length).toBe(9)
    expect(store.showSetup).toBe(true)
    stop()
  })

  it('it_hides_the_card_once_every_row_is_done_by_setup_changed', async () => {
    const stub = createStub({ 'setup.status': () => ({ rows: freshRows }) })
    const store = createStore(stub.bridge)
    const stop = store.start()
    await flush()
    stub.emit('setup.changed', { rows: greenRows })
    expect(store.showSetup).toBe(false)
    stop()
  })

  it('it_hides_the_card_when_there_are_items_or_Settings_is_open', async () => {
    const withItem = createStub({ 'setup.status': () => ({ rows: freshRows }), 'items.list': () => ({ groups: [{ project: null, items: [bridgeItem()] }] }) })
    const first = createStore(withItem.bridge)
    const stopFirst = first.start()
    await flush()
    expect(first.showSetup).toBe(false)
    stopFirst()
    const empty = createStub({ 'setup.status': () => ({ rows: freshRows }) })
    const second = createStore(empty.bridge)
    const stopSecond = second.start()
    await flush()
    await second.openSettings()
    expect(second.showSetup).toBe(false)
    stopSecond()
  })

  it('it_shows_nothing_when_the_app_has_no_setup_status', async () => {
    const stub = createStub()
    const store = createStore(stub.bridge)
    const stop = store.start()
    await flush()
    expect(store.setupRows).toEqual([])
    expect(store.showSetup).toBe(false)
    stop()
  })

  it('it_runs_the_action_the_app_named_for_the_row_and_takes_the_new_rows', async () => {
    const stub = createStub({ 'setup.status': () => ({ rows: freshRows }), 'setup.action': () => ({ rows: greenRows }) })
    const store = createStore(stub.bridge)
    const stop = store.start()
    await flush()
    await store.runSetup('stopHook')
    expect(stub.callsTo('setup.action')[0]?.params).toEqual({ id: 'addHook' })
    expect(store.showSetup).toBe(false)
    await store.runSetup('accessibility')
    expect(stub.callsTo('setup.action').length).toBe(1)
    stop()
  })

  it('it_shows_a_toast_when_an_action_fails', async () => {
    const stub = createStub({
      'setup.status': () => ({ rows: freshRows }),
      'setup.action': () => {
        throw new BridgeError('not_available', 'Setup actions are not available.')
      },
    })
    const store = createStore(stub.bridge)
    const stop = store.start()
    await flush()
    await store.runSetup('tool')
    expect(store.toast?.tone).toBe('warn')
    stop()
  })
})

describe('the store and Wake', () => {
  const wake: BridgeWakeSettings = { enabled: true, owners: [{ project: 'Tinkeroo', owner: 'auto' }], sessions: [{ id: 's1', name: 'Tinkeroo' }] }

  it('it_loads_wake_when_settings_open', async () => {
    const stub = createStub({ 'wake.get': () => wake })
    const store = createStore(stub.bridge)
    expect(store.wake).toBeUndefined()
    await store.openSettings()
    expect(store.wake?.enabled).toBe(true)
    expect(store.wake?.owners[0]?.name).toBe('Tinkeroo')
  })

  it('it_sends_the_switch_and_an_owner_change_and_keeps_the_answer', async () => {
    const stub = createStub({
      'wake.get': () => wake,
      'wake.set': (params) => {
        const change = params as { enabled?: boolean; owners?: { project: string; owner: string }[] }
        return { ...wake, enabled: change.enabled ?? wake.enabled, owners: change.owners ?? wake.owners }
      },
    })
    const store = createStore(stub.bridge)
    await store.openSettings()
    await store.setWakeEnabled(false)
    expect(stub.callsTo('wake.set')[0]?.params).toEqual({ enabled: false })
    expect(store.wake?.enabled).toBe(false)
    await store.setWakeOwner('Tinkeroo', 's1')
    expect(stub.callsTo('wake.set')[1]?.params).toEqual({ owners: [{ project: 'Tinkeroo', owner: 's1' }] })
    expect(store.wake?.owners[0]?.owner).toBe('s1')
  })

  it('it_leaves_the_wake_group_out_when_the_app_cannot_answer', async () => {
    const stub = createStub()
    const store = createStore(stub.bridge)
    await store.openSettings()
    expect(store.wake).toBeUndefined()
  })

  it('it_shows_a_toast_and_reads_again_when_wake_set_fails', async () => {
    const stub = createStub({
      'wake.get': () => wake,
      'wake.set': () => {
        throw new BridgeError('not_available', 'Could not save the owners.')
      },
    })
    const store = createStore(stub.bridge)
    await store.openSettings()
    await store.setWakeEnabled(false)
    expect(store.toast?.tone).toBe('warn')
    expect(store.wake?.enabled).toBe(true)
    expect(stub.callsTo('wake.get').length).toBe(2)
  })
})

describe('hints', () => {
  it('it_shows_a_hint_as_a_toast_without_undo', async () => {
    const stub = createStub()
    const store = createStore(stub.bridge)
    const stop = store.start()
    await flush()
    stub.emit('hint.show', { message: 'Not sent: no Claude session open.', tone: 'warn' })
    expect(store.toast).toEqual({ message: 'Not sent: no Claude session open.', tone: 'warn', undo: false })
    await vi.advanceTimersByTimeAsync(8100)
    expect(store.toast).toBeUndefined()
    stop()
  })

  it('it_runs_the_action_of_a_hint_with_a_button_and_closes_the_toast', async () => {
    const stub = createStub({ 'setup.action': () => ({ rows: freshRows }) })
    const store = createStore(stub.bridge)
    const stop = store.start()
    await flush()
    stub.emit('hint.show', { message: 'Speech download failed.', tone: 'warn', actionLabel: 'Retry', action: 'retrySpeech' })
    expect(store.toast?.actionLabel).toBe('Retry')
    await store.runHintAction()
    expect(stub.callsTo('setup.action')[0]?.params).toEqual({ id: 'retrySpeech' })
    expect(store.toast).toBeUndefined()
    stop()
  })

  it('it_does_nothing_on_the_button_after_an_ordinary_toast_replaced_the_hint', async () => {
    const stub = createStub()
    const store = createStore(stub.bridge)
    const stop = store.start()
    await flush()
    stub.emit('hint.show', { message: 'Speech download failed.', tone: 'warn', actionLabel: 'Retry', action: 'retrySpeech' })
    store.showToast('Copied', 'ok', false)
    await store.runHintAction()
    expect(stub.callsTo('setup.action').length).toBe(0)
    stop()
  })
})
