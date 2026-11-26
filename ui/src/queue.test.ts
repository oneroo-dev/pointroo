// D4: the plain words of a row, the order of the queue and the project chips that fit.
import { describe, expect, it } from 'vitest'

import { projectIdFor, projectNameFor, visibleProjects } from './parts/projects'
import type { Item, ItemState, Project } from './parts/types'
import { isFinished, orderQueue, plainWords, whereLine } from './parts/words'

function item(id: string, state: ItemState, project: string | null = 'Tinkeroo'): Item {
  return { id, project, state, title: id, said: '', points: 1, age: '4 min ago', how: 'said', crops: [] }
}

function project(id: string, listening = false): Project {
  return { id, name: id, count: 0, listening, folder: `/work/${id}`, recentRank: 1 }
}

describe('the words of a row', () => {
  it('it_drops_the_point_marks_and_extra_spaces', () => {
    expect(plainWords('Move [1] this  away,\n and [2] that.')).toBe('Move this away, and that.')
  })

  it('it_says_where_it_went_and_when', () => {
    expect(whereLine(item('a', 'working'))).toBe('Tinkeroo · 4 min ago')
    expect(whereLine(item('b', 'not-sent', null))).toBe('Not sent · 4 min ago')
  })

  it('it_shows_the_project_name_when_the_item_holds_the_folder_path', () => {
    const projects: Project[] = [{ ...project('/work/pointroo-app'), name: 'Pointroo' }]
    expect(whereLine(item('a', 'working', '/work/pointroo-app'), projects)).toBe('Pointroo · 4 min ago')
    expect(whereLine(item('b', 'working', 'Pointroo'), projects)).toBe('Pointroo · 4 min ago')
  })

  it('it_falls_back_to_the_last_folder_name_for_a_path_that_is_not_listed', () => {
    expect(whereLine(item('a', 'working', '/Users/me/Workspace/shellroo/'), [])).toBe('shellroo · 4 min ago')
    expect(projectNameFor([], '/Users/me/Workspace/shellroo')).toBe('shellroo')
    expect(projectNameFor([], null)).toBeNull()
  })

  it('it_finds_the_listed_project_by_path_or_by_name', () => {
    const projects: Project[] = [{ ...project('/work/pointroo-app'), name: 'Pointroo' }, project('Tinkeroo')]
    expect(projectIdFor(projects, '/work/pointroo-app')).toBe('/work/pointroo-app')
    expect(projectIdFor(projects, 'Pointroo')).toBe('/work/pointroo-app')
    expect(projectIdFor(projects, '/work/missing')).toBeUndefined()
    expect(projectIdFor(projects, null)).toBeUndefined()
  })

  it('it_knows_a_finished_item', () => {
    expect(isFinished(item('a', 'done'))).toBe(true)
    expect(isFinished(item('b', 'done-by-you'))).toBe(true)
    expect(isFinished(item('c', 'waiting'))).toBe(false)
  })
})

describe('the order of the queue', () => {
  it('it_puts_what_needs_you_first_and_keeps_the_rest_in_order', () => {
    const items = [item('w1', 'waiting'), item('k1', 'working'), item('w2', 'waiting'), item('q1', 'asks'), item('n1', 'not-sent', null)]
    expect(orderQueue(items).map((entry) => entry.id)).toEqual(['q1', 'n1', 'k1', 'w1', 'w2'])
  })

  it('it_puts_a_fresh_item_on_top', () => {
    const items = [item('q1', 'asks'), item('w1', 'waiting'), item('w2', 'waiting')]
    expect(orderQueue(items, ['w2']).map((entry) => entry.id)).toEqual(['w2', 'q1', 'w1'])
  })

  it('it_does_not_change_the_list_it_was_given', () => {
    const items = [item('w1', 'waiting'), item('q1', 'asks')]
    orderQueue(items)
    expect(items.map((entry) => entry.id)).toEqual(['w1', 'q1'])
  })
})

describe('the project chips that fit', () => {
  const ordered = ['a', 'b', 'c', 'd', 'e'].map((id) => project(id))

  it('it_shows_all_when_they_fit', () => {
    const result = visibleProjects(ordered, 'all', 5)
    expect(result.shown).toHaveLength(5)
    expect(result.hidden).toHaveLength(0)
  })

  it('it_folds_the_last_ones_behind_a_count', () => {
    const result = visibleProjects(ordered, 'all', 2)
    expect(result.shown.map((entry) => entry.id)).toEqual(['a', 'b'])
    expect(result.hidden.map((entry) => entry.id)).toEqual(['c', 'd', 'e'])
  })

  it('it_keeps_the_chosen_project_in_view', () => {
    const result = visibleProjects(ordered, 'd', 2)
    expect(result.shown.map((entry) => entry.id)).toEqual(['a', 'd'])
    expect(result.hidden.map((entry) => entry.id)).toEqual(['b', 'c', 'e'])
  })
})
