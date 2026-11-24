import type { ProjectTile } from './types'

/** What recording.get gives while the pill is recording: the phase, the points so far, the elapsed time the pill works out from startedAt. */
export const recordingSample = { elapsed: '0:12', points: 3 }

/** What picker.get gives when the picker is open: choices in number-key order (live sessions only), the guess marked, a countdown in seconds. */
export interface PickerChoice {
  name: string
  path: string
  key: number
  suggested: boolean
}

export const pickerReply: { open: true; session: string; choices: PickerChoice[]; countdown: number } = {
  open: true,
  session: '2026-11-24-0931',
  choices: [
    { name: 'Tinkeroo', path: '~/Workspace/tinkeroo', key: 1, suggested: true },
    { name: 'Pointroo', path: '~/Workspace/pointroo', key: 2, suggested: false },
    { name: 'Tableroo', path: '~/Workspace/tableroo', key: 3, suggested: false },
    { name: 'Bellroo', path: '~/Workspace/bellroo', key: 4, suggested: false },
  ],
  countdown: 8,
}

/** The picker choices as the tiles the shared ProjectTiles part draws. Every choice is a live session. */
export const pickerTiles: ProjectTile[] = pickerReply.choices.map((choice) => ({ id: choice.path, name: choice.name, suggested: choice.suggested, live: true }))

/** The one session that listens when the picker is skipped and the recording goes straight there. */
export const onlySession = { name: 'Pointroo', path: '~/Workspace/pointroo' }
