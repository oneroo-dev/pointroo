// The shapes the screen parts draw. The mockups fill them with sample data; the app fills them from the bridge (see ../viewModel.ts).
import type { SearchField } from '../types'

export type ItemState = 'waiting' | 'working' | 'asks' | 'done' | 'done-by-you' | 'not-sent' | 'processing'
export type RouteHow = 'said' | 'screen' | 'followup' | 'only' | 'picked' | 'none'

export interface Crop {
  number: number
  caption: string
  /** The picture of this crop (a pointroo-image:// address in the app). The mockups leave it out. */
  url?: string | undefined
}

export interface Item {
  id: string
  project: string | null
  state: ItemState
  title: string
  said: string
  points: number
  age: string
  /** The full time, for the tooltip on the age. */
  atText?: string | undefined
  agent?: string | undefined
  note?: string | undefined
  how: RouteHow
  followsTitle?: string | undefined
  /** The router's best guess (a project id) for a not-sent item. */
  suggested?: string | undefined
  crops: Crop[]
  /** The screen after the agent finished (a pointroo-image:// address). */
  afterUrl?: string | undefined
  question?: { id?: string | undefined; text: string; choices: string[] } | undefined
  /** The recording this item came from. The Recording section needs it. */
  session?: string | undefined
  /** What happened when Pointroo tried to wake the project's Claude session. Left out when it did not try. */
  wake?: WakeNote | undefined
}

/** What the wake did for one recording. `name` is the session that was woken (only for `woke`). */
export interface WakeNote {
  kind: 'woke' | 'no-session' | 'busy' | 'too-old'
  name?: string | undefined
}

/** One line of the Setup checklist: a green tick when `done`, else one button (or a progress word while `busy`). */
export interface SetupRow {
  id: string
  label: string
  description?: string | undefined
  state: 'done' | 'todo' | 'busy'
  /** The word next to the tick, for example "Allowed". Defaults to "Ready". */
  doneLabel?: string | undefined
  /** The button text when `todo`. */
  actionLabel?: string | undefined
  /** The word while `busy`, for example "Downloading...". */
  busyLabel?: string | undefined
  /** A small quiet line under the row. */
  note?: string | undefined
}

/** One open Claude session a project can be tied to. */
export interface WakeSessionChoice {
  value: string
  label: string
}

/** One project and who owns it. `owner` is "auto" or a session value. */
export interface WakeOwnerRow {
  projectId: string
  name: string
  owner: string
}

export interface WakeSettingsView {
  enabled: boolean
  owners: WakeOwnerRow[]
  sessions: WakeSessionChoice[]
  /** "Last: woke Tinkeroo for tinkeroo, 2 min ago". Left out when nothing woke yet. */
  lastWake?: string | undefined
}

export interface HintView {
  message: string
  tone: 'ok' | 'muted' | 'warn'
  actionLabel?: string | undefined
}

/** A whole recording, ready to draw (see viewModel.toRecordingView). */
export interface RecordingView {
  state: 'loading' | 'ready' | 'error'
  /** For the error state: the muted line. */
  message?: string | undefined
  /** What was said, one piece per phrase. */
  said: string[]
  /** One picture address per frame. */
  frames: string[]
  /** One line per point: app - window - element. */
  points: string[]
  /** "2 min, started 10:42". */
  summary?: string | undefined
}

/** One search result: the item as a queue row has it, and the field where the words were found with a line around the first hit. */
export interface SearchHit {
  item: Item
  match: { field: SearchField; snippet: string }
}

export interface Project {
  id: string
  name: string
  count: number
  /** An agent session there listens (it called wait_for_next lately). */
  listening: boolean
  /** A session runs there but does not listen. Left out in the mockups. */
  sessionOpen?: boolean | undefined
  folder: string
  /** 1 is the project that got an item most recently. */
  recentRank: number
}

export interface ProjectTile {
  id: string
  name: string
  suggested?: boolean | undefined
  live?: boolean | undefined
}

export type MainTab = 'now' | 'done'

/** A line above the list that tells the user something needs them. */
export interface MainBanner {
  kind: 'permission' | 'port-busy' | 'mcp-error' | 'no-session'
  title?: string | undefined
  description?: string | undefined
  /** For a permission banner: which one the Allow button asks for. */
  which?: 'microphone' | 'screenRecording' | 'accessibility' | undefined
}

export interface MainToast {
  message: string
  tone: 'ok' | 'muted' | 'warn'
  undo: boolean
  /** A text button next to the message (a hint's Retry). */
  actionLabel?: string | undefined
}
