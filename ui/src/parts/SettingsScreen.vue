<script setup lang="ts">
// Settings as a screen inside the main window (the D4 frame D4Settings). Three short groups hold what people change: Recording,
// Agents and Permissions. What is set once and left alone sits behind "More settings". Every switch saves at once: one click raises
// `change` and the store saves it and shows an Undo toast. The values come from the app; a key that is not there yet shows the
// app's own default. The mockups pass sample values.
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { RooButton, RooIconButton, RooSelect, RooSwitch } from '@roo/kit/controls'
import { RooCollapse, RooIcon, RooSettingRow, RooSettingsGroup, RooStateMark } from '@roo/kit'
import type { AutoStartChoiceKey, BridgeAutoRun, BridgeLastAutoRun, PermissionName, SettingKey, SettingValue, SettingsValues } from '../types'
import SetupChecklist from './SetupChecklist.vue'
import WakeSettings from './WakeSettings.vue'
import type { SetupRow, WakeSettingsView } from './types'
import {
  autoStartChoices,
  autoStartOn,
  budgetLabel,
  budgetOptions,
  budgetValue,
  choiceValue,
  lastRunNote,
  lastRunText,
  projectShortName,
  relativeTime,
  runSummary,
} from './autoStart'

type FlagKey = Exclude<SettingKey, 'locale' | 'autoStartBudget' | AutoStartChoiceKey>

interface FlagRow {
  key: FlagKey
  label: string
  description?: string
  /** What the app uses when it has no saved value (WebBridge.allowedSettings). */
  fallback: boolean
}

const props = withDefaults(
  defineProps<{
    values: SettingsValues
    /** Which permissions are on. Left out while the app has not answered yet. */
    permissions?: Record<PermissionName, boolean> | undefined
    /** The headless runs Auto-start has going now (status.get). Left out while the app has not answered yet. */
    autoRuns?: BridgeAutoRun[] | undefined
    /** The last auto-start run that ended (status.get). Left out when there is none. */
    lastAutoRun?: BridgeLastAutoRun | undefined
    /** The project folders whose Stop button waits for the app's answer. */
    stopping?: string[]
    /** The time to count "ago" from, in milliseconds. Left out: the real time, updated every 30 seconds. The mockups fix it. */
    now?: number | undefined
    /** The newest lines of the auto-start log. Left out while the log panel is closed. */
    logLines?: string[] | undefined
    /** The log is being read now. */
    logLoading?: boolean
    loading?: boolean
    /** "More settings" starts open (the mockups). */
    moreOpen?: boolean
    /** The Setup checklist at the top. Left out (or empty) while the app has no rows: the group is not drawn. */
    setupRows?: SetupRow[] | undefined
    /** The Wake group after the agents group. Left out while the app does not answer: the group is not drawn. */
    wake?: WakeSettingsView | undefined
  }>(),
  { setupRows: undefined, wake: undefined, permissions: undefined, autoRuns: undefined, lastAutoRun: undefined, stopping: () => [], now: undefined, logLines: undefined, logLoading: false, loading: false, moreOpen: false },
)

const logOpen = computed(() => props.logLines !== undefined || props.logLoading)
const logBox = ref<HTMLElement | null>(null)
const more = ref(props.moreOpen)
const changeOpen = ref(false)

// The newest line is at the bottom, so the box starts scrolled down.
function scrollLogToBottom(): void {
  void nextTick(() => {
    const box = logBox.value
    if (box !== null) box.scrollTop = box.scrollHeight
  })
}

watch(() => props.logLines, scrollLogToBottom)

const realNow = ref(Date.now())
const clockNow = computed(() => props.now ?? realNow.value)
let clockTimer: number | undefined

onMounted(() => {
  clockTimer = window.setInterval(() => {
    realNow.value = Date.now()
  }, 30000)
  scrollLogToBottom()
})

onBeforeUnmount(() => {
  window.clearInterval(clockTimer)
})

const emit = defineEmits<{
  change: [key: SettingKey, value: SettingValue, message: string]
  allow: [which: PermissionName]
  stopRun: [project: string]
  loadLog: []
  hideLog: []
  useAnotherPort: []
  checkUpdates: []
  setupAction: [rowId: string]
  wakeToggle: [enabled: boolean]
  wakeOwner: [projectId: string, owner: string]
  back: []
}>()

const recordingRows: FlagRow[] = [
  { key: 'doubleControl', label: 'Control twice starts and stops', fallback: true },
  { key: 'holdToTalk', label: 'Hold to talk', fallback: false },
  { key: 'sounds', label: 'Sounds', fallback: true },
]

