// What the three floating panels show, worked out from the store. Plain functions, so tests need no page.
import type { ProjectTile } from './parts/types'
import type { DoneNotice, Notice, OpenPicker, QuestionNotice, RecordingPhase, RouteSent, SentHow } from './types'

/** A question card shows at most this many choices (the keys 1 to 3). */
export const maxChoices = 3

/** How long "Sent to X / Undo" stays on the pill before it goes by itself. */
export const sentSeconds = 6

/** The small line under "Sent to X": why the app chose that project. */
const sentNotes: Record<SentHow, string> = {
  said: 'You said the name',
  screen: 'Matched from the screen',
  followup: 'Follow-up on a finished item',
  only: 'Only session listening',
}

export interface SentView {
  /** "Sent to Pointroo". */
  label: string
  note: string
}

export interface PillView {
  phase: 'recording' | 'processing'
  elapsed: string
  points: number
}

/** "0:12": minutes and seconds since the recording started. */
export function elapsedText(startedAt: string | undefined, nowMilliseconds: number): string {
  if (startedAt === undefined) return '0:00'
  const started = Date.parse(startedAt)
  if (Number.isNaN(started)) return '0:00'
  const seconds = Math.max(0, Math.floor((nowMilliseconds - started) / 1000))
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`
}

/**
 * The pill: recording or making items; nothing in any other phase. The app sets the point count to 0 when the recording stops,
 * so while processing the last count seen while recording is shown.
 */
export function pillView(
  recording: { phase: RecordingPhase; pointCount: number; startedAt: string | undefined },
  nowMilliseconds: number,
  lastPoints: number,
): PillView | undefined {
  if (recording.phase === 'recording') {
    return { phase: 'recording', elapsed: elapsedText(recording.startedAt, nowMilliseconds), points: recording.pointCount }
  }
  if (recording.phase === 'processing') {
    return { phase: 'processing', elapsed: '0:00', points: recording.pointCount > 0 ? recording.pointCount : lastPoints }
  }
  return undefined
}

function lastFolderName(path: string): string {
  const parts = path.split('/').filter((part) => part !== '')
  return parts[parts.length - 1] ?? ''
}

/** What the "Sent to" pill says: the project's name (else its folder's name, else "the project") and why it was chosen. */
export function sentView(sent: RouteSent | undefined): SentView | undefined {
  if (sent === undefined) return undefined
  const name = sent.projectName !== '' ? sent.projectName : lastFolderName(sent.project)
  return { label: `Sent to ${name === '' ? 'the project' : name}`, note: sentNotes[sent.how] ?? '' }
}

/** The picker rows in number-key order. The id of a row is the folder, which is what picker.pick wants. */
export function pickerTiles(picker: OpenPicker): ProjectTile[] {
  return picker.choices.map((choice) => ({ id: choice.path, name: choice.name, suggested: choice.suggested, live: true }))
}

/** When the picker skips by itself (milliseconds since 1970), or undefined when the app gave no countdown. */
export function pickerEndsAt(picker: OpenPicker, nowMilliseconds: number): number | undefined {
  return picker.countdown === undefined ? undefined : nowMilliseconds + picker.countdown * 1000
}

/** Whole seconds left until the picker skips (never below 0). */
export function secondsLeft(endsAt: number, nowMilliseconds: number): number {
  return Math.max(0, Math.ceil((endsAt - nowMilliseconds) / 1000))
}

/** The notice the card shows now: the newest one (the app sends them newest first). */
export function currentNotice(notices: Notice[]): Notice | undefined {
  return notices[0]
}

/** The project name on a card: the name the app gave, else the folder's name, else a plain word. */
export function noticeProject(notice: Notice): string {
  const name = notice.kind === 'question' ? notice.project : (notice.projectName ?? lastFolderName(notice.project ?? ''))
  return name === '' ? 'An agent' : name
}

export function noticeChoices(notice: QuestionNotice): string[] {
  return notice.choices.slice(0, maxChoices)
}

export function doneNoticeNote(notice: DoneNotice): string {
  return notice.note ?? 'Finished.'
}

/** The size to tell the app: the page's size (whole points, rounded up) while it has something to show, else 0 by 0 (the app hides the panel). */
export function sizeToReport(width: number, height: number, hasContent: boolean): { width: number; height: number } {
  return hasContent ? { width: Math.ceil(width), height: Math.ceil(height) } : { width: 0, height: 0 }
}
