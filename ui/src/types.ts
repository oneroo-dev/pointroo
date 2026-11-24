// What the app (Swift) sends over the bridge. Matches Sources/PointAndYap/WebBridge.swift. A key marked ? is left out when it has no value.

export type BridgeErrorCode = 'bad_request' | 'unknown_method' | 'bad_params' | 'not_found' | 'not_available' | 'refused' | 'busy'

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
  /** ISO date when the item was marked done. Only on items from done.recent (R25). */
  doneAt?: string
}

export interface BridgeSessionWord {
  text: string
  /** Seconds from the start of the recording. */
  start: number
  end: number
}

export interface BridgeSessionPoint {
  at: number
  x: number
  y: number
  app?: string
  window?: string
  url?: string
  element?: string
}

/** A whole recording (session.get, R25). */
export interface BridgeSession {
  session: string
  /** ISO date. */
  started: string
  /** Seconds. */
  duration: number
  said: BridgeSessionWord[]
  points: BridgeSessionPoint[]
  /** One pointroo-image:// address per frame. */
  frames: string[]
  /** The ids of the items this recording made. */
  items: string[]
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

/** A headless agent run that auto-start has going: the project folder and when it started (ISO date). */
export interface BridgeAutoRun {
  project: string
  startedAt: string
}

/** The last auto-start run that ended: the folder, when it ended (ISO date), the exit code (-1 = could not start) and the cost in dollars when known. */
export interface BridgeLastAutoRun {
  project: string
  endedAt: string
  exitCode: number
  cost?: number
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
  autoRuns: BridgeAutoRun[]
  lastAutoRun?: BridgeLastAutoRun
}

export type PermissionName = 'microphone' | 'screenRecording' | 'accessibility'

/** The auto-start settings that are one of a few words (autoStartBudget is a number of dollars, 0.5 to 20). */
export type AutoStartChoiceKey = 'autoStartAgent' | 'autoStartModel' | 'autoStartEffort' | 'autoStartPermission'

/** Every setting the page may read and write (WebBridge.allowedSettings). Flags are true or false; locale is a language id; the auto-start ones are words or a number. */
export type SettingKey =
  | AutoStartChoiceKey
  | 'autoStartBudget'
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
  | 'kitFloating'
  | 'locale'

export type SettingValue = boolean | string | number

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
  // Added by R25 (the Swift side).
  'done.recent': { params: { limit?: number }; result: { items: BridgeItem[] } }
  'session.get': { params: { session: string }; result: BridgeSession }
  'questions.later': { params: { id: string; minutes?: number }; result: { snoozed: true; until: number } }
  'clipboard.copy': { params: { text: string }; result: { copied: true } }
  'window.startDrag': { params: Record<string, never>; result: { dragging: true } }
  'server.useAnotherPort': { params: Record<string, never>; result: { asked: true } }
  'app.checkUpdates': { params: Record<string, never>; result: { asked: true } }
  // Added for W5 (the Swift side is on main).
  'items.search': { params: ItemsSearchParams; result: { items: SearchResult[] } }
  'recording.start': { params: { followUp?: string }; result: { started: true; followUp?: string } }
  'recording.stop': { params: Record<string, never>; result: { stopped: true } }
  'recording.cancel': { params: Record<string, never>; result: { cancelled: true } }
  'recording.get': { params: Record<string, never>; result: RecordingSnapshot }
  'picker.get': { params: Record<string, never>; result: PickerSnapshot }
  'picker.pick': { params: { path: string }; result: { picked: true } }
  'picker.skip': { params: Record<string, never>; result: { skipped: true } }
  'notices.list': { params: { limit?: number }; result: { notices: Notice[] } }
  'notices.seen': { params: { ids: string[] }; result: { seen: number } }
}

export type BridgeMethod = keyof BridgeMethods

/** "picking" is the time the project picker is open. */
export type RecordingPhase = 'idle' | 'recording' | 'processing' | 'picking'

/** The answer of recording.get. */
export interface RecordingSnapshot {
  phase: RecordingPhase
  /** ISO date, only while recording. */
  startedAt?: string
  points: number
  /** The last few spoken words, when the app has them. */
  words?: string[]
}

export interface PickerChoice {
  name: string
  path: string
  /** The number key, 1 to 9. */
  key: number
  /** True for the folder the router guessed. */
  suggested: boolean
}

/** The answer of picker.get: closed, or open with the choices in number-key order. */
export type PickerSnapshot =
  | { open: false }
  | {
      open: true
      /** The recording the picker asks about. */
      session?: string
      choices: PickerChoice[]
      /** Whole seconds before it skips by itself. */
      countdown?: number
    }

/** A done item an agent finished that the user has not seen yet. */
export interface DoneNotice {
  kind: 'done'
  /** The item id. */
  id: string
  agent: string
  project?: string
  projectName?: string
  note?: string
  /** The first crop. */
  cropURL?: string
  afterURL?: string
  /** ISO date. */
  at?: string
}

/** A pending question: the Question keys plus kind "question". */
export interface QuestionNotice extends BridgeQuestion {
  kind: 'question'
}

export type Notice = DoneNotice | QuestionNotice

/** An item from items.search plus where the text was found. */
export interface SearchResult extends BridgeItem {
  match: { field: SearchField; snippet: string }
}

/** The fields items.search can hit. */
export type SearchField = 'title' | 'body' | 'said' | 'alsoSaid' | 'note' | 'project' | 'firstElement'

export type SearchStatus = BridgeStatus | 'trashed' | 'any'

/** The status chips of the search screen. "all" leaves the status param out (every item except the trashed ones). */
export type SearchFilter = 'open' | 'in_progress' | 'done' | 'all'

export interface ItemsSearchParams {
  /** 1 to 200 characters. */
  text: string
  status?: SearchStatus
  /** Whole number 1 to 100, default 30. */
  limit?: number
}

/** How the app chose the project by itself (a route the user picked never sends route.sent). */
export type SentHow = 'said' | 'screen' | 'followup' | 'only'

/** The data of route.sent: a recording the app sent to a project by itself. */
export interface RouteSent {
  session: string
  /** The project folder. */
  project: string
  projectName: string
  how: SentHow
  /** The item ids of the recording, for items.unroute. */
  ids: string[]
}

/** Every event the app can send, with its data. */
export interface BridgeEvents {
  'items.changed': { count: number; open: number; inProgress: number }
  'questions.changed': { count: number }
  'recording.changed': { phase: RecordingPhase; pointCount: number }
  'picker.changed': { open: boolean; session?: string }
  'notices.changed': { count: number }
  'route.sent': RouteSent
  'item.focus': { id: string }
  'status.changed': BridgeAppStatus
}

export type BridgeEventName = keyof BridgeEvents

/** The picker while it is open (the open case of PickerSnapshot). */
export type OpenPicker = Extract<PickerSnapshot, { open: true }>