const sendRow: FlagRow = { key: 'autoSendSingle', label: 'Send without asking', description: 'When only one session listens.', fallback: true }

/** Set once and left alone: every setting that is not in the three short groups. */
const moreRows: FlagRow[] = [
  { key: 'escCancels', label: 'Esc cancels a recording', fallback: true },
  { key: 'showNoSpeech', label: 'Keep recordings with no speech', fallback: false },
  { key: 'connectAgents', label: 'Add Pointroo to new agents', fallback: false },
  { key: 'listenAfterDone', label: 'Agents keep listening after done', fallback: false },
  { key: 'redactSecrets', label: 'Blur secrets in pictures', description: 'Hides keys and tokens before saving.', fallback: true },
  { key: 'kitWindow', label: 'New window design', description: 'From the next launch.', fallback: true },
  { key: 'kitFloating', label: 'New floating panels', fallback: true },
]

const languages = [
  { value: 'system', label: 'Same as the Mac', id: '' },
  { value: 'en-US', label: 'English', id: 'en-US' },
  { value: 'de-DE', label: 'German', id: 'de-DE' },
  { value: 'fr-FR', label: 'French', id: 'fr-FR' },
  { value: 'es-ES', label: 'Spanish', id: 'es-ES' },
  { value: 'it-IT', label: 'Italian', id: 'it-IT' },
  { value: 'pt-BR', label: 'Portuguese', id: 'pt-BR' },
  { value: 'nl-NL', label: 'Dutch', id: 'nl-NL' },
  { value: 'ja-JP', label: 'Japanese', id: 'ja-JP' },
  { value: 'zh-CN', label: 'Chinese', id: 'zh-CN' },
]
const languageOptions = languages.map((language) => ({ value: language.value, label: language.label }))

const permissionRows: { which: PermissionName; label: string; description?: string }[] = [
  { which: 'microphone', label: 'Microphone' },
  { which: 'screenRecording', label: 'Screen recording', description: 'Needed for the pictures.' },
  { which: 'accessibility', label: 'Accessibility' },
]

/** The permissions that are off, each with its own Allow button. */
const missingPermissions = computed(() => {
  const answer = props.permissions
  return answer === undefined ? [] : permissionRows.filter((row) => !answer[row.which])
})

/** The permissions that are fine share one row: "Microphone and Accessibility". */
const allowedNames = computed(() => {
  const answer = props.permissions
  if (answer === undefined) return ''
  const names = permissionRows.filter((row) => answer[row.which]).map((row) => row.label)
  if (names.length < 2) return names.join('')
  return `${names.slice(0, -1).join(', ')} and ${names[names.length - 1] ?? ''}`
})

const languageValue = computed(() => {
  const saved = props.values.locale
  const id = typeof saved === 'string' ? saved : ''
  return languages.find((language) => language.id === id)?.value ?? 'system'
})

function flagValue(row: FlagRow): boolean {
  const saved = props.values[row.key]
  return typeof saved === 'boolean' ? saved : row.fallback
}

function onFlag(row: FlagRow, value: boolean): void {
  emit('change', row.key, value, `${row.label} ${value ? 'on' : 'off'}`)
}

const changeKeys: AutoStartChoiceKey[] = ['autoStartModel', 'autoStartEffort']
const autoStartIsOn = computed(() => autoStartOn(props.values))
const summary = computed(() => runSummary(props.values))
const budgetNow = computed(() => budgetValue(props.values))
const budgetChoices = computed(() => budgetOptions(budgetNow.value))

const historyText = computed(() => {
  const last = props.lastAutoRun
  if (last === undefined) return 'No run yet.'
  const note = lastRunNote(last)
  return `Last run: ${lastRunText(last, clockNow.value)}${note === undefined ? '' : `, ${note}`}.`
})

function startedText(run: BridgeAutoRun): string {
  const ago = relativeTime(run.startedAt, clockNow.value)
  return ago === '' ? '' : `Started ${ago}.`
}

function choiceOptions(key: AutoStartChoiceKey): { value: string; label: string }[] {
  return autoStartChoices[key].options
}

function onChoice(key: AutoStartChoiceKey, value: string | undefined): void {
  const entry = autoStartChoices[key]
  const option = entry.options.find((candidate) => candidate.value === value)
  if (option === undefined) return
  emit('change', key, option.value, `${entry.label}: ${option.label}`)
}

