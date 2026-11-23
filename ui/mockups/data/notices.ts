/** A done notice, from done.recent: the project, the agent's note and the screens before and after. */
export interface DoneNoticeSample {
  project: string
  agent: string
  note: string
}

export const doneNotice: DoneNoticeSample = {
  project: 'Tinkeroo',
  agent: 'Claude Code',
  note: 'Moved Delete to the left of the row and made it red.',
}

/** A question notice, from questions.list: the text may run to two lines, up to three choices. */
export interface QuestionNoticeSample {
  project: string
  agent: string
  text: string
  choices: string[]
}

export const questionNotice: QuestionNoticeSample = {
  project: 'Tinkeroo',
  agent: 'Claude Code',
  text: 'Should Delete ask before it removes a row, or only when more than one row is picked?',
  choices: ['Yes, ask first', 'No', 'Only when many are picked'],
}
