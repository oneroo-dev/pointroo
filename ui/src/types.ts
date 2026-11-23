// What the app (Swift) sends over the bridge. Matches Sources/PointAndYap/WebBridge.swift. A key marked ? is left out when it has no value.

export type BridgeErrorCode = 'bad_request' | 'unknown_method' | 'bad_params' | 'not_found' | 'not_available' | 'refused'

export type BridgeStatus = 'open' | 'in_progress' | 'done'

export interface BridgeItem {
  id: string
  session: string
  n: number
  title: string
  body: string
  crops: string[]
  /** One pointroo-image:// address per crop, same order as `crops`. */
  cropURLs: string[]
  /** The address of after/01.jpg, only when that file exists. */
  afterURL?: string
  status: BridgeStatus
  alsoSaid: string[]
  /** ISO date. */
  at?: string
  by?: string
  note?: string
  project?: string
  routeHow?: string
  priority?: string
  commit?: string
  branch?: string
  duplicateOf?: string
  said?: string
  firstElement?: string
  duration?: number
  /** The router's best guess for a not-sent item: a project path. Only there when the app (R24) sends it. */
  suggested?: string
  /** The same guess as a project name. Only there when the app (R24) sends it. */
  suggestedName?: string
}

export interface BridgeProjectRef {
  name: string
  path: string
}

export interface BridgeProject {
  name: string
  path: string
  aliases: string[]
  live: boolean
  agents: string[]
  /** The picker's number key, given to the first nine live projects only. */
  key?: number
  open: number
  inProgress: number
  /** ISO 8601 date when an item last went to this project. Left out when never used (R24). */
  lastUsed?: string
}

export interface BridgeQuestion {
  id: string
  project: string
  agent: string
  text: string
  choices: string[]
  /** Seconds since 1970. */
  asked: number
}

export interface BridgeAppStatus {
  mcpRunning: boolean
  mcpPort: number
  mcpText: string
  sessions: number
  agents: string[]
  microphone: boolean
  screenRecording: boolean
  accessibility: boolean
}

export type PermissionName = 'microphone' | 'screenRecording' | 'accessibility'

/** Every setting the page may read and write (WebBridge.allowedSettings). Flags are true or false; locale is a language id. */
export type SettingKey =
  | 'sounds'
  | 'doubleControl'
  | 'escCancels'
  | 'redactSecrets'
  | 'connectAgents'
  | 'showNoSpeech'
  | 'holdToTalk'
  | 'listenAfterDone'
  | 'autoSendSingle'
  | 'kitWindow'
  | 'locale'

export type SettingValue = boolean | string

export type SettingsValues = Partial<Record<SettingKey, SettingValue>>

export interface ItemsListParams {
  status?: BridgeStatus
  project?: string
  maxAgeHours?: number
  groupBy?: 'project'
}

export interface ItemGroup {
  project: BridgeProjectRef | null
  items: BridgeItem[]
}

/** Every method the page may call, with its params and result. */
export interface BridgeMethods {
  'items.list': { params: ItemsListParams; result: { items: BridgeItem[] } | { groups: ItemGroup[] } }
  'projects.list': { params: Record<string, never>; result: { projects: BridgeProject[] } }
  'items.get': { params: { id: string }; result: { item: BridgeItem } }
  'items.reroute': { params: { id: string; project: string }; result: { moved: true } }
  'questions.list': { params: Record<string, never>; result: { questions: BridgeQuestion[] } }
  'questions.answer': { params: { id: string; text: string }; result: { answered: true } }
  'settings.get': { params: { key?: string }; result: { key: string; value: SettingValue } | { values: Record<string, SettingValue> } }
  'settings.set': { params: { key: string; value: SettingValue }; result: { key: string; value: SettingValue } }
  'status.get': { params: Record<string, never>; result: { status: BridgeAppStatus } }
  'permissions.ask': { params: { which: PermissionName }; result: { asked: true } }
  // Added by W2 (the Swift side). Until it lands the app answers not_available or unknown_method.
  'items.done': { params: { id: string; note?: string }; result: { done: true } }
  'items.reopen': { params: { id: string }; result: { reopened: true } }
  'items.trash': { params: { id: string }; result: { trashed: true } }
  'items.unroute': { params: { id: string }; result: { unrouted: true } }
  'clipboard.copy': { params: { text: string }; result: { copied: true } }
  'window.startDrag': { params: Record<string, never>; result: { dragging: true } }
  'server.useAnotherPort': { params: Record<string, never>; result: { asked: true } }
  'app.checkUpdates': { params: Record<string, never>; result: { asked: true } }
}

export type BridgeMethod = keyof BridgeMethods

export type RecordingPhase = 'idle' | 'recording' | 'processing'

/** Every event the app can send, with its data. */
export interface BridgeEvents {
  'items.changed': { count: number; open: number; inProgress: number }
  'questions.changed': { count: number }
  'recording.changed': { phase: RecordingPhase; pointCount: number }
  'status.changed': BridgeAppStatus
}

export type BridgeEventName = keyof BridgeEvents
