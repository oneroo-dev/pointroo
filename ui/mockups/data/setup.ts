import type { HintView, Item, SetupRow, WakeSettingsView } from '../../src/parts/types'
import { asks, pointrooWaiting, waiting, working } from './items'

/** Setup when everything is ready: every row is a green tick. */
export const setupAllGreen: SetupRow[] = [
  { id: 'applications', label: 'Pointroo is in Applications', state: 'done', doneLabel: 'Yes' },
  { id: 'microphone', label: 'Microphone', state: 'done', doneLabel: 'Allowed' },
  { id: 'screenRecording', label: 'Screen recording', state: 'done', doneLabel: 'Allowed' },
  { id: 'accessibility', label: 'Accessibility', state: 'done', doneLabel: 'Allowed' },
  { id: 'claudeCode', label: 'Claude Code', description: 'Pointroo found it on this Mac.', state: 'done', doneLabel: 'Found' },
  { id: 'tool', label: 'Pointroo tool in Claude Code', state: 'done', doneLabel: 'Added' },
  { id: 'stopHook', label: 'Stop hook', description: 'Tells Pointroo when Claude is done.', state: 'done', doneLabel: 'Added' },
  { id: 'speech', label: 'Speech model', state: 'done', doneLabel: 'Ready' },
  { id: 'wake', label: 'Claude Code is new enough to wake', description: 'Version 2.1.224 or newer.', state: 'done', doneLabel: 'Yes' },
]

/** Setup on a fresh Mac: most rows are not done and the speech model is still downloading. */
export const setupFresh: SetupRow[] = [
  { id: 'applications', label: 'Pointroo is in Applications', state: 'todo', actionLabel: 'Move to Applications' },
  { id: 'microphone', label: 'Microphone', state: 'todo', actionLabel: 'Allow' },
  { id: 'screenRecording', label: 'Screen recording', description: 'You said no before. Turn it on in System Settings.', state: 'todo', actionLabel: 'Open System Settings' },
  { id: 'accessibility', label: 'Accessibility', state: 'todo', actionLabel: 'Allow' },
  { id: 'claudeCode', label: 'Claude Code', description: 'Not found.', state: 'todo', actionLabel: 'Install Claude Code' },
  {
    id: 'tool',
    label: 'Pointroo tool in Claude Code',
    state: 'todo',
    actionLabel: 'Connect',
    note: 'Restart open Claude sessions to see it.',
  },
  { id: 'stopHook', label: 'Stop hook', description: 'Tells Pointroo when Claude is done.', state: 'todo', actionLabel: 'Add' },
  { id: 'speech', label: 'Speech model', state: 'busy', busyLabel: 'Downloading...' },
  { id: 'wake', label: 'Claude Code is new enough to wake', state: 'todo', actionLabel: 'Update Claude Code for auto-wake' },
]

/** The speech download has failed: the row gives a Retry button. */
export const setupSpeechFailed: SetupRow = { id: 'speech', label: 'Speech model', description: 'The download did not finish.', state: 'todo', actionLabel: 'Retry' }

export const wakeSettings: WakeSettingsView = {
  enabled: true,
  owners: [
    { projectId: 'tinkeroo', name: 'Tinkeroo', owner: 'auto' },
    { projectId: 'pointroo', name: 'Pointroo', owner: 'pointroo-main' },
    { projectId: 'tableroo', name: 'Tableroo', owner: 'auto' },
    { projectId: 'bellroo', name: 'Bellroo', owner: 'auto' },
  ],
  sessions: [
    { value: 'tinkeroo-main', label: 'Tinkeroo' },
    { value: 'pointroo-main', label: 'Pointroo lead' },
    { value: 'pointroo-f2', label: 'Pointroo setup screens' },
    { value: 'tableroo-main', label: 'Tableroo' },
  ],
  lastWake: 'Last: woke Tinkeroo for tinkeroo, 2 min ago',
}

/** One item for each wake note. */
export const wakeItems: Item[] = [
  { ...working, id: 'w1', wake: { kind: 'woke', name: 'Tinkeroo' } },
  { ...waiting, id: 'w2', wake: { kind: 'no-session' } },
  { ...pointrooWaiting, id: 'w3', wake: { kind: 'busy' } },
  { ...asks, id: 'w4', wake: { kind: 'too-old' } },
]

export const hints: HintView[] = [
  { message: 'Not sent: no Claude session open.', tone: 'warn' },
  { message: 'Speech download failed.', tone: 'warn', actionLabel: 'Retry' },
  { message: 'Port 6742 was busy, Pointroo moved to 6743.', tone: 'muted' },
]
