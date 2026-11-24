// What the window knows: the items, projects, status and questions from the app, and what the user has picked.
// The app tells the page when something changed (events); the store then asks again. Every action goes through the bridge.
import { computed, reactive, ref } from 'vue'
import type { Bridge } from './bridge'
import { errorText } from './bridge'
import type { Item, MainBanner, MainTab, MainToast, Project, RecordingView, SearchHit } from './parts/types'
import type {
  BridgeAppStatus,
  BridgeItem,
  BridgeProject,
  BridgeQuestion,
  Notice,
  OpenPicker,
  PermissionName,
  RecordingPhase,
  RouteSent,
  SearchFilter,
  SearchResult,
  SettingKey,
  SettingValue,
  SettingsValues,
} from './types'
import { sentSeconds } from './floatModel'
import { matchQuestions, toRecordingView, toViewItem, toViewProjects } from './viewModel'

const undoSeconds = 5
const plainToastSeconds = 3
const recentDoneLimit = 50
const laterMinutes = 30
const defaultSearchDelayMilliseconds = 200
const searchTextLimit = 200
const autoRunLogLines = 50

export interface StoreOptions {
  /** How long the search waits after the last key before it asks the app. Tests make it small. */
  searchDelayMilliseconds?: number
}

interface UndoStep {
  itemId: string
  /** The project the item was in before; null for a first send. */
  previousName: string | null
}

