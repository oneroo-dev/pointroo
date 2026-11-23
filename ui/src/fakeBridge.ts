// The bridge for a plain browser (npm run dev): answers from the mockups' sample data and keeps changes in memory.
// It also answers the methods W2 adds, so every button can be tried without the app.
import { asks, done, doneByYou, doneOlder, notSent, pointrooWaiting, waiting, working } from '../mockups/data/items'
import { projects } from '../mockups/data/projects'
import type { Item } from './parts/types'
import type { Bridge } from './bridge'
import { BridgeError } from './bridgeError'
import type {
  BridgeAppStatus,
  BridgeEventName,
  BridgeEvents,
  BridgeItem,
  BridgeMethod,
  BridgeMethods,
  BridgeProject,
  BridgeQuestion,
  ItemGroup,
  ItemsListParams,
  PermissionName,
  SettingKey,
  SettingValue,
} from './types'

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
    cropURLs: [],
    status,
    alsoSaid: [],
    at: new Date(Date.now() - minutesAgo(item.age) * 60000).toISOString(),
    said: item.said,
  }
  if (item.project !== null) result.project = item.project
  if (item.agent !== undefined && status !== 'open') result.by = item.agent
  if (item.note !== undefined) result.note = item.note
  if (item.how !== 'none') result.routeHow = item.how
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
    locale: '',
  }
  const languageIds = ['', 'en-US', 'de-DE', 'fr-FR', 'es-ES', 'it-IT', 'pt-BR', 'nl-NL', 'ja-JP', 'zh-CN']

  function isSettingKey(key: string | undefined): key is SettingKey {
    return key !== undefined && Object.hasOwn(settingValues, key)
  }

  function setSetting(key: string, value: SettingValue): { key: string; value: SettingValue } {
    if (!isSettingKey(key)) throw new BridgeError('refused', 'That setting cannot be changed.')
    if (key === 'locale') {
      if (typeof value !== 'string' || !languageIds.includes(value)) throw new BridgeError('bad_params', 'locale must be one of the known values.')
    } else if (typeof value !== 'boolean') {
      throw new BridgeError('bad_params', `${key} is on or off (true or false).`)
    }
    settingValues[key] = value
    return { key, value }
  }

  function statusNow(): BridgeAppStatus {
    return { mcpRunning: true, mcpPort: 6742, mcpText: 'Shared MCP server: running on 127.0.0.1:6742', sessions: 2, agents: ['Claude Code', 'Codex'], ...permissions }
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
    'items.done': (params) => {
      const item = find(params.id)
      item.status = 'done'
      changed()
      return { done: true }
    },
    'items.reopen': (params) => {
      find(params.id).status = 'open'
      changed()
      return { reopened: true }
    },
    'items.trash': (params) => {
      find(params.id)
      items = items.filter((item) => item.id !== params.id)
      changed()
      return { trashed: true }
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
    'clipboard.copy': () => ({ copied: true }),
    'window.startDrag': () => ({ dragging: true }),
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