function onAutoStart(value: string | undefined): void {
  const entry = autoStartChoices.autoStartAgent
  const option = entry.options.find((candidate) => candidate.value === value)
  if (option === undefined) return
  emit('change', 'autoStartAgent', option.value, `Auto-start: ${option.label}`)
}

function onBudget(value: string | undefined): void {
  const dollars = Number(value)
  if (value === undefined || !Number.isFinite(dollars)) return
  emit('change', 'autoStartBudget', dollars, `Budget: ${budgetLabel(dollars)}`)
}

function onLanguage(value: string | undefined): void {
  const language = languages.find((entry) => entry.value === value)
  if (language === undefined) return
  emit('change', 'locale', language.id, `Language: ${language.label}`)
}
</script>

<template>
  <div class="screen">
    <div class="inner">
      <header class="head">
        <RooIconButton icon="arrow-left" variant="ghost" label="Back" tooltip="Back" shortcut="Esc" @click="emit('back')" />
        <h2 class="title">Settings</h2>
      </header>

      <SetupChecklist v-if="setupRows !== undefined && setupRows.length > 0" :rows="setupRows" @action="(rowId) => emit('setupAction', rowId)" />

      <RooSettingsGroup title="Recording">
        <RooSettingRow v-for="row in recordingRows" :key="row.key" :label="row.label">
          <RooSwitch :model-value="flagValue(row)" :disabled="loading" :aria-label="row.label" @update:model-value="(value) => onFlag(row, value)" />
        </RooSettingRow>
        <RooSettingRow label="Language">
          <RooSelect :model-value="languageValue" label="Language" hide-label size="md" :disabled="loading" :options="languageOptions" @update:model-value="onLanguage" />
        </RooSettingRow>
      </RooSettingsGroup>

      <RooSettingsGroup title="Agents">
        <RooSettingRow :label="sendRow.label" :description="sendRow.description">
          <RooSwitch :model-value="flagValue(sendRow)" :disabled="loading" :aria-label="sendRow.label" @update:model-value="(value) => onFlag(sendRow, value)" />
        </RooSettingRow>
        <RooSettingRow label="Auto-start" description="Starts an agent when no session listens.">
          <RooSelect
            :model-value="choiceValue(values, 'autoStartAgent')"
            label="Auto-start"
            hide-label
            size="md"
            :disabled="loading"
            :options="choiceOptions('autoStartAgent')"
            @update:model-value="onAutoStart"
          />
        </RooSettingRow>
        <template v-if="autoStartIsOn">
          <RooSettingRow :label="summary.title" :description="summary.detail">
            <RooButton variant="secondary" size="sm" aria-label="Change how a run works" :aria-expanded="changeOpen" @click="changeOpen = !changeOpen">
              {{ changeOpen ? 'Done' : 'Change' }}
            </RooButton>
          </RooSettingRow>
          <template v-if="changeOpen">
            <RooSettingRow v-for="key in changeKeys" :key="key" :label="autoStartChoices[key].label">
              <RooSelect
                :model-value="choiceValue(values, key)"
                :label="autoStartChoices[key].label"
                hide-label
                size="md"
                :disabled="loading"
                :options="choiceOptions(key)"
                @update:model-value="(value) => onChoice(key, value)"
              />
            </RooSettingRow>
            <RooSettingRow label="Budget" description="The most one run may spend.">
              <RooSelect :model-value="String(budgetNow)" label="Budget" hide-label size="md" :disabled="loading" :options="budgetChoices" @update:model-value="onBudget" />
            </RooSettingRow>
            <RooSettingRow label="Permission" description="What the run may do without asking. Anything else is refused.">
              <RooSelect
                :model-value="choiceValue(values, 'autoStartPermission')"
                label="Permission"
                hide-label
                size="md"
                :disabled="loading"
                :options="choiceOptions('autoStartPermission')"
                @update:model-value="(value) => onChoice('autoStartPermission', value)"
              />
            </RooSettingRow>
          </template>
          <RooSettingRow v-for="run in autoRuns ?? []" :key="run.project" :label="`Running in ${projectShortName(run.project)}`" :description="startedText(run)">
            <RooButton
              variant="secondary"
              size="sm"
              :disabled="stopping.includes(run.project)"
              :aria-label="`Stop the run in ${projectShortName(run.project)}`"
              @click="emit('stopRun', run.project)"
            >
              Stop
            </RooButton>
          </RooSettingRow>
          <RooSettingRow label="History" :description="historyText">
            <RooButton v-if="!logOpen" variant="ghost" size="sm" aria-label="Show the log" @click="emit('loadLog')">Log</RooButton>
          </RooSettingRow>
          <RooSettingRow v-if="logOpen" label="Log" description="What Auto-start did, newest last." stack>
            <div class="log">
              <div ref="logBox" class="log-box" tabindex="0" role="log" aria-label="Auto-start log">
                <span v-if="logLines === undefined" class="log-note">Loading...</span>
                <span v-else-if="logLines.length === 0" class="log-note">No runs yet.</span>
                <div v-for="(line, index) in logLines" v-else :key="index" class="log-line">{{ line }}</div>
              </div>
              <div class="log-buttons">
                <RooButton variant="secondary" size="sm" :disabled="logLoading" aria-label="Refresh the log" @click="emit('loadLog')">Refresh</RooButton>
                <RooButton variant="secondary" size="sm" aria-label="Hide the log" @click="emit('hideLog')">Hide</RooButton>
              </div>
            </div>
          </RooSettingRow>
        </template>
      </RooSettingsGroup>

      <WakeSettings v-if="wake !== undefined" :settings="wake" @toggle="(enabled) => emit('wakeToggle', enabled)" @owner="(projectId, owner) => emit('wakeOwner', projectId, owner)" />

      <RooSettingsGroup title="Permissions">
        <RooSettingRow v-if="permissions === undefined" label="Permissions">
          <RooStateMark state="muted" label="Checking" />
        </RooSettingRow>
        <template v-else>
          <RooSettingRow v-for="row in missingPermissions" :key="row.which" :label="row.label" :description="row.description">
            <RooButton variant="primary" size="sm" :aria-label="`Allow ${row.label}`" @click="emit('allow', row.which)">Allow</RooButton>
          </RooSettingRow>
          <RooSettingRow v-if="allowedNames !== ''" :label="allowedNames">
            <RooStateMark state="ok" label="Allowed" />
          </RooSettingRow>
        </template>
      </RooSettingsGroup>

      <div class="more">
        <div class="more-toggle">
          <RooButton variant="ghost" size="sm" flush :aria-expanded="more" @click="more = !more">
            <template #icon><RooIcon :name="more ? 'chevron-down' : 'chevron'" :size="16" /></template>
            More settings
          </RooButton>
        </div>
        <RooCollapse v-model:open="more">
          <RooSettingsGroup>
            <RooSettingRow v-for="row in moreRows" :key="row.key" :label="row.label" :description="row.description">
              <RooSwitch :model-value="flagValue(row)" :disabled="loading" :aria-label="row.label" @update:model-value="(value) => onFlag(row, value)" />
            </RooSettingRow>
            <RooSettingRow label="Agents server port" description="Change it when another app has 6742.">
              <RooButton variant="secondary" size="sm" aria-label="Use another port" @click="emit('useAnotherPort')">Change</RooButton>
            </RooSettingRow>
            <RooSettingRow label="Updates">
              <RooButton variant="secondary" size="sm" aria-label="Check for updates" @click="emit('checkUpdates')">Check</RooButton>
            </RooSettingRow>
          </RooSettingsGroup>
        </RooCollapse>
      </div>
    </div>
  </div>
