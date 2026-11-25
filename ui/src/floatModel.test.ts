// What the three floating panels show: the route names, then the pill, the picker and the notice card worked out from the
// store (alone, and with the fake bridge for the whole flow). Timers are fake, so nothing really waits.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

// The store and the bridge file read `window` when they load, and this runs in plain node.
vi.hoisted(() => {
  ;(globalThis as { window?: unknown }).window = globalThis
})

import { createFakeBridge } from './fakeBridge'
import {
  currentNotice,
  doneNoticeNote,
  elapsedText,
  maxChoices,
  noticeChoices,
  noticeProject,
  pickerEndsAt,
  pickerTiles,
  pillView,
  secondsLeft,
  sentSeconds,
  sentView,
  sizeToReport,
} from './floatModel'
import { floatRouteFrom } from './floatRoute'
import { createStore } from './store'
import type { DoneNotice, Notice, OpenPicker, QuestionNotice, RouteSent } from './types'

beforeEach(() => {
  vi.useFakeTimers()
})

afterEach(() => {
  vi.useRealTimers()
})

async function settle(promise: Promise<void>): Promise<void> {
  await vi.advanceTimersByTimeAsync(500)
  await promise
}

const doneNotice: DoneNotice = { kind: 'done', id: 'a1', agent: 'Claude Code', project: '/Users/me/Workspace/tinkeroo', projectName: 'Tinkeroo', note: 'Moved Delete.' }
const questionNotice: QuestionNotice = {
  kind: 'question',
  id: 'q1',
  project: 'Tinkeroo',
  agent: 'Claude Code',
  text: 'Ask first?',
  choices: ['Yes', 'No', 'Maybe', 'Never'],
  asked: 1,
}

describe('float route', () => {
  it('it_reads_the_route_the_app_injected', () => {
    expect(floatRouteFrom('pill', '')).toBe('pill')
    expect(floatRouteFrom('picker', '')).toBe('picker')
    expect(floatRouteFrom('notice', '')).toBe('notice')
  })

  it('it_reads_the_route_from_the_address_when_nothing_was_injected', () => {
    expect(floatRouteFrom(undefined, '#/float/notice')).toBe('notice')
    expect(floatRouteFrom('other', '#/float/pill')).toBe('pill')
  })

  it('it_is_the_main_window_for_anything_else', () => {
    expect(floatRouteFrom(undefined, '')).toBeUndefined()
    expect(floatRouteFrom(undefined, '#/settings')).toBeUndefined()
    expect(floatRouteFrom(7, '#/float/other')).toBeUndefined()
  })
})

describe('pill', () => {
  it('it_counts_minutes_and_seconds_since_the_start', () => {
    const start = Date.parse('2026-11-24T09:00:00Z')
    expect(elapsedText('2026-11-24T09:00:00Z', start + 12_000)).toBe('0:12')
    expect(elapsedText('2026-11-24T09:00:00Z', start + 125_000)).toBe('2:05')
    expect(elapsedText('2026-11-24T09:00:00Z', start - 5000)).toBe('0:00')
    expect(elapsedText(undefined, start)).toBe('0:00')
    expect(elapsedText('not a date', start)).toBe('0:00')
  })

  it('it_shows_the_recording_with_time_and_points', () => {
    const now = Date.parse('2026-11-24T09:00:12Z')
    const view = pillView({ phase: 'recording', pointCount: 3, startedAt: '2026-11-24T09:00:00Z' }, now, 0)
    expect(view).toEqual({ phase: 'recording', elapsed: '0:12', points: 3 })
  })

  it('it_shows_making_items_with_the_last_points_when_the_app_reports_zero', () => {
    expect(pillView({ phase: 'processing', pointCount: 0, startedAt: undefined }, 0, 4)).toEqual({ phase: 'processing', elapsed: '0:00', points: 4 })
    expect(pillView({ phase: 'processing', pointCount: 2, startedAt: undefined }, 0, 4)?.points).toBe(2)
  })

  it('it_shows_nothing_while_idle_or_picking', () => {
    expect(pillView({ phase: 'idle', pointCount: 0, startedAt: undefined }, 0, 0)).toBeUndefined()
    expect(pillView({ phase: 'picking', pointCount: 0, startedAt: undefined }, 0, 0)).toBeUndefined()
  })
})

describe('picker', () => {
  const picker: OpenPicker = {
    open: true,
    session: 's1',
    choices: [
      { name: 'Tinkeroo', path: '/w/tinkeroo', key: 1, suggested: true },
      { name: 'Pointroo', path: '/w/pointroo', key: 2, suggested: false },
    ],
    countdown: 8,
  }

  it('it_makes_a_live_row_per_choice_in_key_order_with_the_folder_as_id', () => {
    expect(pickerTiles(picker)).toEqual([
      { id: '/w/tinkeroo', name: 'Tinkeroo', suggested: true, live: true },
      { id: '/w/pointroo', name: 'Pointroo', suggested: false, live: true },
    ])
  })

  it('it_works_out_when_the_picker_skips', () => {
    expect(pickerEndsAt(picker, 1000)).toBe(9000)
    const { countdown: _countdown, ...withoutCountdown } = picker
    expect(pickerEndsAt(withoutCountdown, 1000)).toBeUndefined()
  })

  it('it_counts_whole_seconds_left_and_never_goes_below_zero', () => {
    expect(secondsLeft(9000, 1000)).toBe(8)
    expect(secondsLeft(9000, 1001)).toBe(8)
    expect(secondsLeft(9000, 8999)).toBe(1)
    expect(secondsLeft(9000, 12000)).toBe(0)
  })
})

