// Turns what the app sends (types.ts) into what the screen parts draw (parts/types.ts).
import type { Crop, Item, ItemState, Project, RouteHow } from './parts/types'
import type { BridgeItem, BridgeProject, BridgeQuestion } from './types'

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

export function toViewItem(item: BridgeItem, question: BridgeQuestion | undefined, now: Date): Item {
  let state: ItemState
  if (item.status === 'done') state = item.by === undefined ? 'done-by-you' : 'done'
  else if (item.status === 'in_progress') state = question === undefined ? 'working' : 'asks'
  else state = item.project === undefined ? 'not-sent' : 'waiting'

  const crops = cropsFor(item)
  const how = routeWords.find((word) => word === item.routeHow) ?? 'none'
  const result: Item = {
    id: item.id,
    project: item.project ?? null,
    state,
    title: item.title,
    said: item.said ?? '',
    points: Math.max(countPoints(item.body), crops.length),
    age: ageText(item.at, now),
    how,
    crops,
  }
  const marked = markedSaid(item)
  if (item.said !== undefined && marked !== '') result.said = marked
  if (item.at !== undefined) result.atText = new Date(item.at).toLocaleString()
  if (item.by !== undefined) result.agent = item.by
  if (item.note !== undefined) result.note = item.note
  if (item.afterURL !== undefined) result.afterUrl = item.afterURL
  if (question !== undefined) result.question = { id: question.id, text: question.text, choices: question.choices }
  return result
}

/** A project's id is its folder path. The list order from the app is kept: live projects first, then the rest. */
export function toViewProjects(projects: BridgeProject[]): Project[] {
  return projects.map((project, index) => ({
    id: project.path,
    name: project.name,
    count: project.open + project.inProgress,
    listening: project.live,
    folder: project.path,
    recentRank: index + 1,
  }))
}