</template>

<style scoped>
.screen {
  box-sizing: border-box;
  height: 100%;
  min-height: 0;
  overflow-y: auto;
  padding: var(--roo-space-group);
}

.inner {
  display: flex;
  max-width: 640px;
  flex-direction: column;
  gap: var(--roo-space-section);
  margin-inline: auto;
}

.more {
  display: flex;
  flex-direction: column;
  gap: var(--roo-space-item);
}

.more-toggle {
  display: flex;
}

.log {
  display: flex;
  min-width: 0;
  flex-direction: column;
  gap: var(--roo-space-item);
}

.log-box {
  box-sizing: border-box;
  max-height: 240px;
  overflow: auto;
  padding: var(--roo-space-item);
  border: 1px solid var(--roo-border);
  border-radius: var(--roo-p-radius-medium);
  background: var(--roo-surface);
  font-family: var(--roo-font-mono);
  font-size: var(--roo-p-size-12);
}

.log-line {
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

.log-note {
  color: var(--roo-muted);
}

.log-buttons {
  display: flex;
  gap: var(--roo-space-item);
}

.head {
  display: flex;
  align-items: center;
  gap: var(--roo-space-item);
}

.title {
  margin: 0;
  font-size: var(--roo-p-size-15);
  font-weight: 600;
}
</style>
