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

/**
 * The project chips that fit and the ones behind "+N". The chosen project always shows: when it would be hidden it takes the
 * place of the last chip that fits.
 */
export function visibleProjects(ordered: Project[], selectedId: string, limit: number): { shown: Project[]; hidden: Project[] } {
  if (ordered.length <= limit) return { shown: ordered, hidden: [] }
  const shown = ordered.slice(0, limit)
  const chosen = ordered.find((project) => project.id === selectedId)
  if (chosen !== undefined && !shown.includes(chosen) && limit > 0) shown[limit - 1] = chosen
  return { shown, hidden: ordered.filter((project) => !shown.includes(project)) }
}

export function projectIdFor(projects: Project[], name: string | null): string | undefined {
  return projects.find((project) => project.name === name)?.id
}
