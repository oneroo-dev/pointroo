import type { Project, ProjectTile } from './types'

/** Projects that listen first, then the most recently used. */
export function orderProjects(projects: Project[]): Project[] {
  return [...projects].sort((first, second) => {
    if (first.listening !== second.listening) return first.listening ? -1 : 1
    return first.recentRank - second.recentRank
  })
}

function toTile(project: Project, suggestedId: string | undefined): ProjectTile {
  return { id: project.id, name: project.name, suggested: project.id === suggestedId, live: project.listening }
}

/** Tiles in the order of the design: the app's guess, then projects that listen, then recent ones. Five show, the rest go behind More. */
export function tilesFor(projects: Project[], suggestedId?: string, limit = 5): { tiles: ProjectTile[]; rest: ProjectTile[] } {
  const guess = projects.filter((project) => project.id === suggestedId)
  const others = orderProjects(projects).filter((project) => project.id !== suggestedId)
  const all = [...guess, ...others].map((project) => toTile(project, suggestedId))
  return { tiles: all.slice(0, limit), rest: all.slice(limit) }
}

export function projectIdFor(projects: Project[], name: string | null): string | undefined {
  return projects.find((project) => project.name === name)?.id
}
