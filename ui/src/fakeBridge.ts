// The bridge for a plain browser (npm run dev): answers from the mockups' sample data and keeps changes in memory.
// It also answers the methods W2 adds, so every button can be tried without the app.
import { asks, done, doneByYou, doneOlder, notSent, pointrooWaiting, sampleImage, waiting, working } from '../mockups/data/items'
import { projects } from '../mockups/data/projects'
import type { Item } from './parts/types'
import { autoStartChoices } from './parts/autoStart'
import type { Bridge } from './bridge'
import { BridgeError } from './bridgeError'
import type {
  AutoStartChoiceKey,
  BridgeAppStatus,
  BridgeEventName,
  BridgeEvents,
  BridgeHint,
  BridgeItem,
  BridgeSetupRow,
  BridgeWakeSettings,
  BridgeMethod,
  BridgeMethods,
  BridgeProject,
  BridgeQuestion,
  DoneNotice,
  ItemGroup,
  ItemsListParams,
  ItemsSearchParams,
  Notice,
  PermissionName,
  PickerChoice,
  PickerSnapshot,
  QuestionNotice,
  RecordingPhase,
  RouteSent,
  SearchField,
  SearchResult,
  SettingKey,
  SettingValue,
} from './types'

declare global {
  interface Window {
    /** Set by the fake bridge (plain browser only): try the events the app sends by itself, from the console. */
    pointrooDev?: {
      focusItem(id: string): void
      sent(data: RouteSent): void
      hint(data: BridgeHint): void
    }
  }
}

const minutesPerUnit: Record<string, number> = { min: 1, hour: 60, hours: 60, day: 1440, days: 1440 }

function minutesAgo(age: string): number {
  if (age === 'now') return 0
  if (age === 'yesterday') return 1440
  const match = /^(\d+) (min|hours?|days?) ago$/.exec(age)
  if (match === null) return 0
  return Number(match[1]) * (minutesPerUnit[match[2] ?? 'min'] ?? 1)
}

function toBridgeItem(item: Item): BridgeItem {
  const status = item.state === 'done' || item.state === 'done-by-you' ? 'done' : item.state === 'working' || item.state === 'asks' ? 'in_progress' : 'open'
  const pointLines = item.crops.map((crop) => `- [${crop.number}] click in Sample: ${crop.caption}; crop \`/sample/crops/0${crop.number}.jpg\``)
  const marked = item.crops.length > 0 ? `${item.said} [1]` : item.said
  const body = [`Said (0:00 to 0:05): "${marked}"`, '', 'Pointed at:', ...pointLines].join('\n')
  const result: BridgeItem = {
    id: item.id,
    session: 'sample',
    n: 1,
    title: item.title,
    body,
    crops: item.crops.map((crop) => `/sample/crops/0${crop.number}.jpg`),
    cropURLs: item.crops.flatMap((crop) => (crop.url === undefined ? [] : [crop.url])),
    status,
    alsoSaid: [],
    at: new Date(Date.now() - minutesAgo(item.age) * 60000).toISOString(),
    said: item.said,
  }
  if (status === 'done') result.doneAt = result.at ?? new Date().toISOString()
  if (item.afterUrl !== undefined) result.afterURL = item.afterUrl
  if (item.project !== null) result.project = item.project
  if (item.agent !== undefined && status !== 'open') result.by = item.agent
  if (item.note !== undefined) result.note = item.note
  if (item.how !== 'none') result.routeHow = item.how
  if (item.wake !== undefined) {
    const results = { woke: 'sent', 'no-session': 'no owner', busy: 'listening', 'too-old': 'claude code too old for wake (needs 2.1.224+)' }
    result.wake = item.wake.name === undefined ? { result: results[item.wake.kind] } : { result: results[item.wake.kind], name: item.wake.name }
  }
  return result
}

