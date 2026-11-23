import type { Item } from './types'

/** The fields items.search can hit, as the bridge names them. */
export type SearchField = 'title' | 'body' | 'said' | 'alsoSaid' | 'note' | 'project' | 'firstElement'

/** An Item plus the match the bridge adds: the best field with a hit and up to 80 characters around the first hit, on one line. */
export interface SearchResult {
  item: Item
  match: { field: SearchField; snippet: string }
}

export const searchQuery = 'delete'

function sample(id: string, project: string, state: Item['state'], title: string, said: string, age: string, note?: string): Item {
  return {
    id,
    project,
    state,
    title,
    said,
    points: 1,
    age,
    how: 'said',
    crops: [],
    ...(note === undefined ? {} : { note }),
  }
}

export const searchResults: SearchResult[] = [
  {
    item: sample('s1', 'Tinkeroo', 'working', 'Move delete away from save', 'The delete button is right next to save, move it away and make it red.', '4 min ago'),
    match: { field: 'title', snippet: 'Move delete away from save' },
  },
  {
    item: sample('s2', 'Tinkeroo', 'asks', 'Should Delete ask first?', 'Make delete ask before it removes a row.', '6 min ago'),
    match: { field: 'title', snippet: 'Should Delete ask first?' },
  },
  {
    item: sample('s3', 'Pointroo', 'waiting', 'Trash icon is too close', 'The trash icon sits next to delete in the row, space them out a bit.', '1 hour ago'),
    match: { field: 'said', snippet: 'The trash icon sits next to delete in the row, space them out a bit.' },
  },
  {
    item: sample('s4', 'Tableroo', 'done', 'Rows jump after a removal', 'Rows jump up when one goes away.', 'yesterday', 'Kept the row height so nothing jumps after delete.'),
    match: { field: 'note', snippet: 'Kept the row height so nothing jumps after delete.' },
  },
  {
    item: sample('s5', 'Tinkeroo', 'done', 'Make the sidebar a bit narrower', 'The sidebar is too wide, make it a bit narrower.', '2 days ago', 'Set the sidebar to 200 wide.'),
    match: { field: 'firstElement', snippet: 'Button "Delete" · Overview · Tinkeroo' },
  },
]
