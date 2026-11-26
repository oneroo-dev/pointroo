// Turns what the app sends (types.ts) into what the screen parts draw (parts/types.ts).
import type { Crop, Item, ItemState, Project, RecordingView, RouteHow } from './parts/types'
import type { BridgeItem, BridgeProject, BridgeQuestion, BridgeSession, BridgeSessionPoint } from './types'

const routeWords: RouteHow[] = ['said', 'screen', 'followup', 'only', 'picked']

/** "now", "4 min ago", "2 hours ago", "yesterday", "3 days ago". An item with no date says "earlier". */
export function ageText(at: string | undefined, now: Date): string {
  if (at === undefined) return 'earlier'
  const then = new Date(at).getTime()
  if (Number.isNaN(then)) return 'earlier'
  const minutes = Math.max(0, Math.floor((now.getTime() - then) / 60000))
  if (minutes < 1) return 'now'
  if (minutes < 60) return `${minutes} min ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours} ${hours === 1 ? 'hour' : 'hours'} ago`
  const days = Math.floor(hours / 24)
  return days === 1 ? 'yesterday' : `${days} days ago`
}

/** The words the user said, with [n] where the cursor was: the first line of the body (Said (0:01 to 0:09): "..."). */
export function markedSaid(item: BridgeItem): string {
  const firstLine = item.body.split('\n')[0] ?? ''
  const match = /^Said \([^)]*\): "(.*)"$/.exec(firstLine)
  if (match !== null) return match[1] ?? ''
  return item.said ?? ''
}

/** Every "Pointed at" line that has a crop, in order: its number and a short caption. */
export function pointLines(body: string): { number: number; caption: string }[] {
  const lines: { number: number; caption: string }[] = []
  for (const line of body.split('\n')) {
    const match = /^- \[(\d+)\] (.*?)(?:; crop `[^`]*`)?$/.exec(line)
    if (match === null || !line.includes('; crop `')) continue
    lines.push({ number: Number(match[1]), caption: match[2] ?? '' })
  }
  return lines
}

function countPoints(body: string): number {
  return body.split('\n').filter((line) => /^- \[\d+\] /.test(line)).length
}

function cropsFor(item: BridgeItem): Crop[] {
  const lines = pointLines(item.body)
  return item.crops.map((_path, index) => {
    const line = lines[index]
    const crop: Crop = { number: line?.number ?? index + 1, caption: line?.caption ?? `Point ${index + 1}` }
    const url = item.cropURLs[index]
    if (url !== undefined) crop.url = url
    return crop
  })
}

/** For each question, the in-progress item of its project that the agent is working on (by name when known). */
export function matchQuestions(items: BridgeItem[], questions: BridgeQuestion[]): Map<string, BridgeQuestion> {
  const matched = new Map<string, BridgeQuestion>()
  for (const question of questions) {
    const candidates = items.filter((item) => item.status === 'in_progress' && item.project === question.project && !matched.has(item.id))
    const best = candidates.find((item) => item.by === question.agent) ?? candidates[0]
    if (best !== undefined) matched.set(best.id, question)
  }
  return matched
}

/** The app's guess for a not-sent item as a project id (the folder path). It sends the path or only the name; without either there is no guess. */
function suggestedProjectId(item: BridgeItem, projects: Project[]): string | undefined {
  if (item.suggested !== undefined && item.suggested !== '') return item.suggested
  if (item.suggestedName === undefined || item.suggestedName === '') return undefined
  return projects.find((project) => project.name === item.suggestedName)?.id
}

export function toViewItem(item: BridgeItem, question: BridgeQuestion | undefined, now: Date, projects: Project[] = []): Item {
  let state: ItemState
  if (item.status === 'done') state = item.by === undefined ? 'done-by-you' : 'done'
  else if (item.status === 'in_progress') state = question === undefined ? 'working' : 'asks'
  else state = item.project === undefined ? 'not-sent' : 'waiting'

  const crops = cropsFor(item)
  // A done item shows when it was finished; the others show when they were recorded.
  const when = item.status === 'done' ? (item.doneAt ?? item.at) : item.at
  const how = routeWords.find((word) => word === item.routeHow) ?? 'none'
  const result: Item = {
    id: item.id,
    project: item.project ?? null,
    state,
    title: item.title,
    said: item.said ?? '',
    points: Math.max(countPoints(item.body), crops.length),
    age: ageText(when, now),
    how,
    crops,
  }
  const marked = markedSaid(item)
  if (item.said !== undefined && marked !== '') result.said = marked
  if (when !== undefined) result.atText = new Date(when).toLocaleString()
  if (item.session !== '') result.session = item.session
  if (item.by !== undefined) result.agent = item.by
  if (item.note !== undefined) result.note = item.note
  if (item.afterURL !== undefined) result.afterUrl = item.afterURL
  const suggested = state === 'not-sent' ? suggestedProjectId(item, projects) : undefined
  if (suggested !== undefined) result.suggested = suggested
  if (question !== undefined) result.question = { id: question.id, text: question.text, choices: question.choices }
  return result
}

/** A project's id is its folder path. The list order from the app is kept: live projects first, then the rest. */
export function toViewProjects(projects: BridgeProject[]): Project[] {
  const hasLastUsed = projects.some((project) => project.lastUsed !== undefined)
  // With lastUsed from the app, rank 1 is the project used most recently (absent or unreadable date: never used, last).
  // Without it on any project, the app's order is kept.
  const ranked = hasLastUsed
    ? projects
        .map((project, index) => {
          const time = project.lastUsed === undefined ? Number.NaN : Date.parse(project.lastUsed)
          return { index, lastUsed: Number.isNaN(time) ? Number.NEGATIVE_INFINITY : time }
        })
        .sort((first, second) => second.lastUsed - first.lastUsed || first.index - second.index)
    : []
  return projects.map((project, index) => ({
    id: project.path,
    name: project.name,
    count: project.open + project.inProgress,
    listening: project.live,
    sessionOpen: project.sessionOpen,
    folder: project.path,
    recentRank: hasLastUsed ? ranked.findIndex((entry) => entry.index === index) + 1 : index + 1,
  }))
}

/** One point as a line: "app - window - element". With none of those, the address; with nothing, "A point". */
function pointText(point: BridgeSessionPoint): string {
  const parts = [point.app, point.window, point.element].filter((part): part is string => part !== undefined && part !== '')
  if (parts.length > 0) return parts.join(' - ')
  return point.url !== undefined && point.url !== '' ? point.url : 'A point'
}

function durationText(seconds: number): string {
  return seconds < 60 ? `${Math.max(1, Math.round(seconds))} sec` : `${Math.round(seconds / 60)} min`
}

/** A whole recording from session.get as the Recording section draws it. */
export function toRecordingView(recording: BridgeSession): RecordingView {
  const started = new Date(recording.started)
  const startedText = Number.isNaN(started.getTime()) ? '' : `, started ${started.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`
  return {
    state: 'ready',
    said: recording.said.map((word) => word.text.trim()).filter((text) => text !== ''),
    frames: recording.frames,
    points: recording.points.map(pointText),
    summary: `${durationText(recording.duration)}${startedText}`,
  }
}
