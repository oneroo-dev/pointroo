<script setup lang="ts">
// A review frame round the real main window part (src/parts/MainWindow.vue). A scenario picks the sample data and flags.
import { computed, ref } from 'vue'
import MainWindow from '../../src/parts/MainWindow.vue'
import SettingsScreen from '../../src/parts/SettingsScreen.vue'
import type { Item, MainBanner, MainTab, RecordingView } from '../../src/parts/types'
import type { SettingKey, SettingValue, SettingsValues } from '../../src/types'
import SetupView from './SetupView.vue'
import TrafficLights from './TrafficLights.vue'
import { projects } from '../data/projects'
import { asks, doneCount, doneItems, doneRecent, justSent, nowCount, nowItems, notSent, processing, recorded, sampleImage, working } from '../data/items'

export type Scenario =
  | 'queue'
  | 'asks'
  | 'done'
  | 'done-list'
  | 'recording'
  | 'not-sent'
  | 'just-sent'
  | 'processing'
  | 'none-selected'
  | 'empty'
  | 'now-empty'
  | 'loading'
  | 'permission'
  | 'port-busy'
  | 'mcp-error'
  | 'no-session'
  | 'update'
  | 'updating'
  | 'setup'
  | 'setup-done'
  | 'settings'
  | 'settings-auto-start'
  | 'settings-auto-start-run'
  | 'settings-auto-start-log'

const props = withDefaults(defineProps<{ width?: number; height?: number; scenario?: Scenario; detailOpen?: boolean }>(), {
  width: 960,
  height: 620,
  scenario: 'queue',
  detailOpen: true,
})

const tab = ref<MainTab>(props.scenario === 'done' || props.scenario === 'done-list' || props.scenario === 'now-empty' ? 'done' : 'now')

const recordingView: RecordingView = {
  state: 'ready',
  said: ['Okay, this is the settings page.', 'The delete button is right next to save, move it away and make it red.', 'That is all for this one.'],
  frames: [sampleImage('Frame 1', '#6b7280'), sampleImage('Frame 2', '#3b82f6'), sampleImage('Frame 3', '#10b981')],
  points: ['Tinkeroo - Settings - Button "Delete"', 'Tinkeroo - Settings - Button "Save"', 'https://example.com/overview'],
  summary: '1 min, started 10:42',
}
const filter = ref('all')

const autoStartScenario = props.scenario === 'settings-auto-start' || props.scenario === 'settings-auto-start-run' || props.scenario === 'settings-auto-start-log'
const settingsValues = ref<SettingsValues>({
  sounds: true,
  doubleControl: true,
  escCancels: true,
  redactSecrets: true,
  connectAgents: true,
  showNoSpeech: false,
  holdToTalk: false,
  listenAfterDone: false,
  autoSendSingle: true,
  kitWindow: true,
  locale: 'en-US',
  autoStartAgent: autoStartScenario ? 'claude' : 'off',
  autoStartModel: 'sonnet',
  autoStartEffort: 'medium',
  autoStartBudget: 2,
  autoStartPermission: 'acceptEdits',
})
const settingsOpen = props.scenario === 'settings' || autoStartScenario
const autoRuns = autoStartScenario ? [{ project: '/Users/sample/Workspace/tinkeroo', startedAt: '2026-11-24T10:42:00Z' }] : []
// Only the "run" frame shows the Last run row. The time is fixed so the "ago" words stay the same.
const lastAutoRun =
  props.scenario === 'settings-auto-start-run'
    ? { project: '/Users/sample/Workspace/pointroo', endedAt: '2026-11-24T10:34:00Z', exitCode: 0, cost: 0.42 }
    : undefined
// Only the "log" frame has the log panel open, with the same three sample lines the fake bridge answers.
const logLines =
  props.scenario === 'settings-auto-start-log'
    ? [
        '2026-11-24T09:00:00Z started a run in /Users/sample/Workspace/tinkeroo',
        '2026-11-24T09:04:12Z run in /Users/sample/Workspace/tinkeroo ended (exit 0, $0.42)',
        '2026-11-24T09:30:00Z started a run in /Users/sample/Workspace/shoproo',
      ]
    : undefined
const settingsClock =Date.parse('2026-11-24T10:44:00Z')

