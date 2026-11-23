import { orderProjects, projectIdFor as findProjectId, tilesFor as buildTiles } from '../../src/parts/projects'
import type { Project, ProjectTile } from '../../src/parts/types'

export const projects: Project[] = [
  { id: 'tinkeroo', name: 'Tinkeroo', count: 3, listening: true, folder: '~/Workspace/tinkeroo', recentRank: 1 },
  { id: 'pointroo', name: 'Pointroo', count: 1, listening: true, folder: '~/Workspace/pointroo', recentRank: 2 },
  { id: 'tableroo', name: 'Tableroo', count: 0, listening: false, folder: '~/Workspace/tableroo', recentRank: 3 },
  { id: 'bellroo', name: 'Bellroo', count: 0, listening: false, folder: '~/Workspace/bellroo', recentRank: 4 },
  { id: 'fileroo', name: 'Fileroo', count: 0, listening: false, folder: '~/Workspace/fileroo', recentRank: 5 },
  { id: 'shellroo', name: 'Shellroo', count: 0, listening: false, folder: '~/Workspace/shellroo', recentRank: 6 },
]

/** The sidebar and the filter chips: projects that listen first, then the most recently used. */
export const orderedProjects: Project[] = orderProjects(projects)

/** Tiles in the order of the design, from the sample projects. */
export function tilesFor(suggestedId?: string, limit = 5): { tiles: ProjectTile[]; rest: ProjectTile[] } {
  return buildTiles(projects, suggestedId, limit)
}

export function projectIdFor(name: string | null): string | undefined {
  return findProjectId(projects, name)
}
