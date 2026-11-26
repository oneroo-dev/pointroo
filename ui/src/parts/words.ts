import type { RooStateMarkState } from '@roo/kit/states'
import { projectNameFor } from './projects'
import type { Item, ItemState, Project, RouteHow } from './types'

export interface Mark {
  state: RooStateMarkState
  label: string
}

const marks: Record<ItemState, Mark> = {
  waiting: { state: 'muted', label: 'Waiting' },
  working: { state: 'running', label: 'Working' },
  asks: { state: 'warn', label: 'Asks you' },
  done: { state: 'ok', label: 'Done' },
  'done-by-you': { state: 'ok', label: 'Done by you' },
  'not-sent': { state: 'muted', label: 'Not sent' },
  processing: { state: 'running', label: 'Working' },
}

export function markFor(item: Item): Mark {
  return marks[item.state]
}

export function pointsWord(count: number): string {
  return `${count} ${count === 1 ? 'point' : 'points'}`
}

export function subtitleFor(item: Item, doneTab = false): string {
  if (doneTab && item.note) return `${item.project ?? 'Not sent'} · ${item.age} · ${item.note.replace(/\s+/g, ' ').trim()}`
  if (item.state === 'not-sent') return `Not sent yet · ${pointsWord(item.points)} · ${item.age}`
  const agent = item.state === 'working' && item.agent ? ` · ${item.agent}` : ''
  return `${item.project}${agent} · ${pointsWord(item.points)} · ${item.age}`
}

function squash(text: string): string {
  return text.replace(/\[\d+\]/g, ' ').replace(/\s+/g, ' ').trim()
}

/** What the user said without the [n] point marks, on one line. */
export function plainWords(text: string): string {
  return squash(text)
}

/** The quiet part of a row: where it went and when. An item with no project says "Not sent". */
export function whereLine(item: Item, projects: Project[] = []): string {
  return `${projectNameFor(projects, item.project) ?? 'Not sent'} · ${item.age}`
}
export function isFinished(item: Item): boolean {
  return item.state === 'done' || item.state === 'done-by-you'
}

/** How soon an item needs the user: new arrivals, then questions, then not sent, then working, then waiting, then done. */
function queueRank(item: Item, freshIds: string[]): number {
  if (freshIds.includes(item.id)) return 0
  switch (item.state) {
    case 'asks':
      return 1
    case 'not-sent':
    case 'processing':
      return 2
    case 'working':
      return 3
    case 'waiting':
      return 4
    default:
      return 5
  }
}

/** The queue in the order of the design: what needs you first. Items of the same rank keep the order they came in. */
export function orderQueue(items: Item[], freshIds: string[] = []): Item[] {
  return items
    .map((item, index) => ({ item, index, rank: queueRank(item, freshIds) }))
    .sort((first, second) => first.rank - second.rank || first.index - second.index)
    .map((entry) => entry.item)
}

export interface SaidPiece {
  text: string
  /** True when the item's own words include this piece. */
  own: boolean
}

/** The phrases of a whole recording, each flagged when the item's own words (with their [n] marks) contain it. */
export function markOwnWords(phrases: string[], ownWords: string): SaidPiece[] {
  const own = squash(ownWords)
  return phrases.map((text) => {
    const plain = squash(text)
    return { text, own: own !== '' && plain !== '' && own.includes(plain) }
  })
}

export function sentToWords(how: RouteHow, followsTitle?: string): string {
  switch (how) {
    case 'said':
      return 'You said "{project}".'
    case 'screen':
      return 'It was on screen.'
    case 'followup':
      return `Follow-up to "${followsTitle ?? 'the last item'}".`
    case 'only':
      return 'Only project with a session.'
    case 'picked':
      return 'You picked it.'
    default:
      return 'Not sent yet.'
  }
}

export function sentToLine(item: Item, projects: Project[] = []): string {
  return sentToWords(item.how, item.followsTitle).replace('{project}', projectNameFor(projects, item.project) ?? '')
}

export function shortReason(how: RouteHow): string {
  const words: Record<RouteHow, string> = {
    said: 'you said its name',
    screen: 'it was on screen',
    followup: 'follow-up',
    only: 'only project',
    picked: 'you picked it',
    none: 'not sent yet',
  }
  return words[how]
}