function onSettingChange(key: SettingKey, value: SettingValue): void {
  settingsValues.value = { ...settingsValues.value, [key]: value }
}

const isSetup = computed(() => props.scenario === 'setup' || props.scenario === 'setup-done')

const rows = computed<Item[]>(() => {
  switch (props.scenario) {
    case 'done':
      return doneItems
    case 'done-list':
      return doneRecent
    case 'recording':
      return [recorded, ...nowItems.slice(1)]
    case 'processing':
      return [processing, ...nowItems]
    case 'not-sent':
      return [notSent, ...nowItems]
    case 'just-sent':
      return [justSent, ...nowItems]
    case 'empty':
    case 'now-empty':
    case 'loading':
      return []
    default:
      return nowItems
  }
})

const selectedItem = computed<Item | undefined>(() => {
  switch (props.scenario) {
    case 'asks':
      return asks
    case 'done':
      return doneItems[0]
    case 'done-list':
      return doneRecent[0]
    case 'recording':
      return recorded
    case 'not-sent':
      return notSent
    case 'just-sent':
      return justSent
    case 'none-selected':
    case 'processing':
      return undefined
    case 'queue':
    case 'permission':
    case 'port-busy':
    case 'mcp-error':
    case 'no-session':
    case 'update':
    case 'updating':
      return working
    default:
      return undefined
  }
})

const banner = computed<MainBanner | undefined>(() => {
  switch (props.scenario) {
    case 'permission':
      return { kind: 'permission' }
    case 'port-busy':
      return { kind: 'port-busy' }
    case 'mcp-error':
      return { kind: 'mcp-error' }
    case 'no-session':
      return { kind: 'no-session' }
    default:
      return undefined
  }
})

const problem = computed(() => ['permission', 'port-busy', 'mcp-error'].includes(props.scenario))
const update = computed(() => (props.scenario === 'update' ? 'ready' : props.scenario === 'updating' ? 'updating' : undefined))
const setupStep = computed(() => (props.scenario === 'setup-done' ? 'done' : 'accessibility'))
const sessionsText = computed(() => (props.scenario === 'no-session' ? 'None listening' : '2 listening'))
</script>

<template>
  <div class="frame" :style="{ width: `${width}px`, height: `${height}px` }">
    <TrafficLights class="frame-lights" />
    <MainWindow
      v-model:tab="tab"
      v-model:filter="filter"
      :width="width"
      :projects="projects"
      :items="rows"
      :selected-item="selectedItem"
      :now-count="nowCount"
      :done-count="doneCount"
      :detail-open="detailOpen"
      :loading="scenario === 'loading'"
      :empty-kind="scenario === 'now-empty' ? 'all-done' : 'nothing'"
      :banner="banner"
      :record-state="scenario === 'processing' ? 'processing' : 'idle'"
      :record-disabled="scenario === 'permission'"
      :update="update"
      :setup="isSetup"
      :settings-open="settingsOpen"
      :sessions-text="sessionsText"
      :sessions-warn="scenario === 'no-session'"
      agents-text="Claude Code, Codex"
      speech-text="English"
      :needs-you="problem"
      v-bind="scenario === 'recording' ? { recording: recordingView, recordingOpen: true } : {}"
      :toast="scenario === 'just-sent' ? { message: 'Sent to Tinkeroo', tone: 'ok', undo: true } : undefined"
    >
      <template #setup><SetupView :step="setupStep" /></template>
      <template #settings>
        <SettingsScreen
          :values="settingsValues"
          :permissions="{ microphone: true, screenRecording: false, accessibility: true }"
          :auto-runs="autoRuns"
          :last-auto-run="lastAutoRun"
          :log-lines="logLines"
          :now="settingsClock"
          @change="onSettingChange"
        />
      </template>
    </MainWindow>
  </div>
</template>

<style scoped>
.frame {
  position: relative;
  flex: none;
  overflow: hidden;
  border: 1px solid var(--roo-border);
  border-radius: var(--roo-p-radius-card);
  background: var(--roo-surface);
}

.frame-lights {
  position: absolute;
  z-index: 5;
  inset-block-start: 16px;
  inset-inline-start: var(--roo-space-group);
}
</style>