export function createStore(bridge: Bridge, options: StoreOptions = {}) {
  const searchDelayMilliseconds = options.searchDelayMilliseconds ?? defaultSearchDelayMilliseconds
  const bridgeItems = ref<BridgeItem[]>([])
  /** The newest done items from done.recent. Stays undefined while the app does not answer that method. */
  const recentDone = ref<BridgeItem[] | undefined>(undefined)
  const recordings = ref<Record<string, RecordingView>>({})
  const bridgeProjects = ref<BridgeProject[]>([])
  const questions = ref<BridgeQuestion[]>([])
  const status = ref<BridgeAppStatus | undefined>(undefined)
  const recording = reactive<{ phase: RecordingPhase; pointCount: number; startedAt: string | undefined }>({ phase: 'idle', pointCount: 0, startedAt: undefined })
  /** The open project picker, or null while it is closed. */
  const picker = ref<OpenPicker | null>(null)
  const notices = ref<Notice[]>([])
  /** The recording the app just sent by itself (route.sent), for the pill's "Sent to X / Undo". Cleared after sentSeconds or on undo. */
  const lastSent = ref<RouteSent | undefined>(undefined)
  const searchState = reactive<{ query: string; status: SearchFilter; results: SearchResult[]; loading: boolean; error: string | undefined }>({
    query: '',
    status: 'all',
    results: [],
    loading: false,
    error: undefined,
  })
  /** The search box in the bar is open: the results replace the queue. */
  const searchOpen = ref(false)
  const loading = ref(true)
  const tab = ref<MainTab>('now')
  const filter = ref('all')
  const selectedId = ref<string | undefined>(undefined)
  const toast = ref<MainToast | undefined>(undefined)
  /** The project folders whose auto-start run has been asked to stop and has not answered yet. */
  const stoppingRuns = ref<string[]>([])
  /** The newest lines of the auto-start log while the log panel is open. Undefined when the panel is closed. */
  const autoRunLog = ref<string[] | undefined>(undefined)
  const autoRunLogLoading = ref(false)
  const now = ref(new Date())
  const view = ref<'queue' | 'settings'>('queue')
  const settings = ref<SettingsValues>({})
  const settingsLoaded = ref(false)

  let toastTimer: number | undefined
  let sentTimer: number | undefined
  /** The recordings whose send was already shown, so the same event twice (the app may send it from two places) shows once. */
  const shownSentSessions = new Set<string>()
  let undoSteps: UndoStep[] = []
  let settingUndo: (() => Promise<void>) | undefined
  let refreshing: Promise<void> | undefined
  let refreshAgain = false
  let searchTimer: ReturnType<typeof setTimeout> | undefined
  /** Counts the searches. A reply whose number is no longer the latest is thrown away. */
  let searchNumber = 0
  let finishPendingSearch: (() => void) | undefined

  const projects = computed<Project[]>(() => toViewProjects(bridgeProjects.value))
  const matched = computed(() => matchQuestions(bridgeItems.value, questions.value))
  // A done item from done.recent wins over the same item from items.list (it knows when it was finished). Done items that
  // only done.recent has are added, so a row of the Done tab can always be opened.
  const combinedItems = computed<BridgeItem[]>(() => {
    const recent = recentDone.value ?? []
    const recentById = new Map<string, BridgeItem>(recent.map((item): [string, BridgeItem] => [item.id, item]))
    const known = new Set(bridgeItems.value.map((item) => item.id))
    return [...bridgeItems.value.map((item) => recentById.get(item.id) ?? item), ...recent.filter((item) => !known.has(item.id))]
  })
  const allItems = computed<Item[]>(() => combinedItems.value.map((item) => toViewItem(item, matched.value.get(item.id), now.value, projects.value)))
  const nowItems = computed(() => allItems.value.filter((item) => item.state !== 'done' && item.state !== 'done-by-you'))
  const doneItems = computed<Item[]>(() => {
    const finished = allItems.value.filter((item) => item.state === 'done' || item.state === 'done-by-you')
    const recent = recentDone.value
    if (recent === undefined) return finished
    // Newest first, as done.recent sends them.
    return recent.flatMap((bridgeItem) => finished.filter((item) => item.id === bridgeItem.id))
  })
  const filterName = computed(() => projects.value.find((project) => project.id === filter.value)?.name)
  const rows = computed<Item[]>(() => {
    const list = tab.value === 'now' ? nowItems.value : doneItems.value
    if (filter.value === 'all') return list
    return list.filter((item) => item.project === filterName.value)
  })
  /** What the screen draws for each search result: the item the way a queue row has it, and where the words were found. */
  const searchHits = computed<SearchHit[]>(() =>
    searchState.results.map((result) => ({
      item: toViewItem(result, matched.value.get(result.id), now.value, projects.value),
      match: result.match,
    })),
  )
  // A result the user opened that the queue does not hold (an old done item): it still opens in the detail.
  const searchOpened = ref<SearchHit | undefined>(undefined)
  const selectedItem = computed(() => allItems.value.find((item) => item.id === selectedId.value) ?? (searchOpened.value?.item.id === selectedId.value ? searchOpened.value?.item : undefined))
  const emptyKind = computed<'nothing' | 'all-done'>(() => (allItems.value.length === 0 ? 'nothing' : 'all-done'))

  const banner = computed<MainBanner | undefined>(() => {
    const current = status.value
    if (current === undefined) return undefined
    if (!current.microphone) return { kind: 'permission', which: 'microphone' }
    if (!current.screenRecording) {
      return { kind: 'permission', which: 'screenRecording', title: "Pointroo can't see the screen", description: 'Screen recording is off: no screenshots.' }
    }
    if (!current.accessibility) {
      return { kind: 'permission', which: 'accessibility', title: "Pointroo can't see what you point at", description: 'Accessibility is off: no button or field names.' }
    }
    if (!current.mcpRunning) {
      const busy = /in use|busy/i.test(current.mcpText)
      return { kind: busy ? 'port-busy' : 'mcp-error', description: current.mcpText }
    }
    if (current.sessions === 0) return { kind: 'no-session' }
    return undefined
  })

  const sessionsText = computed(() => {
    const count = status.value?.sessions ?? 0
    return count === 0 ? 'None listening' : `${count} listening`
  })
  const agentsText = computed(() => {
    const names = status.value?.agents ?? []
    return names.length === 0 ? undefined : names.join(', ')
  })

  function showToast(message: string, tone: MainToast['tone'], undo: boolean): void {
    window.clearTimeout(toastTimer)
    settingUndo = undefined
    toast.value = { message, tone, undo }
    toastTimer = window.setTimeout(dismissToast, (undo ? undoSeconds : plainToastSeconds) * 1000)
  }

  function dismissToast(): void {
    window.clearTimeout(toastTimer)
    toast.value = undefined
    undoSteps = []
    settingUndo = undefined
  }

  function fail(error: unknown): void {
    showToast(errorText(error), 'warn', false)
  }

  async function loadItems(): Promise<void> {
    const reply = await bridge.call('items.list', { groupBy: 'project' })
    const groups = 'groups' in reply ? reply.groups : []
    const unrouted = groups.filter((group) => group.project === null).flatMap((group) => group.items)
    const routed = groups.filter((group) => group.project !== null).flatMap((group) => group.items)
    bridgeItems.value = [...unrouted, ...routed]
    now.value = new Date()
  }

  /** An app without done.recent is fine: the Done tab then shows the done items of items.list. */
  async function loadRecentDone(): Promise<void> {
    try {
      recentDone.value = (await bridge.call('done.recent', { limit: recentDoneLimit })).items
    } catch {
      recentDone.value = undefined
    }
  }

  async function loadProjects(): Promise<void> {
    bridgeProjects.value = (await bridge.call('projects.list', {})).projects
  }

  async function loadQuestions(): Promise<void> {
    questions.value = (await bridge.call('questions.list', {})).questions
  }

  async function loadStatus(): Promise<void> {
    status.value = (await bridge.call('status.get', {})).status
  }

  async function runRefresh(): Promise<void> {
    try {
      await Promise.all([loadItems(), loadRecentDone(), loadProjects(), loadQuestions(), loadStatus()])
    } catch (error) {
      fail(error)
    } finally {
      loading.value = false
    }
  }

  /** Asks the app for everything again. A call made while one is running makes it run once more after. */
  function refresh(): Promise<void> {
    if (refreshing !== undefined) {
      refreshAgain = true
      return refreshing
    }
    refreshing = runRefresh().finally(async () => {
      refreshing = undefined
      if (refreshAgain) {
        refreshAgain = false
        await refresh()
      }
    })
    return refreshing
  }

  /** Takes "Sent to X / Undo" off the pill (and stops its timer). */
  function clearSent(): void {
    window.clearTimeout(sentTimer)
    sentTimer = undefined
    lastSent.value = undefined
  }

  /** Shows "Sent to X / Undo" for a recording the app sent by itself. It goes after sentSeconds. The same recording shows once. */
  function showSent(data: RouteSent): void {
    if (shownSentSessions.has(data.session)) return
    shownSentSessions.add(data.session)
    window.clearTimeout(sentTimer)
    lastSent.value = data
    sentTimer = window.setTimeout(clearSent, sentSeconds * 1000)
  }

  /** Undo on the pill: the pill goes at once, then every item of the recording is unrouted (it waits in the queue again). */
  async function undoSent(): Promise<void> {
    const sent = lastSent.value
    if (sent === undefined) return
    clearSent()
    try {
      for (const id of sent.ids) await bridge.call('items.unroute', { id })
    } catch (error) {
      fail(error)
    }
  }

  /** Listens for what a floating panel shows: the recording, the picker, the notices and the automatic send. */
  function listenToFloatingEvents(): (() => void)[] {
    return [
      bridge.on('recording.changed', (data) => {
        recording.phase = data.phase
        recording.pointCount = data.pointCount
        if (data.phase === 'recording') {
          clearSent()
          void loadRecordingState().catch(() => undefined)
        } else {
          recording.startedAt = undefined
        }
      }),
      bridge.on('route.sent', showSent),
      bridge.on('picker.changed', () => void loadPicker().catch(() => undefined)),
      bridge.on('notices.changed', () => void loadNotices().catch(() => undefined)),
    ]
  }

  function loadFloatingState(): void {
    void loadRecordingState().catch(() => undefined)
    void loadPicker().catch(() => undefined)
    void loadNotices().catch(() => undefined)
  }

  function start(): () => void {
    const stops = [
      bridge.on('items.changed', () => void refresh()),
      bridge.on('questions.changed', () => void refresh()),
      bridge.on('status.changed', (data) => {
        status.value = data
      }),
      bridge.on('item.focus', (data) => void focusItem(data.id)),
      ...listenToFloatingEvents(),
    ]
    void refresh()
    loadFloatingState()
    return () => stops.forEach((stop) => stop())
  }

  /** The start of a floating panel: only the recording, the picker and the notices (no queue, no projects, no status). */
  function startFloating(): () => void {
    const stops = listenToFloatingEvents()
    loadFloatingState()
    return () => stops.forEach((stop) => stop())
  }

  /** Asks the app what the recording is doing now (the phase, the points and when it started). */
  async function loadRecordingState(): Promise<void> {
    const snapshot = await bridge.call('recording.get', {})
    recording.phase = snapshot.phase
    recording.pointCount = snapshot.points
    recording.startedAt = snapshot.startedAt
  }

  async function loadPicker(): Promise<void> {
    const snapshot = await bridge.call('picker.get', {})
    picker.value = snapshot.open ? snapshot : null
  }

  /** Loads the notices (done items the user has not seen, and the pending questions). */
  async function loadNotices(): Promise<void> {
    notices.value = (await bridge.call('notices.list', {})).notices
  }

  /** Starts a recording. With followUp it is the follow-up of that done item ("Say more"). */
  async function startRecording(followUp?: string): Promise<void> {
    try {
      await bridge.call('recording.start', followUp === undefined ? {} : { followUp })
    } catch (error) {
      fail(error)
    }
  }

  async function stopRecording(): Promise<void> {
    try {
      await bridge.call('recording.stop', {})
    } catch (error) {
      fail(error)
    }
  }

  async function cancelRecording(): Promise<void> {
    try {
      await bridge.call('recording.cancel', {})
    } catch (error) {
      fail(error)
    }
  }

  /** Answers the open picker with a project folder. If the app says no, the picker is read again. */
  async function pickProject(path: string): Promise<void> {
    try {
      await bridge.call('picker.pick', { path })
      picker.value = null
    } catch (error) {
      fail(error)
      await loadPicker().catch(() => undefined)
    }
  }

  /** Answers the open picker like Esc: the recording stays in the queue. */
  async function skipPicker(): Promise<void> {
    try {
      await bridge.call('picker.skip', {})
      picker.value = null
    } catch (error) {
      fail(error)
      await loadPicker().catch(() => undefined)
    }
  }

  /** Marks done notices as seen, then reads the list again. */
  async function markNoticesSeen(ids: string[]): Promise<void> {
    if (ids.length === 0) return
    try {
      await bridge.call('notices.seen', { ids })
    } catch (error) {
      fail(error)
    }
    await loadNotices().catch(() => undefined)
  }

  /** "Say more" on a done item: a new recording that follows up on it. */
  function sayMore(itemId: string): Promise<void> {
    return startRecording(itemId)
  }

  function cancelPendingSearch(): void {
    clearTimeout(searchTimer)
    searchTimer = undefined
    finishPendingSearch?.()
    finishPendingSearch = undefined
  }

  async function runSearch(number: number, text: string, status: SearchFilter): Promise<void> {
    try {
      const reply = await bridge.call('items.search', status === 'all' ? { text } : { text, status })
      if (number !== searchNumber) return
      searchState.results = reply.items
      searchState.error = undefined
    } catch (error) {
      if (number !== searchNumber) return
      searchState.results = []
      searchState.error = errorText(error)
    }
    searchState.loading = false
  }

  /**
   * Searches the items for what the user typed. It waits for searchDelayMilliseconds after the last call, and a slower
   * old reply never replaces a newer one. The returned promise is done when this search is answered or replaced.
   */
  function search(query: string, status: SearchFilter = searchState.status): Promise<void> {
    cancelPendingSearch()
    searchNumber += 1
    const number = searchNumber
    searchState.query = query
    searchState.status = status
    const text = query.trim().slice(0, searchTextLimit)
    if (text === '') {
      searchState.results = []
      searchState.error = undefined
      searchState.loading = false
      return Promise.resolve()
    }
    searchState.loading = true
    return new Promise<void>((resolve) => {
      finishPendingSearch = resolve
      searchTimer = setTimeout(() => {
        searchTimer = undefined
        finishPendingSearch = undefined
        void runSearch(number, text, status).then(resolve)
      }, searchDelayMilliseconds)
    })
  }

  /** A status chip: the same words searched again with the new status. */
  function setSearchStatus(status: SearchFilter): Promise<void> {
    return search(searchState.query, status)
  }

  /** Mod+K or the search button: the box opens in the bar. */
  function openSearch(): void {
    searchOpen.value = true
  }

  /** Esc, the clear button and Clear search: the words and the status go back to nothing, the box closes and the queue comes back. */
  function closeSearch(): void {
    searchOpen.value = false
    void search('', 'all')
  }

  /** Opens the result like a queue row: the item is selected, and the tab follows where the item lives. */
  function openSearchResult(itemId: string): void {
    const hit = searchHits.value.find((entry) => entry.item.id === itemId)
    const found = allItems.value.find((item) => item.id === itemId) ?? hit?.item
    if (found !== undefined) tab.value = found.state === 'done' || found.state === 'done-by-you' ? 'done' : 'now'
    searchOpened.value = hit
    filter.value = 'all'
    selectedId.value = itemId
    searchOpen.value = false
    void search('', 'all')
  }

  /**
   * The app asked to open an item (Open on a notice, the done banner, a pointroo:// link). Search and Settings close, the tab follows
   * where the item lives and it is selected. An item the queue does not know yet: the queue is loaded once, then it is selected if found.
   */
  async function focusItem(itemId: string): Promise<void> {
    closeSearch()
    view.value = 'queue'
    let found = itemById(itemId)
    if (found === undefined) {
      await refresh()
      found = itemById(itemId)
    }
    if (found === undefined) return
    tab.value = found.state === 'done' || found.state === 'done-by-you' ? 'done' : 'now'
    searchOpened.value = undefined
    filter.value = 'all'
    selectedId.value = itemId
  }

  function projectById(projectId: string): Project | undefined {
    return projects.value.find((project) => project.id === projectId)
  }

  function itemById(itemId: string): Item | undefined {
    return allItems.value.find((item) => item.id === itemId)
  }

  async function reroute(itemId: string, project: Project): Promise<UndoStep> {
    const previousName = itemById(itemId)?.project ?? null
    await bridge.call('items.reroute', { id: itemId, project: project.folder })
    return { itemId, previousName }
  }

  /** Sends or moves items to a project, then shows a toast with Undo. */
  async function send(itemIds: string[], projectId: string): Promise<void> {
    const project = projectById(projectId)
    if (project === undefined) {
      showToast('That project is not there any more.', 'warn', false)
      return
    }
    const steps: UndoStep[] = []
    try {
      for (const itemId of itemIds) steps.push(await reroute(itemId, project))
    } catch (error) {
      fail(error)
    }
    if (steps.length === 0) return
    const first = steps[0]
    const verb = first !== undefined && first.previousName === null ? 'Sent' : 'Moved'
    showToast(steps.length > 1 ? `${verb} ${steps.length} to ${project.name}` : `${verb} to ${project.name}`, 'ok', true)
    undoSteps = steps
    await refresh()
  }

  async function undo(): Promise<void> {
    const steps = undoSteps
    const revertSetting = settingUndo
    dismissToast()
    if (revertSetting !== undefined) {
      await revertSetting()
      return
    }
    try {
      for (const step of steps) {
        if (step.previousName === null) {
          await bridge.call('items.unroute', { id: step.itemId })
        } else {
          const previous = projects.value.find((project) => project.name === step.previousName)
          if (previous === undefined) throw new Error('The old project is not there any more.')
          await bridge.call('items.reroute', { id: step.itemId, project: previous.folder })
        }
      }
    } catch (error) {
      fail(error)
    }
    await refresh()
  }

  async function act(run: () => Promise<unknown>, message: string): Promise<void> {
    try {
      await run()
      showToast(message, 'ok', false)
    } catch (error) {
      fail(error)
    }
    await refresh()
  }

  function done(itemId: string): Promise<void> {
    return act(() => bridge.call('items.done', { id: itemId }), 'Marked done')
  }

  function reopen(itemId: string): Promise<void> {
    return act(() => bridge.call('items.reopen', { id: itemId }), 'Open again')
  }

  async function trash(itemId: string): Promise<void> {
    await act(() => bridge.call('items.trash', { id: itemId }), 'Moved to Trash')
    if (selectedId.value === itemId) selectedId.value = undefined
  }

  /** Two lines an agent can act on: what is new, and how to get it (the same words as the old window). */
  function pointerText(item: Item): string {
    const open = nowItems.value.filter((entry) => entry.state === 'waiting' || entry.state === 'not-sent').length
    const more = open > 1 ? ` (${open} recordings to fix)` : ''
    return `New in Pointroo: "${item.title}…"${more}\nFix them all: the pointroo MCP get_open_items, then mark_done each when it is fixed.`
  }

  async function copyFor(itemId: string): Promise<void> {
    const item = itemById(itemId)
    if (item === undefined) return
    try {
      await bridge.call('clipboard.copy', { text: pointerText(item) })
      showToast('Copied. Paste it into your agent', 'ok', false)
    } catch (error) {
      fail(error)
    }
  }

  async function copyText(text: string): Promise<void> {
    try {
      await bridge.call('clipboard.copy', { text })
      showToast('Copied', 'ok', false)
    } catch (error) {
      fail(error)
    }
  }

  async function answer(question: Item['question'], text: string): Promise<void> {
    if (question?.id === undefined) return
    try {
      await bridge.call('questions.answer', { id: question.id, text })
      showToast('Answer sent', 'ok', false)
    } catch (error) {
      fail(error)
    }
    await refresh()
  }

  /** Puts a question off. It comes back after laterMinutes. There is no undo in the app, so the toast has none either. */
  async function later(question: Item['question']): Promise<void> {
    if (question?.id === undefined) return
    try {
      await bridge.call('questions.later', { id: question.id, minutes: laterMinutes })
      showToast(`Back in ${laterMinutes} minutes.`, 'ok', false)
    } catch (error) {
      fail(error)
    }
    await refresh()
  }

  /** Loads a whole recording once the user opens the Recording section. A loaded one is kept; a failed one is tried again. */
  async function loadRecording(session: string): Promise<void> {
    const existing = recordings.value[session]
    if (existing !== undefined && existing.state !== 'error') return
    recordings.value = { ...recordings.value, [session]: { state: 'loading', said: [], frames: [], points: [] } }
    try {
      recordings.value = { ...recordings.value, [session]: toRecordingView(await bridge.call('session.get', { session })) }
    } catch (error) {
      recordings.value = { ...recordings.value, [session]: { state: 'error', message: errorText(error), said: [], frames: [], points: [] } }
    }
  }

  async function allow(which: PermissionName): Promise<void> {
    try {
      await bridge.call('permissions.ask', { which })
    } catch (error) {
      fail(error)
    }
  }

  /** Stops one auto-start run, then asks for the status again. A run that already ended gets a quiet toast. */
  async function stopAutoRun(project: string): Promise<void> {
    if (stoppingRuns.value.includes(project)) return
    stoppingRuns.value = [...stoppingRuns.value, project]
    try {
      const reply = await bridge.call('autoRuns.stop', { project })
      if (!reply.stopped) showToast('That run already ended', 'muted', false)
      await loadStatus()
    } catch (error) {
      fail(error)
    } finally {
      stoppingRuns.value = stoppingRuns.value.filter((path) => path !== project)
    }
  }

  /** Reads the newest lines of the auto-start log. A failed read shows the usual toast and leaves the panel closed if it was closed. */
  async function loadAutoRunLog(): Promise<void> {
    autoRunLogLoading.value = true
    try {
      autoRunLog.value = (await bridge.call('autoRuns.log', { lines: autoRunLogLines })).lines
    } catch (error) {
      fail(error)
    } finally {
      autoRunLogLoading.value = false
    }
  }

  /** Hide on the log panel: the lines are forgotten, so the next Show log reads them fresh. */
  function hideAutoRunLog(): void {
    autoRunLog.value = undefined
  }

  /** Asks the app to move the agents server to the next free port. */
  async function useAnotherPort(): Promise<void> {
    try {
      await bridge.call('server.useAnotherPort', {})
      showToast('Asked.', 'ok', false)
    } catch (error) {
      fail(error)
    }
  }

  /** Asks the app to look for a new version. */
  async function checkUpdates(): Promise<void> {
    try {
      await bridge.call('app.checkUpdates', {})
      showToast('Asked.', 'ok', false)
    } catch (error) {
      fail(error)
    }
  }

  async function loadSettings(): Promise<void> {
    const reply = await bridge.call('settings.get', {})
    if ('values' in reply) settings.value = reply.values
    settingsLoaded.value = true
  }

  /** Opens Settings in the window and asks the app for the saved values and the permissions again. */
  async function openSettings(): Promise<void> {
    view.value = 'settings'
    try {
      await Promise.all([loadSettings(), loadStatus()])
    } catch (error) {
      fail(error)
    }
  }

  function closeSettings(): void {
    view.value = 'queue'
  }

  /**
   * Saves one setting at once. The screen shows the new value straight away; if the app refuses, the old value comes back
   * and a toast says why. A saved change shows a toast (with Undo) that says `message`.
   */
  async function setSetting(key: SettingKey, value: SettingValue, message: string, announce = true): Promise<void> {
    const previous = settings.value[key]
    settings.value = { ...settings.value, [key]: value }
    try {
      const reply = await bridge.call('settings.set', { key, value })
      settings.value = { ...settings.value, [key]: reply.value }
    } catch (error) {
      if (previous === undefined) {
        const restored = { ...settings.value }
        delete restored[key]
        settings.value = restored
      } else {
        settings.value = { ...settings.value, [key]: previous }
      }
      fail(error)
      return
    }
    if (!announce) return
    if (previous === undefined) {
      showToast(message, 'ok', false)
      return
    }
    showToast(message, 'ok', true)
    settingUndo = () => setSetting(key, previous, 'Change undone', false)
  }

  function select(itemId: string | undefined): void {
    selectedId.value = itemId
  }

  /** Cmd+1 to 9 jump to the project at that place in the sidebar. */
  function selectProjectNumber(number: number): void {
    const project = projects.value[number - 1]
    if (project !== undefined) filter.value = project.id
  }

  return reactive({
    loading,
    tab,
    filter,
    selectedId,
    toast,
    recording,
    picker,
    notices,
    lastSent,
    undoSent,
    noticeCount: computed(() => notices.value.length),
    searchState,
    searchOpen,
    searchHits,
    setSearchStatus,
    openSearch,
    closeSearch,
    openSearchResult,
    focusItem,
    startRecording,
    stopRecording,
    cancelRecording,
    loadRecordingState,
    loadPicker,
    pickProject,
    skipPicker,
    loadNotices,
    markNoticesSeen,
    sayMore,
    search,
    status,
    projects,
    rows,
    selectedItem,
    emptyKind,
    banner,
    sessionsText,
    agentsText,
    nowCount: computed(() => nowItems.value.length),
    doneCount: computed(() => doneItems.value.length),
    view,
    settings,
    settingsLoaded,
    openSettings,
    closeSettings,
    setSetting,
    start,
    startFloating,
    refresh,
    send,
    undo,
    done,
    reopen,
    trash,
    copyFor,
    copyText,
    answer,
    later,
    recordings,
    loadRecording,
    allow,
    useAnotherPort,
    checkUpdates,
    stopAutoRun,
    stoppingRuns,
    autoRunLog,
    autoRunLogLoading,
    loadAutoRunLog,
    hideAutoRunLog,
    select,
    selectProjectNumber,
    showToast,
    dismissToast,
    itemById,
  })
}

export type Store = ReturnType<typeof createStore>
