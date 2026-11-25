// The store drives recording, the picker, notices and search through the bridge. These tests use a small stub bridge that
// writes down every call, and the fake bridge for the whole flow. Timers are fake, so nothing really waits.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

// The store and the bridge file read `window` when they load, and this runs in plain node.
vi.hoisted(() => {
  ;(globalThis as { window?: unknown }).window = globalThis
})

import type { Bridge } from './bridge'
import { BridgeError } from './bridgeError'
import { createFakeBridge } from './fakeBridge'
import { createStore } from './store'
import type { BridgeEventName, BridgeEvents, BridgeItem, Notice, SearchResult } from './types'

type Handler = (params: unknown) => unknown

interface Call {
  method: string
  params: unknown
}

const searchDelay = 200

function createStubBridge(overrides: Record<string, Handler> = {}) {
  const calls: Call[] = []
  const listeners = new Map<string, Set<(data: unknown) => void>>()
  const defaults: Record<string, Handler> = {
    'items.list': () => ({ groups: [] }),
    'done.recent': () => ({ items: [] }),
    'projects.list': () => ({ projects: [] }),
    'questions.list': () => ({ questions: [] }),
    'status.get': () => ({
      status: { mcpRunning: true, mcpPort: 6742, mcpText: 'running', sessions: 1, agents: [], microphone: true, screenRecording: true, accessibility: true, autoRuns: [] },
    }),
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
  function callsTo(method: string): Call[] {
    return calls.filter((call) => call.method === method)
  }
  return { bridge, calls, callsTo, emit }
}

async function flush(): Promise<void> {
  await vi.advanceTimersByTimeAsync(0)
}

/** The fake bridge answers after a (fake) timer, so time must run while the call is awaited. */
async function settle(promise: Promise<void>): Promise<void> {
  await vi.advanceTimersByTimeAsync(500)
  await promise
}

function searchResult(id: string, title: string): SearchResult {
  return {
    id,
    session: 'sample',
    n: 1,
    title,
    body: title,
    crops: [],
    cropURLs: [],
    status: 'open',
    alsoSaid: [],
    match: { field: 'title', snippet: title },
  }
}

beforeEach(() => {
  vi.useFakeTimers()
})

afterEach(() => {
  vi.useRealTimers()
})

describe('recording', () => {
  it('it_starts_a_recording_with_no_params_when_there_is_no_follow_up', async () => {
    const stub = createStubBridge({ 'recording.start': () => ({ started: true }) })
    const store = createStore(stub.bridge)
    await store.startRecording()
    expect(stub.callsTo('recording.start')).toEqual([{ method: 'recording.start', params: {} }])
  })

  it('it_sends_followUp_when_saying_more_on_an_item', async () => {
    const stub = createStubBridge({ 'recording.start': () => ({ started: true, followUp: 'a5' }) })
    const store = createStore(stub.bridge)
    await store.sayMore('a5')
    expect(stub.callsTo('recording.start')).toEqual([{ method: 'recording.start', params: { followUp: 'a5' } }])
  })

  it('it_calls_recording_stop_and_recording_cancel', async () => {
    const stub = createStubBridge({ 'recording.stop': () => ({ stopped: true }), 'recording.cancel': () => ({ cancelled: true }) })
    const store = createStore(stub.bridge)
    await store.stopRecording()
    await store.cancelRecording()
    expect(stub.callsTo('recording.stop')).toEqual([{ method: 'recording.stop', params: {} }])
    expect(stub.callsTo('recording.cancel')).toEqual([{ method: 'recording.cancel', params: {} }])
  })

  it('it_shows_the_busy_error_as_a_toast', async () => {
    const stub = createStubBridge({
      'recording.start': () => {
        throw new BridgeError('busy', 'A recording is already running.')
      },
    })
    const store = createStore(stub.bridge)
    await store.startRecording()
    expect(store.toast?.message).toBe('A recording is already running.')
    expect(store.toast?.tone).toBe('warn')
  })

  it('it_shows_bad_params_for_a_follow_up_that_is_not_allowed', async () => {
    const stub = createStubBridge({
      'recording.start': () => {
        throw new BridgeError('bad_params', 'followUp must be a done item that went to a project.')
      },
    })
    const store = createStore(stub.bridge)
    await store.sayMore('open-item')
    expect(store.toast?.message).toBe('followUp must be a done item that went to a project.')
  })

  it('it_updates_phase_and_points_on_recording_changed_and_reads_startedAt', async () => {
    const stub = createStubBridge({ 'recording.get': () => ({ phase: 'recording', points: 2, startedAt: '2026-11-24T09:31:00.000Z' }) })
    const store = createStore(stub.bridge)
    const stop = store.start()
    await flush()
    stub.emit('recording.changed', { phase: 'recording', pointCount: 2 })
    await flush()
    expect(store.recording.phase).toBe('recording')
    expect(store.recording.pointCount).toBe(2)
    expect(store.recording.startedAt).toBe('2026-11-24T09:31:00.000Z')
    stub.emit('recording.changed', { phase: 'processing', pointCount: 2 })
    await flush()
    expect(store.recording.phase).toBe('processing')
    expect(store.recording.startedAt).toBeUndefined()
    stop()
  })
})

describe('picker', () => {
  const openReply = {
    open: true,
    session: '2026-11-24-0931',
    choices: [
      { name: 'Tinkeroo', path: '~/Workspace/tinkeroo', key: 1, suggested: true },
      { name: 'Pointroo', path: '~/Workspace/pointroo', key: 2, suggested: false },
    ],
    countdown: 8,
  }

  it('it_reads_picker_get_when_picker_changed_arrives', async () => {
    let reply: unknown = openReply
    const stub = createStubBridge({ 'picker.get': () => reply })
    const store = createStore(stub.bridge)
    const stop = store.start()
    await flush()
    stub.emit('picker.changed', { open: true, session: '2026-11-24-0931' })
    await flush()
    expect(store.picker?.choices.map((choice) => choice.name)).toEqual(['Tinkeroo', 'Pointroo'])
    expect(store.picker?.countdown).toBe(8)
    reply = { open: false }
    stub.emit('picker.changed', { open: false })
    await flush()
    expect(store.picker).toBeNull()
    stop()
  })

  it('it_picks_a_project_by_path_and_closes_the_picker', async () => {
    const stub = createStubBridge({ 'picker.get': () => openReply, 'picker.pick': () => ({ picked: true }) })
    const store = createStore(stub.bridge)
    await store.loadPicker()
    expect(store.picker).not.toBeNull()
    await store.pickProject('~/Workspace/pointroo')
    expect(stub.callsTo('picker.pick')).toEqual([{ method: 'picker.pick', params: { path: '~/Workspace/pointroo' } }])
    expect(store.picker).toBeNull()
  })

  it('it_skips_the_picker', async () => {
    const stub = createStubBridge({ 'picker.get': () => openReply, 'picker.skip': () => ({ skipped: true }) })
    const store = createStore(stub.bridge)
    await store.loadPicker()
    await store.skipPicker()
    expect(stub.callsTo('picker.skip')).toEqual([{ method: 'picker.skip', params: {} }])
    expect(store.picker).toBeNull()
  })

  it('it_shows_not_found_and_reads_the_picker_again_when_it_was_answered_already', async () => {
    let reply: unknown = openReply
    const stub = createStubBridge({
      'picker.get': () => reply,
      'picker.pick': () => {
        reply = { open: false }
        throw new BridgeError('not_found', 'No picker is open.')
      },
    })
    const store = createStore(stub.bridge)
    await store.loadPicker()
    await store.pickProject('~/Workspace/pointroo')
    expect(store.toast?.message).toBe('No picker is open.')
    expect(store.picker).toBeNull()
  })
})

describe('notices', () => {
  const doneNotice: Notice = { kind: 'done', id: 'a7', agent: 'Claude Code', projectName: 'Tinkeroo', note: 'Moved Delete.' }
  const questionNotice: Notice = { kind: 'question', id: 'q1', project: 'Tinkeroo', agent: 'Claude Code', text: 'Ask first?', choices: ['Yes', 'No'], asked: 1700000000 }

  it('it_reloads_the_list_when_notices_changed_arrives', async () => {
    let list: Notice[] = []
    const stub = createStubBridge({ 'notices.list': () => ({ notices: list }) })
    const store = createStore(stub.bridge)
    const stop = store.start()
    await flush()
    expect(store.noticeCount).toBe(0)
    list = [doneNotice, questionNotice]
    stub.emit('notices.changed', { count: 2 })
    await flush()
    expect(store.notices).toEqual([doneNotice, questionNotice])
    expect(store.noticeCount).toBe(2)
    stop()
  })

  it('it_sends_the_ids_to_notices_seen_and_reads_the_list_again', async () => {
    let list: Notice[] = [doneNotice, questionNotice]
    const stub = createStubBridge({
      'notices.list': () => ({ notices: list }),
      'notices.seen': () => {
        list = [questionNotice]
        return { seen: 1 }
      },
    })
    const store = createStore(stub.bridge)
    await store.loadNotices()
    await store.markNoticesSeen(['a7'])
    expect(stub.callsTo('notices.seen')).toEqual([{ method: 'notices.seen', params: { ids: ['a7'] } }])
    expect(store.notices).toEqual([questionNotice])
  })

  it('it_does_not_call_notices_seen_with_no_ids', async () => {
    const stub = createStubBridge()
    const store = createStore(stub.bridge)
    await store.markNoticesSeen([])
    expect(stub.callsTo('notices.seen')).toEqual([])
  })

  it('it_shows_a_toast_when_notices_seen_fails', async () => {
    const stub = createStubBridge({
      'notices.seen': () => {
        throw new BridgeError('bad_params', 'ids is not a list of text.')
      },
    })
    const store = createStore(stub.bridge)
    await store.markNoticesSeen(['a7'])
    expect(store.toast?.message).toBe('ids is not a list of text.')
  })
})

describe('automatic send', () => {
  const sent: BridgeEvents['route.sent'] = { session: 's1', project: '/work/pointroo', projectName: 'Pointroo', how: 'said', ids: ['s1#1', 's1#2'] }

  it('it_keeps_lastSent_for_six_seconds_and_then_clears_it', async () => {
    const stub = createStubBridge()
    const store = createStore(stub.bridge)
    const stop = store.startFloating()
    await flush()
    expect(store.lastSent).toBeUndefined()
    stub.emit('route.sent', sent)
    expect(store.lastSent).toEqual(sent)
    await vi.advanceTimersByTimeAsync(5900)
    expect(store.lastSent).toEqual(sent)
    await vi.advanceTimersByTimeAsync(200)
    expect(store.lastSent).toBeUndefined()
    stop()
  })

  it('it_shows_the_same_recording_only_once', async () => {
    const stub = createStubBridge()
    const store = createStore(stub.bridge)
    const stop = store.startFloating()
    stub.emit('route.sent', sent)
    await vi.advanceTimersByTimeAsync(7000)
    expect(store.lastSent).toBeUndefined()
    stub.emit('route.sent', sent)
    expect(store.lastSent).toBeUndefined()
    stop()
  })

  it('it_calls_items_unroute_for_each_id_on_undo_and_hides_the_pill', async () => {
    const stub = createStubBridge({ 'items.unroute': () => ({ unrouted: true }) })
    const store = createStore(stub.bridge)
    const stop = store.startFloating()
    stub.emit('route.sent', sent)
    await store.undoSent()
    expect(stub.callsTo('items.unroute')).toEqual([
      { method: 'items.unroute', params: { id: 's1#1' } },
      { method: 'items.unroute', params: { id: 's1#2' } },
    ])
    expect(store.lastSent).toBeUndefined()
    stop()
  })

  it('it_calls_route_change_with_the_session_on_change_and_hides_the_pill', async () => {
    const stub = createStubBridge({ 'route.change': () => ({ opened: true }) })
    const store = createStore(stub.bridge)
    const stop = store.startFloating()
    stub.emit('route.sent', sent)
    await store.changeSent()
    expect(stub.callsTo('route.change')).toEqual([{ method: 'route.change', params: { session: 's1' } }])
    expect(store.lastSent).toBeUndefined()
    stop()
  })

  it('it_does_nothing_on_change_when_nothing_was_sent', async () => {
    const stub = createStubBridge()
    const store = createStore(stub.bridge)
    await store.changeSent()
    expect(stub.callsTo('route.change')).toEqual([])
  })

  it('it_shows_the_error_when_change_is_refused', async () => {
    const stub = createStubBridge({
      'route.change': () => {
        throw new BridgeError('busy', 'A project picker is already open.')
      },
    })
    const store = createStore(stub.bridge)
    const stop = store.startFloating()
    stub.emit('route.sent', sent)
    await store.changeSent()
    expect(store.toast?.message).toBe('A project picker is already open.')
    stop()
  })

  it('it_does_nothing_on_undo_when_nothing_was_sent', async () => {
    const stub = createStubBridge()
    const store = createStore(stub.bridge)
    await store.undoSent()
    expect(stub.callsTo('items.unroute')).toEqual([])
  })

  it('it_clears_lastSent_when_a_new_recording_starts', async () => {
    const stub = createStubBridge()
    const store = createStore(stub.bridge)
    const stop = store.startFloating()
    stub.emit('route.sent', sent)
    expect(store.lastSent).toEqual(sent)
    stub.emit('recording.changed', { phase: 'recording', pointCount: 0 })
    expect(store.lastSent).toBeUndefined()
    stop()
  })
})

describe('question card calls', () => {
  const question = { id: 'q1', text: 'Which?', choices: ['Yes', 'No'] }

  it('it_sends_the_chosen_text_to_questions_answer', async () => {
    const stub = createStubBridge({ 'questions.answer': () => ({ answered: true }) })
    const store = createStore(stub.bridge)
    await store.answer(question, 'No')
    expect(stub.callsTo('questions.answer')).toEqual([{ method: 'questions.answer', params: { id: 'q1', text: 'No' } }])
  })

  it('it_sends_later_to_questions_later', async () => {
    const stub = createStubBridge({ 'questions.later': () => ({ snoozed: true, until: 1 }) })
    const store = createStore(stub.bridge)
    await store.later(question)
    expect(stub.callsTo('questions.later')).toEqual([{ method: 'questions.later', params: { id: 'q1', minutes: 30 } }])
  })
})

describe('search', () => {
  it('it_waits_200_milliseconds_and_asks_once_with_the_last_text', async () => {
    const stub = createStubBridge({ 'items.search': () => ({ items: [searchResult('s1', 'Move delete away')] }) })
    const store = createStore(stub.bridge)
    void store.search('d')
    void store.search('del')
    const last = store.search('delete')
    await vi.advanceTimersByTimeAsync(searchDelay - 1)
    expect(stub.callsTo('items.search')).toEqual([])
    expect(store.searchState.loading).toBe(true)
    await vi.advanceTimersByTimeAsync(1)
    await last
    expect(stub.callsTo('items.search')).toEqual([{ method: 'items.search', params: { text: 'delete' } }])
    expect(store.searchState.query).toBe('delete')
    expect(store.searchState.results.map((result) => result.id)).toEqual(['s1'])
    expect(store.searchState.loading).toBe(false)
    expect(store.searchState.error).toBeUndefined()
  })

  it('it_uses_the_delay_it_was_given', async () => {
    const stub = createStubBridge({ 'items.search': () => ({ items: [] }) })
    const store = createStore(stub.bridge, { searchDelayMilliseconds: 10 })
    const done = store.search('delete')
    await vi.advanceTimersByTimeAsync(10)
    await done
    expect(stub.callsTo('items.search')).toHaveLength(1)
  })

  it('it_never_lets_a_slower_old_reply_replace_a_newer_one', async () => {
    let releaseOld: (value: unknown) => void = () => undefined
    const stub = createStubBridge({
      'items.search': (params) => {
        const text = (params as { text: string }).text
        if (text === 'del') return new Promise((resolve) => (releaseOld = resolve))
        return { items: [searchResult('new', 'Newer')] }
      },
    })
    const store = createStore(stub.bridge)
    const old = store.search('del')
    await vi.advanceTimersByTimeAsync(searchDelay)
    const newer = store.search('delete')
    await vi.advanceTimersByTimeAsync(searchDelay)
    await newer
    expect(store.searchState.results.map((result) => result.id)).toEqual(['new'])
    releaseOld({ items: [searchResult('old', 'Older')] })
    await old
    expect(store.searchState.results.map((result) => result.id)).toEqual(['new'])
    expect(store.searchState.loading).toBe(false)
  })

  it('it_clears_the_results_and_asks_nothing_for_an_empty_query', async () => {
    const stub = createStubBridge({ 'items.search': () => ({ items: [searchResult('s1', 'Move delete away')] }) })
    const store = createStore(stub.bridge)
    const first = store.search('delete')
    await vi.advanceTimersByTimeAsync(searchDelay)
    await first
    expect(store.searchState.results).toHaveLength(1)
    await store.search('   ')
    await vi.advanceTimersByTimeAsync(searchDelay)
    expect(store.searchState.results).toEqual([])
    expect(store.searchState.loading).toBe(false)
    expect(stub.callsTo('items.search')).toHaveLength(1)
  })

  it('it_cuts_the_text_to_200_characters', async () => {
    const stub = createStubBridge({ 'items.search': () => ({ items: [] }) })
    const store = createStore(stub.bridge)
    const done = store.search('x'.repeat(250))
    await vi.advanceTimersByTimeAsync(searchDelay)
    await done
    expect(stub.callsTo('items.search')[0]?.params).toEqual({ text: 'x'.repeat(200) })
  })

  it('it_keeps_the_error_text_in_the_search_state', async () => {
    const stub = createStubBridge({
      'items.search': () => {
        throw new BridgeError('bad_params', 'text is 1 to 200 characters.')
      },
    })
    const store = createStore(stub.bridge)
    const done = store.search('delete')
    await vi.advanceTimersByTimeAsync(searchDelay)
    await done
    expect(store.searchState.error).toBe('text is 1 to 200 characters.')
    expect(store.searchState.results).toEqual([])
    expect(store.searchState.loading).toBe(false)
  })
})

describe('search screen', () => {
  it('it_passes_the_status_chip_as_the_status_param_and_leaves_it_out_for_all', async () => {
    const stub = createStubBridge({ 'items.search': () => ({ items: [] }) })
    const store = createStore(stub.bridge)
    const first = store.search('delete', 'open')
    await vi.advanceTimersByTimeAsync(searchDelay)
    await first
    const second = store.setSearchStatus('in_progress')
    await vi.advanceTimersByTimeAsync(searchDelay)
    await second
    const third = store.setSearchStatus('all')
    await vi.advanceTimersByTimeAsync(searchDelay)
    await third
    expect(stub.callsTo('items.search').map((call) => call.params)).toEqual([
      { text: 'delete', status: 'open' },
      { text: 'delete', status: 'in_progress' },
      { text: 'delete' },
    ])
    expect(store.searchState.status).toBe('all')
    expect(store.searchState.query).toBe('delete')
  })

  it('it_keeps_the_chosen_status_for_the_next_words', async () => {
    const stub = createStubBridge({ 'items.search': () => ({ items: [] }) })
    const store = createStore(stub.bridge)
    void store.setSearchStatus('done')
    const typed = store.search('trash')
    await vi.advanceTimersByTimeAsync(searchDelay)
    await typed
    expect(stub.callsTo('items.search').map((call) => call.params)).toEqual([{ text: 'trash', status: 'done' }])
  })

  it('it_resets_the_words_the_status_and_the_results_when_the_search_closes', async () => {
    const stub = createStubBridge({ 'items.search': () => ({ items: [searchResult('s1', 'Move delete away')] }) })
    const store = createStore(stub.bridge)
    store.openSearch()
    expect(store.searchOpen).toBe(true)
    const found = store.search('delete', 'open')
    await vi.advanceTimersByTimeAsync(searchDelay)
    await found
    expect(store.searchHits).toHaveLength(1)
    store.closeSearch()
    expect(store.searchOpen).toBe(false)
    expect(store.searchState.query).toBe('')
    expect(store.searchState.status).toBe('all')
    expect(store.searchState.results).toEqual([])
    expect(store.searchHits).toEqual([])
    expect(store.searchState.loading).toBe(false)
  })

  it('it_has_no_hits_and_no_error_when_nothing_matches', async () => {
    const stub = createStubBridge({ 'items.search': () => ({ items: [] }) })
    const store = createStore(stub.bridge)
    const found = store.search('fuzzy banner')
    await vi.advanceTimersByTimeAsync(searchDelay)
    await found
    expect(store.searchHits).toEqual([])
    expect(store.searchState.error).toBeUndefined()
    expect(store.searchState.loading).toBe(false)
  })

  it('it_gives_each_hit_the_item_and_where_the_words_were_found', async () => {
    const stub = createStubBridge({ 'items.search': () => ({ items: [searchResult('s1', 'Move delete away')] }) })
    const store = createStore(stub.bridge)
    const found = store.search('delete')
    await vi.advanceTimersByTimeAsync(searchDelay)
    await found
    expect(store.searchHits[0]?.item.title).toBe('Move delete away')
    expect(store.searchHits[0]?.match).toEqual({ field: 'title', snippet: 'Move delete away' })
  })

  it('it_opens_a_result_in_the_detail_and_closes_the_search', async () => {
    const stub = createStubBridge({ 'items.search': () => ({ items: [searchResult('s1', 'Move delete away')] }) })
    const store = createStore(stub.bridge)
    store.openSearch()
    const found = store.search('delete')
    await vi.advanceTimersByTimeAsync(searchDelay)
    await found
    store.openSearchResult('s1')
    expect(store.selectedId).toBe('s1')
    expect(store.selectedItem?.title).toBe('Move delete away')
    expect(store.searchOpen).toBe(false)
    expect(store.searchState.query).toBe('')
  })
})

describe('with the fake bridge', () => {
  it('it_goes_from_recording_to_the_picker_to_idle', async () => {
    const store = createStore(createFakeBridge())
    const stop = store.start()
    await vi.advanceTimersByTimeAsync(500)
    expect(store.recording.phase).toBe('idle')
    await settle(store.startRecording())
    expect(store.recording.phase).toBe('recording')
    expect(store.recording.startedAt).toBeDefined()
    await settle(store.stopRecording())
    expect(store.recording.phase).toBe('picking')
    const choice = store.picker?.choices[0]
    expect(choice).toBeDefined()
    await settle(store.pickProject(choice?.path ?? ''))
    expect(store.picker).toBeNull()
    expect(store.recording.phase).toBe('idle')
    stop()
  })

  it('it_says_busy_when_a_recording_is_already_running', async () => {
    const store = createStore(createFakeBridge())
    await settle(store.startRecording())
    await settle(store.startRecording())
    expect(store.toast?.message).toBe('A recording is running or being processed.')
  })

  it('it_finds_items_and_lists_and_clears_notices', async () => {
    const store = createStore(createFakeBridge())
    const found = store.search('delete')
    await vi.advanceTimersByTimeAsync(searchDelay + 500)
    await found
    expect(store.searchState.results.length).toBeGreaterThan(0)
    expect(store.searchState.results[0]?.match.snippet.length).toBeLessThanOrEqual(80)
    await settle(store.loadNotices())
    const doneIds = store.notices.flatMap((notice) => (notice.kind === 'done' ? [notice.id] : []))
    expect(doneIds.length).toBeGreaterThan(0)
    await settle(store.markNoticesSeen(doneIds))
    expect(store.notices.some((notice) => notice.kind === 'done')).toBe(false)
  })
})

describe('item.focus', () => {
  function bridgeItem(id: string, status: 'open' | 'done'): BridgeItem {
    return { id, session: 'sample', n: 1, title: `Item ${id}`, body: 'body', crops: [], cropURLs: [], status, alsoSaid: [] }
  }

  function listOf(...items: BridgeItem[]): Handler {
    return () => ({ groups: [{ project: null, items }] })
  }

  it('it_selects_a_queue_item_and_switches_to_the_tab_it_lives_in', async () => {
    const stub = createStubBridge({ 'items.list': listOf(bridgeItem('a#1', 'open'), bridgeItem('d#1', 'done')) })
    const store = createStore(stub.bridge)
    const stop = store.start()
    await flush()
    stub.emit('item.focus', { id: 'd#1' })
    await flush()
    expect(store.selectedId).toBe('d#1')
    expect(store.tab).toBe('done')
    stub.emit('item.focus', { id: 'a#1' })
    await flush()
    expect(store.selectedId).toBe('a#1')
    expect(store.tab).toBe('now')
    stop()
  })

  it('it_closes_search_and_settings', async () => {
    const stub = createStubBridge({ 'items.list': listOf(bridgeItem('a#1', 'open')) })
    const store = createStore(stub.bridge)
    const stop = store.start()
    await flush()
    store.openSearch()
    await store.openSettings()
    expect(store.searchOpen).toBe(true)
    expect(store.view).toBe('settings')
    stub.emit('item.focus', { id: 'a#1' })
    await flush()
    expect(store.searchOpen).toBe(false)
    expect(store.view).toBe('queue')
    expect(store.selectedId).toBe('a#1')
    stop()
  })

  it('it_loads_the_items_once_for_an_unknown_id_and_then_selects_it', async () => {
    let known = [bridgeItem('a#1', 'open')]
    const stub = createStubBridge({ 'items.list': () => ({ groups: [{ project: null, items: known }] }) })
    const store = createStore(stub.bridge)
    const stop = store.start()
    await flush()
    known = [bridgeItem('a#1', 'open'), bridgeItem('new#1', 'open')]
    const before = stub.callsTo('items.list').length
    stub.emit('item.focus', { id: 'new#1' })
    await flush()
    expect(stub.callsTo('items.list').length).toBe(before + 1)
    expect(store.selectedId).toBe('new#1')
    stop()
  })

  it('it_selects_nothing_and_shows_no_toast_when_the_id_is_still_missing', async () => {
    const stub = createStubBridge({ 'items.list': listOf(bridgeItem('a#1', 'open')) })
    const store = createStore(stub.bridge)
    const stop = store.start()
    await flush()
    stub.emit('item.focus', { id: 'gone#1' })
    await flush()
    expect(store.selectedId).toBeUndefined()
    expect(store.toast).toBeUndefined()
    stop()
  })
})

describe('choosing a project from the menu', () => {
  const pointroo = { name: 'pointroo', path: '/work/pointroo', aliases: [], live: true, agents: [], open: 1, inProgress: 0 }
  const shellroo = { name: 'shellroo', path: '/work/shellroo', aliases: [], live: false, agents: [], open: 0, inProgress: 0 }

  function routedItem(project: string | undefined): BridgeItem {
    const item: BridgeItem = { id: 'a#1', session: 'sample', n: 1, title: 'Item a', body: 'body', crops: [], cropURLs: [], status: 'open', alsoSaid: [] }
    if (project !== undefined) item.project = project
    return item
  }

  function setup(project: string | undefined) {
    const stub = createStubBridge({
      'items.list': () => ({ groups: [{ project: null, items: [routedItem(project)] }] }),
      'projects.list': () => ({ projects: [pointroo, shellroo] }),
      'items.reroute': () => ({ moved: true }),
      'items.unroute': () => ({ unrouted: true }),
    })
    return { stub, store: createStore(stub.bridge) }
  }

  it('it_moves_an_item_that_holds_a_folder_path_to_the_picked_project', async () => {
    const { stub, store } = setup('/work/pointroo')
    await store.refresh()
    await store.send(['a#1'], '/work/shellroo')
    expect(stub.callsTo('items.reroute')).toEqual([{ method: 'items.reroute', params: { id: 'a#1', project: '/work/shellroo' } }])
    expect(store.toast?.message).toBe('Moved to shellroo')
  })

  it('it_sends_a_not_sent_item_and_undo_unroutes_it', async () => {
    const { stub, store } = setup(undefined)
    await store.refresh()
    await store.send(['a#1'], '/work/pointroo')
    expect(store.toast?.message).toBe('Sent to pointroo')
    await store.undo()
    expect(stub.callsTo('items.unroute')).toEqual([{ method: 'items.unroute', params: { id: 'a#1' } }])
  })

  it('it_puts_a_moved_item_back_on_undo_even_when_the_old_project_was_a_folder_path', async () => {
    const { stub, store } = setup('/work/pointroo')
    await store.refresh()
    await store.send(['a#1'], '/work/shellroo')
    await store.undo()
    expect(stub.callsTo('items.reroute')[1]).toEqual({ method: 'items.reroute', params: { id: 'a#1', project: '/work/pointroo' } })
  })

  it('it_keeps_the_rows_of_the_project_filter_when_items_hold_folder_paths', async () => {
    const { store } = setup('/work/pointroo')
    await store.refresh()
    store.filter = '/work/pointroo'
    expect(store.rows.map((row) => row.id)).toEqual(['a#1'])
    store.filter = '/work/shellroo'
    expect(store.rows).toEqual([])
  })
})

describe('new recordings', () => {
  function bridgeItem(id: string, at?: string): BridgeItem {
    const item: BridgeItem = { id, session: 'sample', n: 1, title: `Item ${id}`, body: 'body', crops: [], cropURLs: [], status: 'open', alsoSaid: [] }
    if (at !== undefined) item.at = at
    return item
  }

  function setup() {
    let current = [bridgeItem('a#1', '2026-11-24T10:00:00Z')]
    const stub = createStubBridge({ 'items.list': () => ({ groups: [{ project: null, items: current }] }) })
    const store = createStore(stub.bridge)
    return {
      store,
      setItems(items: BridgeItem[]) {
        current = items
      },
    }
  }

  it('it_selects_nothing_on_the_first_load', async () => {
    const { store } = setup()
    const stop = store.start()
    await flush()
    expect(store.selectedId).toBeUndefined()
    stop()
  })

  it('it_selects_a_new_open_item_that_a_refresh_brings', async () => {
    const { store, setItems } = setup()
    const stop = store.start()
    await flush()
    setItems([bridgeItem('a#1', '2026-11-24T10:00:00Z'), bridgeItem('b#1', '2026-11-26T09:31:00Z')])
    await settle(store.refresh())
    expect(store.selectedId).toBe('b#1')
    stop()
  })

  it('it_keeps_the_selection_when_a_refresh_has_only_known_items', async () => {
    const { store, setItems } = setup()
    const stop = store.start()
    await flush()
    store.select('a#1')
    setItems([bridgeItem('a#1', '2026-11-24T10:00:00Z')])
    await settle(store.refresh())
    expect(store.selectedId).toBe('a#1')
    stop()
  })

  it('it_does_not_change_the_selection_while_settings_are_open', async () => {
    const { store, setItems } = setup()
    const stop = store.start()
    await flush()
    store.select('a#1')
    await store.openSettings()
    setItems([bridgeItem('a#1', '2026-11-24T10:00:00Z'), bridgeItem('b#1', '2026-11-26T09:31:00Z')])
    await settle(store.refresh())
    expect(store.selectedId).toBe('a#1')
    stop()
  })
})
