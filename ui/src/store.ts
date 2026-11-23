// What the window knows: the items, projects, status and questions from the app, and what the user has picked.
// The app tells the page when something changed (events); the store then asks again. Every action goes through the bridge.
import { computed, reactive, ref } from 'vue'
import type { Bridge } from './bridge'
import { errorText } from './bridge'
import type { Item, MainBanner, MainTab, MainToast, Project } from './parts/types'
import type { BridgeAppStatus, BridgeItem, BridgeProject, BridgeQuestion, PermissionName, RecordingPhase } from './types'
import { matchQuestions, toViewItem, toViewProjects } from './viewModel'

const undoSeconds = 5
const plainToastSeconds = 3

interface UndoStep {
  itemId: string
  /** The project the item was in before; null for a first send. */
  previousName: string | null
}

export function createStore(bridge: Bridge) {
  const bridgeItems = ref<BridgeItem[]>([])
  const bridgeProjects = ref<BridgeProject[]>([])
  const questions = ref<BridgeQuestion[]>([])
  const status = ref<BridgeAppStatus | undefined>(undefined)
  const recording = reactive<{ phase: RecordingPhase; pointCount: number }>({ phase: 'idle', pointCount: 0 })
  const loading = ref(true)
  const tab = ref<MainTab>('now')
  const filter = ref('all')
  const selectedId = ref<string | undefined>(undefined)
  const toast = ref<MainToast | undefined>(undefined)
  const now = ref(new Date())

  let toastTimer: number | undefined
  let undoSteps: UndoStep[] = []
  let refreshing: Promise<void> | undefined
  let refreshAgain = false

  const projects = computed<Project[]>(() => toViewProjects(bridgeProjects.value))
  const matched = computed(() => matchQuestions(bridgeItems.value, questions.value))
  const allItems = computed<Item[]>(() => bridgeItems.value.map((item) => toViewItem(item, matched.value.get(item.id), now.value)))
  const nowItems = computed(() => allItems.value.filter((item) => item.state !== 'done' && item.state !== 'done-by-you'))
  const doneItems = computed(() => allItems.value.filter((item) => item.state === 'done' || item.state === 'done-by-you'))
  const filterName = computed(() => projects.value.find((project) => project.id === filter.value)?.name)
  const rows = computed<Item[]>(() => {
    const list = tab.value === 'now' ? nowItems.value : doneItems.value
    if (filter.value === 'all') return list
    return list.filter((item) => item.project === filterName.value)
  })
  const selectedItem = computed(() => allItems.value.find((item) => item.id === selectedId.value))
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
    toast.value = { message, tone, undo }
    toastTimer = window.setTimeout(dismissToast, (undo ? undoSeconds : plainToastSeconds) * 1000)
  }

  function dismissToast(): void {
    window.clearTimeout(toastTimer)
    toast.value = undefined
    undoSteps = []
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
      await Promise.all([loadItems(), loadProjects(), loadQuestions(), loadStatus()])
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

  function start(): () => void {
    const stops = [
      bridge.on('items.changed', () => void refresh()),
      bridge.on('questions.changed', () => void refresh()),
      bridge.on('status.changed', (data) => {
        status.value = data
      }),
      bridge.on('recording.changed', (data) => {
        recording.phase = data.phase
        recording.pointCount = data.pointCount
      }),
    ]
    void refresh()
    return () => stops.forEach((stop) => stop())
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
    dismissToast()
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

  async function allow(which: PermissionName): Promise<void> {
    try {
      await bridge.call('permissions.ask', { which })
    } catch (error) {
      fail(error)
    }
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
    start,
    refresh,
    send,
    undo,
    done,
    reopen,
    trash,
    copyFor,
    copyText,
    answer,
    allow,
    select,
    selectProjectNumber,
    showToast,
    dismissToast,
    itemById,
  })
}

export type Store = ReturnType<typeof createStore>
