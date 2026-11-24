import type { Item } from './types'

/** A plain picture for the samples, drawn as an SVG so no file is needed. */
export function sampleImage(label: string, fill: string): string {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="320" height="200"><rect width="320" height="200" fill="${fill}"/><text x="16" y="108" font-size="20" font-family="sans-serif" fill="#ffffff">${label}</text></svg>`
  return `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`
}

export const working: Item = {
  id: 'a1',
  project: 'Tinkeroo',
  state: 'working',
  title: 'Move delete away from save',
  said: 'The delete button is right next to save, move it away and make it red.',
  points: 2,
  age: '4 min ago',
  agent: 'Claude Code',
  how: 'said',
  crops: [
    { number: 1, caption: 'Button "Delete" · Settings · Tinkeroo' },
    { number: 2, caption: 'Button "Save" · Settings · Tinkeroo' },
  ],
}

export const asks: Item = {
  id: 'a2',
  project: 'Tinkeroo',
  state: 'asks',
  title: 'Should Delete ask first?',
  said: 'Make delete ask before it removes a row.',
  points: 1,
  age: '6 min ago',
  agent: 'Claude Code',
  how: 'screen',
  crops: [{ number: 1, caption: 'Button "Delete" · Rows · Tinkeroo' }],
  question: { text: 'Should Delete ask before it deletes?', choices: ['Yes, ask first', 'No', 'Only when many are picked'] },
}

export const waiting: Item = {
  id: 'a3',
  project: 'Tinkeroo',
  state: 'waiting',
  title: 'Card corners look sharp',
  said: 'The corners on these cards look sharp, round them like the rest.',
  points: 3,
  age: '9 min ago',
  how: 'said',
  crops: [
    { number: 1, caption: 'Group "Card" · Overview · Tinkeroo' },
    { number: 2, caption: 'Group "Card" · Overview · Tinkeroo' },
    { number: 3, caption: 'Group "Card" · Overview · Tinkeroo' },
  ],
}

export const pointrooWaiting: Item = {
  id: 'a4',
  project: 'Pointroo',
  state: 'waiting',
  title: 'Make the pill a bit smaller',
  said: 'Make the pill a bit smaller, it covers the menu bar.',
  points: 1,
  age: '12 min ago',
  how: 'screen',
  crops: [{ number: 1, caption: 'Group "Pill" · Pointroo' }],
}

export const notSent: Item = {
  id: 'n1',
  project: null,
  state: 'not-sent',
  title: 'This label is cut off at the end',
  said: 'This label is cut off at the end, show all of it.',
  points: 1,
  age: 'now',
  how: 'none',
  suggested: 'tinkeroo',
  crops: [{ number: 1, caption: 'Text "Last synced" · Unknown window' }],
}

export const justSent: Item = {
  id: 'n1',
  project: 'Tinkeroo',
  state: 'waiting',
  title: notSent.title,
  said: notSent.said,
  points: notSent.points,
  age: 'now',
  how: 'picked',
  crops: notSent.crops,
}

export const processing: Item = {
  id: 'p1',
  project: null,
  state: 'processing',
  title: 'Writing it up…',
  said: '',
  points: 2,
  age: 'now',
  how: 'none',
  crops: [],
}

export const done: Item = {
  id: 'd1',
  project: 'Tinkeroo',
  state: 'done',
  title: 'Make the sidebar a bit narrower',
  said: 'The sidebar is too wide, make it a bit narrower.',
  points: 1,
  age: '2 hours ago',
  agent: 'Claude Code',
  note: 'Set the sidebar to 200 wide and kept the labels on one line.',
  how: 'said',
  crops: [{ number: 1, caption: 'Group "Sidebar" · Overview · Tinkeroo', url: sampleImage('Before', '#6b7280') }],
  afterUrl: sampleImage('Now', '#3b82f6'),
}

export const doneToday: Item = {
  id: 'd4',
  project: 'Pointroo',
  state: 'done',
  title: 'The pill hides behind the menu bar',
  said: 'The pill hides behind the menu bar, move it down a little.',
  points: 1,
  age: '5 hours ago',
  agent: 'Claude Code',
  note: 'Moved the pill 8 points down so it clears the menu bar on every screen.',
  how: 'screen',
  crops: [{ number: 1, caption: 'Group "Pill" · Pointroo' }],
}

/** A recording with the Recording section: the detail shows it open in the RecordingOpen frame. */
export const recorded: Item = {
  id: 'r1',
  project: 'Tinkeroo',
  state: 'working',
  title: 'Move delete away from save',
  said: 'The delete button is right next to save, move it away and make it red.',
  points: 2,
  age: '4 min ago',
  agent: 'Claude Code',
  how: 'said',
  session: 'sample',
  crops: [
    { number: 1, caption: 'Button "Delete" · Settings · Tinkeroo' },
    { number: 2, caption: 'Button "Save" · Settings · Tinkeroo' },
  ],
}

export const doneByYou: Item = {
  id: 'd2',
  project: 'Tableroo',
  state: 'done-by-you',
  title: 'Practice',
  said: 'Make this blue.',
  points: 1,
  age: 'yesterday',
  how: 'only',
  crops: [],
}

export const doneOlder: Item = {
  id: 'd3',
  project: 'Pointroo',
  state: 'done',
  title: 'The date is wrong, it should say today',
  said: 'The date is wrong, it should say today.',
  points: 2,
  age: '3 days ago',
  agent: 'Claude Code',
  note: 'Used a relative date in the row subtitle.',
  how: 'picked',
  crops: [],
}

export const nowItems: Item[] = [working, asks, waiting, pointrooWaiting]
export const doneItems: Item[] = [done, doneByYou, doneOlder]
export const doneRecent: Item[] = [done, doneToday, doneByYou, doneOlder]
export const nowCount = 4
export const doneCount = 18