export function createFakeBridge(): Bridge {
  const samples: Item[] = [working, asks, waiting, pointrooWaiting, notSent, done, doneByYou, doneOlder]
  let items: BridgeItem[] = samples.map(toBridgeItem)
  let questions: BridgeQuestion[] = asks.question
    ? [{ id: 'q1', project: 'Tinkeroo', agent: 'Claude Code', text: asks.question.text, choices: asks.question.choices, asked: Date.now() / 1000 }]
    : []
  const listeners = new Map<string, Set<(data: never) => void>>()

  function emit<Name extends BridgeEventName>(name: Name, data: BridgeEvents[Name]): void {
    window.setTimeout(() => listeners.get(name)?.forEach((listener) => listener(data as never)), 0)
  }

  function counts(): BridgeEvents['items.changed'] {
    return { count: items.length, open: items.filter((item) => item.status === 'open').length, inProgress: items.filter((item) => item.status === 'in_progress').length }
  }

  function changed(): void {
    emit('items.changed', counts())
  }

  function find(id: string): BridgeItem {
    const found = items.find((item) => item.id === id)
    if (found === undefined) throw new BridgeError('not_found', 'No such item.')
    return found
  }

  function projectList(): BridgeProject[] {
    return projects.map((project, index) => {
      const mine = items.filter((item) => item.project === project.name && item.status !== 'done')
      const entry: BridgeProject = {
        name: project.name,
        path: project.folder,
        aliases: [],
        live: project.listening,
        // Sample: Tableroo has a session open that does not listen, so the "open" hint shows.
        sessionOpen: project.sessionOpen === true,
        agents: project.listening ? ['Claude Code'] : [],
        open: mine.filter((item) => item.status === 'open').length,
        inProgress: mine.filter((item) => item.status === 'in_progress').length,
      }
      if (project.listening && index < 9) entry.key = index + 1
      // Sample dates: the first projects were used most recently; the rest never.
      if (index < 3) entry.lastUsed = new Date(Date.now() - (index + 1) * 3600000).toISOString()
      return entry
    })
  }

  // Sample permissions: screen recording starts off so Settings shows an Allow button; asking turns it on.
  const permissions: Record<PermissionName, boolean> = { microphone: true, screenRecording: false, accessibility: true }
  // Sample setup: a fresh Mac. Each action fixes its row; screen recording says "denied" once it was asked for.
  const setupState = { inApplications: false, screenAsked: false, tool: false, stopHook: false, speechReady: false }

  function setupRows(): BridgeSetupRow[] {
    const permission = (id: PermissionName, label: string): BridgeSetupRow => {
      if (permissions[id]) return { id, state: 'done' }
      if (id === 'screenRecording' && setupState.screenAsked) return { id, state: 'todo', detail: 'denied', action: 'openScreenRecordingSettings' }
      return { id, state: 'todo', action: `allow${label}` as BridgeSetupRow['action'] }
    }
    const todo = (id: string, done: boolean, action: BridgeSetupRow['action']): BridgeSetupRow => (done ? { id, state: 'done' } : { id, state: 'todo', ...(action === undefined ? {} : { action }) })
    return [
      todo('applications', setupState.inApplications, 'move'),
      permission('microphone', 'Microphone'),
      permission('screenRecording', 'ScreenRecording'),
      permission('accessibility', 'Accessibility'),
      todo('claudeCode', true, 'install'),
      todo('tool', setupState.tool, 'connect'),
      todo('stopHook', setupState.stopHook, 'addHook'),
      setupState.speechReady ? { id: 'speech', state: 'done' } : { id: 'speech', state: 'busy' },
      todo('wake', true, 'updateClaude'),
    ]
  }

  const wakeState: BridgeWakeSettings = {
    enabled: true,
    owners: projects.map((project) => ({ project: project.name, owner: 'auto' })),
    sessions: [
      { id: 'tinkeroo-main', name: 'Tinkeroo' },
      { id: 'pointroo-main', name: 'Pointroo lead' },
    ],
    last: { project: 'Tinkeroo', name: 'Tinkeroo', at: new Date(Date.now() - 120000).toISOString() },
  }

  // The sample auto-start run goes away when autoRuns.stop is called; changing the Auto-start setting brings it back.
  let sampleRunStopped = false
  const settingValues: Record<SettingKey, SettingValue> = {
    sounds: true,
    doubleControl: true,
    escCancels: true,
    redactSecrets: true,
    connectAgents: false,
    showNoSpeech: false,
    holdToTalk: false,
    listenAfterDone: false,
    autoSendSingle: true,
    kitWindow: true,
    kitFloating: true,
    locale: '',
    autoStartAgent: 'off',
    autoStartModel: 'sonnet',
    autoStartEffort: 'medium',
    autoStartBudget: 2,
    autoStartPermission: 'acceptEdits',
  }
  const languageIds = ['', 'en-US', 'de-DE', 'fr-FR', 'es-ES', 'it-IT', 'pt-BR', 'nl-NL', 'ja-JP', 'zh-CN']

  function isSettingKey(key: string | undefined): key is SettingKey {
    return key !== undefined && Object.hasOwn(settingValues, key)
  }

  function setSetting(key: string, value: SettingValue): { key: string; value: SettingValue } {
    if (!isSettingKey(key)) throw new BridgeError('refused', 'That setting cannot be changed.')
    if (key === 'locale') {
      if (typeof value !== 'string' || !languageIds.includes(value)) throw new BridgeError('bad_params', 'locale must be one of the known values.')
    } else if (key === 'autoStartBudget') {
      if (typeof value !== 'number' || !Number.isFinite(value) || value < 0.5 || value > 20) {
        throw new BridgeError('bad_params', 'autoStartBudget must be a number from 0.5 to 20.')
      }
    } else if (key in autoStartChoices) {
      const options = autoStartChoices[key as AutoStartChoiceKey].options
      if (typeof value !== 'string' || !options.some((option) => option.value === value)) {
        throw new BridgeError('bad_params', `${key} must be one of the known values.`)
      }
    } else if (typeof value !== 'boolean') {
      throw new BridgeError('bad_params', `${key} is on or off (true or false).`)
    }
    settingValues[key] = value
    if (key === 'autoStartAgent') sampleRunStopped = false
    return { key, value }
  }

  function statusNow(): BridgeAppStatus {
    // One sample run, only while Auto-start is on, so the Settings frame can show "1 run going".
    const autoRuns = settingValues.autoStartAgent === 'off' || sampleRunStopped ? [] : [{ project: '/Users/sample/Workspace/tinkeroo', startedAt: new Date(Date.now() - 90000).toISOString() }]
    const lastAutoRun = settingValues.autoStartAgent === 'claude' ? { project: '/Users/sample/Workspace/tinkeroo', endedAt: new Date(Date.now() - 600000).toISOString(), exitCode: 0, cost: 0.42 } : undefined
    return { mcpRunning: true, mcpPort: 6742, mcpText: 'Shared MCP server: running on 127.0.0.1:6742', sessions: 2, agents: ['Claude Code', 'Codex'], autoRuns, ...(lastAutoRun === undefined ? {} : { lastAutoRun }), ...permissions }
  }

  function listItems(params: ItemsListParams): { items: BridgeItem[] } | { groups: ItemGroup[] } {
    const matching = items.filter((item) => params.status === undefined || item.status === params.status)
    if (params.groupBy !== 'project') return { items: matching }
    const groups: ItemGroup[] = projects
      .map((project) => ({ project: { name: project.name, path: project.folder }, items: matching.filter((item) => item.project === project.name) }))
      .filter((group) => group.items.length > 0)
    const loose = matching.filter((item) => item.project === undefined)
    if (loose.length > 0) groups.push({ project: null, items: loose })
    return { groups }
  }

  function reroute(id: string, projectText: string): void {
    const item = find(id)
    if (item.status === 'done') throw new BridgeError('refused', 'The item is done.')
    const project = projects.find((entry) => entry.name === projectText || entry.folder === projectText)
    if (project === undefined) throw new BridgeError('not_found', 'No such project.')
    item.project = project.name
    item.routeHow = 'picked'
  }

  let phase: RecordingPhase = 'idle'
  let startedAt: string | undefined
  let pointCount = 0
  let pickerSession: string | undefined
  const seenNoticeIds = new Set<string>()

  function emitRecording(): void {
    emit('recording.changed', { phase, pointCount })
  }

  function pickerChoices(): PickerChoice[] {
    return projectList()
      .filter((project) => project.live)
      .slice(0, 9)
      .map((project, index) => ({ name: project.name, path: project.path, key: index + 1, suggested: index === 0 }))
  }

  function pickerSnapshot(): PickerSnapshot {
    if (phase !== 'picking') return { open: false }
    return { open: true, ...(pickerSession === undefined ? {} : { session: pickerSession }), choices: pickerChoices(), countdown: 8 }
  }

  function closePicker(): void {
    phase = 'idle'
    pickerSession = undefined
    emitRecording()
    emit('picker.changed', { open: false })
  }

  function noticeList(): Notice[] {
    const doneNotices = items
      .filter((item) => item.status === 'done' && item.by !== undefined && item.by !== 'you' && item.by !== 'user' && !seenNoticeIds.has(item.id))
      .map((item): DoneNotice => {
        const notice: DoneNotice = { kind: 'done', id: item.id, agent: item.by ?? '' }
        const project = projects.find((entry) => entry.name === item.project)
        if (project !== undefined) notice.project = project.folder
        if (item.project !== undefined) notice.projectName = item.project
        if (item.note !== undefined) notice.note = item.note
        const firstCrop = item.cropURLs[0]
        if (firstCrop !== undefined) notice.cropURL = firstCrop
        if (item.afterURL !== undefined) notice.afterURL = item.afterURL
        if (item.at !== undefined) notice.at = item.at
        return notice
      })
    const questionNotices = questions.map((question): QuestionNotice => ({ ...question, kind: 'question' }))
    const when = (notice: Notice): number => (notice.kind === 'question' ? notice.asked * 1000 : Date.parse(notice.at ?? ''))
    return [...doneNotices, ...questionNotices].sort((first, second) => (when(second) || 0) - (when(first) || 0))
  }

  function plain(text: string): string {
    return text.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase()
  }

  function searchFields(item: BridgeItem): [SearchField, string][] {
    return [
      ['title', item.title],
      ['said', item.said ?? ''],
      ['body', item.body],
      ['alsoSaid', item.alsoSaid.join(' ')],
      ['note', item.note ?? ''],
      ['project', item.project ?? ''],
      ['firstElement', item.firstElement ?? ''],
    ]
  }

  function snippetAround(text: string, word: string): string {
    const oneLine = text.replace(/\s+/g, ' ').trim()
    const at = Math.max(0, plain(oneLine).indexOf(word))
    const start = Math.max(0, Math.min(at - 20, oneLine.length - 80))
    return oneLine.slice(start, start + 80)
  }

  function searchItems(params: ItemsSearchParams): { items: SearchResult[] } {
    if (typeof params.text !== 'string' || params.text.trim() === '' || params.text.length > 200) throw new BridgeError('bad_params', 'text is 1 to 200 characters.')
    const allowed = ['open', 'in_progress', 'done', 'trashed', 'any']
    if (params.status !== undefined && !allowed.includes(params.status)) throw new BridgeError('bad_params', 'status is not allowed.')
    const limit = params.limit ?? 30
    if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new BridgeError('bad_params', 'limit is a whole number from 1 to 100.')
    const words = plain(params.text).split(/\s+/).filter((word) => word !== '')
    const found: { result: SearchResult; rank: number }[] = []
    for (const item of items) {
      if (params.status !== undefined && params.status !== 'any' && item.status !== params.status) continue
      const fields = searchFields(item)
      const joined = plain(fields.map(([, text]) => text).join('\n'))
      if (!words.every((word) => joined.includes(word))) continue
      const fallback: [SearchField, string] = ['title', item.title]
      const [field, text] = fields.find(([, fieldText]) => plain(fieldText).includes(words[0] ?? '')) ?? fallback
      found.push({ result: { ...item, match: { field, snippet: snippetAround(text, words[0] ?? '') } }, rank: field === 'title' ? 0 : field === 'said' || field === 'body' ? 1 : 2 })
    }
    found.sort((first, second) => first.rank - second.rank || Date.parse(second.result.at ?? '') - Date.parse(first.result.at ?? ''))
    return { items: found.slice(0, limit).map((entry) => entry.result) }
  }

  const handlers: { [Name in BridgeMethod]: (params: BridgeMethods[Name]['params']) => BridgeMethods[Name]['result'] } = {
    'items.list': (params) => listItems(params),
    'projects.list': () => ({ projects: projectList() }),
    'items.get': (params) => ({ item: find(params.id) }),
    'items.reroute': (params) => {
      reroute(params.id, params.project)
      changed()
      return { moved: true }
    },
    'items.unroute': (params) => {
      const item = find(params.id)
      delete item.project
      delete item.routeHow
      changed()
      return { unrouted: true }
    },
    'route.change': (params) => {
      if (typeof params.session !== 'string' || params.session === '' || params.session.includes('/') || params.session.includes('..')) throw new BridgeError('bad_params', 'session is needed.')
      if (phase === 'picking') throw new BridgeError('busy', 'A project picker is already open.')
      if (params.session !== 'sample') throw new BridgeError('not_found', 'No such recording.')
      phase = 'picking'
      pickerSession = params.session
      emitRecording()
      emit('picker.changed', { open: true, session: pickerSession })
      return { opened: true }
    },
    'items.done': (params) => {
      const item = find(params.id)
      item.status = 'done'
      item.doneAt = new Date().toISOString()
      changed()
      return { done: true }
    },
    'items.reopen': (params) => {
      const item = find(params.id)
      item.status = 'open'
      delete item.doneAt
      changed()
      return { reopened: true }
    },
    'items.trash': (params) => {
      find(params.id)
      items = items.filter((item) => item.id !== params.id)
      changed()
      return { trashed: true }
    },
    'done.recent': (params) => {
      const limit = Math.min(50, Math.max(1, params.limit ?? 10))
      const finished = items.filter((item) => item.status === 'done').sort((first, second) => Date.parse(second.doneAt ?? second.at ?? '') - Date.parse(first.doneAt ?? first.at ?? ''))
      return { items: finished.slice(0, limit) }
    },
    'session.get': (params) => {
      if (typeof params.session !== 'string' || params.session === '') throw new BridgeError('bad_params', 'session is needed.')
      if (params.session !== 'sample') throw new BridgeError('not_found', 'No such recording.')
      const mine = items.filter((item) => item.said !== undefined && item.said !== '')
      return {
        session: 'sample',
        started: new Date(Date.now() - 10 * 60000).toISOString(),
        duration: 95,
        said: mine.map((item, index) => ({ text: item.said ?? '', start: index * 8, end: index * 8 + 6 })),
        points: [
          { at: 2, x: 120, y: 80, app: 'Tinkeroo', window: 'Settings', element: 'Button "Delete"' },
          { at: 5, x: 220, y: 80, app: 'Tinkeroo', window: 'Settings', element: 'Button "Save"' },
          { at: 21, x: 400, y: 300, app: 'Safari', url: 'https://example.com/overview' },
        ],
        frames: [sampleImage('Frame 1', '#6b7280'), sampleImage('Frame 2', '#3b82f6'), sampleImage('Frame 3', '#10b981')],
        items: mine.map((item) => item.id),
      }
    },
    'questions.later': (params) => {
      if (!questions.some((question) => question.id === params.id)) throw new BridgeError('not_found', 'No such question.')
      const minutes = Math.min(1440, Math.max(1, params.minutes ?? 30))
      questions = questions.filter((question) => question.id !== params.id)
      emit('questions.changed', { count: questions.length })
      return { snoozed: true, until: Date.now() / 1000 + minutes * 60 }
    },
    'questions.list': () => ({ questions }),
    'questions.answer': (params) => {
      questions = questions.filter((question) => question.id !== params.id)
      emit('questions.changed', { count: questions.length })
      return { answered: true }
    },
    'settings.get': (params) => {
      if (params.key === undefined) return { values: { ...settingValues } }
      if (!isSettingKey(params.key)) throw new BridgeError('refused', 'That setting cannot be read.')
      return { key: params.key, value: settingValues[params.key] }
    },
    'settings.set': (params) => setSetting(params.key, params.value),
    'status.get': () => ({ status: statusNow() }),
    'permissions.ask': (params) => {
      permissions[params.which] = true
      emit('status.changed', statusNow())
      return { asked: true }
    },
    'items.search': (params) => searchItems(params),
    'recording.start': (params) => {
      if (phase !== 'idle') throw new BridgeError('busy', 'A recording is running or being processed.')
      if (params.followUp !== undefined) {
        const target = items.find((item) => item.id === params.followUp)
        if (target === undefined || target.status !== 'done' || target.project === undefined) throw new BridgeError('bad_params', 'followUp must be a done item that went to a project.')
      }
      phase = 'recording'
      startedAt = new Date().toISOString()
      pointCount = 0
      emitRecording()
      return params.followUp === undefined ? { started: true } : { started: true, followUp: params.followUp }
    },
    'recording.stop': () => {
      if (phase !== 'recording') throw new BridgeError('busy', 'Not recording.')
      startedAt = undefined
      phase = 'picking'
      pickerSession = new Date().toISOString().slice(0, 16).replace('T', '-').replace(':', '')
      emitRecording()
      emit('picker.changed', { open: true, session: pickerSession })
      return { stopped: true }
    },
    'recording.cancel': () => {
      if (phase !== 'recording') throw new BridgeError('busy', 'Not recording.')
      startedAt = undefined
      phase = 'idle'
      pointCount = 0
      emitRecording()
      return { cancelled: true }
    },
    'recording.get': () => ({ phase, points: pointCount, ...(startedAt === undefined || phase !== 'recording' ? {} : { startedAt }) }),
    'picker.get': () => pickerSnapshot(),
    'picker.pick': (params) => {
      if (phase !== 'picking') throw new BridgeError('not_found', 'No picker is open.')
      if (typeof params.path !== 'string' || !pickerChoices().some((choice) => choice.path === params.path)) throw new BridgeError('bad_params', 'path is not one of the choices.')
      closePicker()
      return { picked: true }
    },
    'picker.skip': () => {
      if (phase !== 'picking') throw new BridgeError('not_found', 'No picker is open.')
      closePicker()
      return { skipped: true }
    },
    'notices.list': (params) => {
      const limit = params.limit ?? 20
      if (!Number.isInteger(limit) || limit < 1 || limit > 50) throw new BridgeError('bad_params', 'limit is a whole number from 1 to 50.')
      return { notices: noticeList().slice(0, limit) }
    },
    'notices.seen': (params) => {
      if (!Array.isArray(params.ids) || params.ids.some((id) => typeof id !== 'string')) throw new BridgeError('bad_params', 'ids is a list of text.')
      const doneIds = params.ids.filter((id) => items.some((item) => item.id === id && item.status === 'done'))
      doneIds.forEach((id) => seenNoticeIds.add(id))
      emit('notices.changed', { count: noticeList().length })
      return { seen: doneIds.length }
    },
    'clipboard.copy': () => ({ copied: true }),
    'window.startDrag': () => ({ dragging: true }),
    'server.useAnotherPort': () => ({ asked: true }),
    'app.checkUpdates': () => ({ asked: true }),
    'autoRuns.stop': (params) => {
      if (params.project === '') throw new BridgeError('bad_params', 'project is needed.')
      const wasGoing = settingValues.autoStartAgent !== 'off' && !sampleRunStopped
      sampleRunStopped = true
      if (wasGoing) emit('status.changed', statusNow())
      return { stopped: wasGoing }
    },
    'setup.status': () => ({ rows: setupRows() }),
    'setup.action': (params) => {
      const actions: Record<string, () => void> = {
        move: () => (setupState.inApplications = true),
        allowMicrophone: () => (permissions.microphone = true),
        allowScreenRecording: () => (setupState.screenAsked = true),
        allowAccessibility: () => (permissions.accessibility = true),
        openMicrophoneSettings: () => (permissions.microphone = true),
        openScreenRecordingSettings: () => (permissions.screenRecording = true),
        openAccessibilitySettings: () => (permissions.accessibility = true),
        install: () => undefined,
        connect: () => (setupState.tool = true),
        addHook: () => (setupState.stopHook = true),
        retrySpeech: () => (setupState.speechReady = true),
        updateClaude: () => undefined,
      }
      const run = Object.hasOwn(actions, params.id) ? actions[params.id] : undefined
      if (run === undefined) throw new BridgeError('bad_params', 'id must be one of the setup actions.')
      run()
      emit('status.changed', statusNow())
      emit('setup.changed', { rows: setupRows() })
      return { rows: setupRows() }
    },
    'wake.get': () => ({ ...wakeState }),
    'wake.set': (params) => {
      if (params.enabled !== undefined) wakeState.enabled = params.enabled
      for (const change of params.owners ?? []) {
        const entry = wakeState.owners.find((owner) => owner.project === change.project)
        if (entry === undefined) throw new BridgeError('not_found', 'No such project.')
        entry.owner = change.owner
      }
      return { ...wakeState }
    },
    'autoRuns.log': (params) => {
      const count = params.lines ?? 50
      if (!Number.isInteger(count) || count < 1 || count > 200) throw new BridgeError('bad_params', 'lines is a whole number from 1 to 200.')
      const sampleLines = [
        '2026-11-24T09:00:00Z started a run in /Users/sample/Workspace/tinkeroo',
        '2026-11-24T09:04:12Z run in /Users/sample/Workspace/tinkeroo ended (exit 0, $0.42)',
        '2026-11-24T09:30:00Z started a run in /Users/sample/Workspace/shoproo',
      ]
      return { lines: sampleLines.slice(-count) }
    },
  }

  window.pointrooDev = {
    focusItem: (id) => emit('item.focus', { id }),
    sent: (data) => emit('route.sent', data),
    hint: (data) => emit('hint.show', data),
  }

  return {
    call(method, params) {
      const handler = handlers[method] as (value: unknown) => unknown
      return new Promise((resolve, reject) => {
        window.setTimeout(() => {
          try {
            resolve(handler(params ?? {}) as never)
          } catch (error) {
            reject(error)
          }
        }, 60)
      })
    },
    on(name, listener) {
      const set = listeners.get(name) ?? new Set<(data: never) => void>()
      set.add(listener as (data: never) => void)
      listeners.set(name, set)
      return () => {
        set.delete(listener as (data: never) => void)
      }
    },
  }
}