describe('notice card', () => {
  it('it_shows_the_newest_notice_or_none', () => {
    expect(currentNotice([])).toBeUndefined()
    expect(currentNotice([questionNotice, doneNotice])).toBe(questionNotice)
  })

  it('it_names_the_project_from_the_name_then_the_folder_then_a_plain_word', () => {
    expect(noticeProject(doneNotice)).toBe('Tinkeroo')
    const { projectName: _projectName, ...withoutName } = doneNotice
    expect(noticeProject(withoutName)).toBe('tinkeroo')
    const { project: _project, ...withoutAny } = withoutName
    expect(noticeProject(withoutAny)).toBe('An agent')
    expect(noticeProject(questionNotice)).toBe('Tinkeroo')
    expect(noticeProject({ ...questionNotice, project: '' })).toBe('An agent')
  })

  it('it_cuts_the_choices_to_three_and_gives_a_done_notice_a_note', () => {
    expect(maxChoices).toBe(3)
    expect(noticeChoices(questionNotice)).toEqual(['Yes', 'No', 'Maybe'])
    expect(doneNoticeNote(doneNotice)).toBe('Moved Delete.')
    const { note: _note, ...withoutNote } = doneNotice
    expect(doneNoticeNote(withoutNote)).toBe('Finished.')
  })
})

describe('sent pill', () => {
  const sent: RouteSent = { session: 's1', project: '/Users/me/Workspace/pointroo', projectName: 'Pointroo', how: 'only', ids: ['s1#1'] }

  it('it_says_where_it_went_and_why', () => {
    expect(sentSeconds).toBe(6)
    expect(sentView(undefined)).toBeUndefined()
    expect(sentView(sent)).toEqual({ label: 'Sent to Pointroo', note: 'Only session listening' })
    expect(sentView({ ...sent, how: 'said' })?.note).toBe('You said the name')
    expect(sentView({ ...sent, how: 'screen' })?.note).toBe('Matched from the screen')
    expect(sentView({ ...sent, how: 'followup' })?.note).toBe('Follow-up on a finished item')
  })

  it('it_falls_back_to_the_folder_name_and_then_a_plain_word', () => {
    expect(sentView({ ...sent, projectName: '' })?.label).toBe('Sent to pointroo')
    expect(sentView({ ...sent, projectName: '', project: '' })?.label).toBe('Sent to the project')
  })
})

describe('size to the app', () => {
  it('it_reports_the_whole_size_while_there_is_content_and_zero_when_not', () => {
    expect(sizeToReport(392.2, 88.5, true)).toEqual({ width: 393, height: 89 })
    expect(sizeToReport(392, 88, false)).toEqual({ width: 0, height: 0 })
  })
})

describe('floating store with the fake bridge', () => {
  it('it_follows_the_recording_to_the_picker_and_back_with_the_light_start', async () => {
    const store = createStore(createFakeBridge())
    const stop = store.startFloating()
    await vi.advanceTimersByTimeAsync(500)
    expect(pillView(store.recording, Date.now(), 0)).toBeUndefined()
    await settle(store.startRecording())
    expect(pillView(store.recording, Date.now(), 0)?.phase).toBe('recording')
    await settle(store.stopRecording())
    expect(store.recording.phase).toBe('picking')
    expect(pillView(store.recording, Date.now(), 0)).toBeUndefined()
    const open = store.picker
    expect(open).not.toBeNull()
    expect(open === null ? [] : pickerTiles(open).length).toBeGreaterThan(0)
    await settle(store.skipPicker())
    expect(store.picker).toBeNull()
    stop()
  })

  it('it_loads_only_the_recording_the_picker_and_the_notices', async () => {
    const calls: string[] = []
    const fake = createFakeBridge()
    const store = createStore({
      call(method, params) {
        calls.push(method)
        return fake.call(method, params)
      },
      on: (name, handler) => fake.on(name, handler),
    })
    const stop = store.startFloating()
    await vi.advanceTimersByTimeAsync(500)
    expect(calls.sort()).toEqual(['notices.list', 'picker.get', 'recording.get'])
    stop()
  })

  it('it_shows_a_done_notice_until_it_is_marked_seen', async () => {
    const store = createStore(createFakeBridge())
    const stop = store.startFloating()
    await vi.advanceTimersByTimeAsync(500)
    const done = store.notices.find((notice: Notice): notice is DoneNotice => notice.kind === 'done')
    expect(done).toBeDefined()
    await settle(store.markNoticesSeen(done === undefined ? [] : [done.id]))
    expect(store.notices.some((notice) => notice.kind === 'done' && notice.id === done?.id)).toBe(false)
    stop()
  })
})
