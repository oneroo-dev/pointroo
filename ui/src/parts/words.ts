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
  if (doneTab && item.note) return item.note
  if (item.state === 'not-sent') return `Not sent yet · ${pointsWord(item.points)} · ${item.age}`
  const agent = item.state === 'working' && item.agent ? ` · ${item.agent}` : ''
  return `${item.project}${agent} · ${pointsWord(item.points)} · ${item.age}`
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
