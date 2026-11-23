// The shapes the screen parts draw. The mockups fill them with sample data; the app fills them from the bridge (see ../viewModel.ts).
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

export interface Project {
  id: string
  name: string
  count: number
  listening: boolean
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
}
