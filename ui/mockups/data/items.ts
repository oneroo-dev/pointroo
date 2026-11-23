import type { Item } from './types'

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
  crops: [{ number: 1, caption: 'Text "Last synced" · Unknown window' }],
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
  crops: [{ number: 1, caption: 'Group "Sidebar" · Overview · Tinkeroo' }],
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
export const nowCount = 4
export const doneCount = 18
