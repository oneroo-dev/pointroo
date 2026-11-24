import type { RooStateMarkState } from '@roo/kit/states'
import type { Item, ItemState, RouteHow } from './types'

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

export function sentToLine(item: Item): string {
  return sentToWords(item.how, item.followsTitle).replace('{project}', item.project ?? '')
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
