import type { Project, ProjectTile } from './types'

export const projects: Project[] = [
  { id: 'tinkeroo', name: 'Tinkeroo', count: 3, listening: true, folder: '~/Workspace/tinkeroo', recentRank: 1 },
  { id: 'pointroo', name: 'Pointroo', count: 1, listening: true, folder: '~/Workspace/pointroo', recentRank: 2 },
  { id: 'tableroo', name: 'Tableroo', count: 0, listening: false, folder: '~/Workspace/tableroo', recentRank: 3 },
  { id: 'bellroo', name: 'Bellroo', count: 0, listening: false, folder: '~/Workspace/bellroo', recentRank: 4 },
  { id: 'fileroo', name: 'Fileroo', count: 0, listening: false, folder: '~/Workspace/fileroo', recentRank: 5 },
  { id: 'shellroo', name: 'Shellroo', count: 0, listening: false, folder: '~/Workspace/shellroo', recentRank: 6 },
]

/** The sidebar and the filter chips: projects that listen first, then the most recently used. */
export const orderedProjects: Project[] = [...projects].sort((first, second) => {
  if (first.listening !== second.listening) return first.listening ? -1 : 1
  return first.recentRank - second.recentRank
})

function toTile(project: Project, suggestedId: string | undefined): ProjectTile {
  return { id: project.id, name: project.name, suggested: project.id === suggestedId, live: project.listening }
}

/** Tiles in the order of the design: the app's guess, then projects that listen, then recent ones. Five show, the rest go behind More. */
export function tilesFor(suggestedId?: string, limit = 5): { tiles: ProjectTile[]; rest: ProjectTile[] } {
  const guess = projects.filter((project) => project.id === suggestedId)
  const others = orderedProjects.filter((project) => project.id !== suggestedId)
  const all = [...guess, ...others].map((project) => toTile(project, suggestedId))
  return { tiles: all.slice(0, limit), rest: all.slice(limit) }
}

export function projectIdFor(name: string | null): string | undefined {
  return projects.find((project) => project.name === name)?.id
}
