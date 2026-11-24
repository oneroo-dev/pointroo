<script setup lang="ts">
// Settings as a screen inside the main window (the old Settings dialog is gone). Every switch saves at once: one click
// raises `change` and the store saves it and shows an Undo toast. The values come from the app; a key that is not there
// yet shows the app's own default. The mockups pass sample values.
import { computed } from 'vue'
import { RooButton, RooIconButton, RooSelect, RooSwitch } from '@roo/kit/controls'
import { RooSettingRow, RooSettingsGroup, RooStateMark } from '@roo/kit'
import type { AutoStartChoiceKey, BridgeAutoRun, PermissionName, SettingKey, SettingValue, SettingsValues } from '../types'
import { autoStartChoices, autoStartOn, budgetLabel, budgetOptions, budgetValue, choiceValue, runsText } from './autoStart'

type FlagKey = Exclude<SettingKey, 'locale' | 'autoStartBudget' | AutoStartChoiceKey>

interface FlagRow {
  key: FlagKey
  label: string
  description: string
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
    loading?: boolean
  }>(),
  { permissions: undefined, autoRuns: undefined, loading: false },
)

const emit = defineEmits<{
  change: [key: SettingKey, value: SettingValue, message: string]
  allow: [which: PermissionName]
  useAnotherPort: []
  checkUpdates: []
  back: []
}>()

const recordingRows: FlagRow[] = [
  { key: 'doubleControl', label: 'Control twice', description: 'Starts and stops from any app.', fallback: true },
  { key: 'holdToTalk', label: 'Hold to talk', description: 'Records only while you hold the key.', fallback: false },
  { key: 'escCancels', label: 'Esc cancels', description: 'Stops and moves it to the Trash.', fallback: true },
  { key: 'showNoSpeech', label: 'Show recordings with no speech', description: 'Keeps silent ones in the list.', fallback: false },
  { key: 'sounds', label: 'Sounds', description: 'A soft sound at start and when sent.', fallback: true },
]

const agentRows: FlagRow[] = [
  { key: 'connectAgents', label: 'Connect agents by themselves', description: 'Adds Pointroo to new coding agents.', fallback: false },
  { key: 'autoSendSingle', label: 'Send to the only listening session', description: 'With one session listening, recordings go there without asking.', fallback: true },
  { key: 'listenAfterDone', label: 'Keep listening after done', description: 'Agents wait for the next recording.', fallback: false },
  { key: 'redactSecrets', label: 'Blur secrets in screenshots', description: 'Hides keys and tokens before saving.', fallback: true },
]

const windowRows: FlagRow[] = [
  { key: 'kitWindow', label: 'New window design', description: 'Takes effect next launch.', fallback: true },
  { key: 'kitFloating', label: 'Kit floating panels', description: 'The pill, the project picker and the notices use the new design.', fallback: false },
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

const permissionRows: { which: PermissionName; label: string; description: string }[] = [
  { which: 'microphone', label: 'Microphone', description: 'Needed to hear you.' },
  { which: 'screenRecording', label: 'Screen recording', description: 'Needed for screenshots.' },
  { which: 'accessibility', label: 'Accessibility', description: 'Needed for button and field names.' },
]

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

const modelAndEffortKeys: AutoStartChoiceKey[] = ['autoStartModel', 'autoStartEffort']
const autoStartIsOn = computed(() => autoStartOn(props.values))
const budgetNow = computed(() => budgetValue(props.values))
const budgetChoices = computed(() => budgetOptions(budgetNow.value))

function choiceOptions(key: AutoStartChoiceKey): { value: string; label: string }[] {
  return autoStartChoices[key].options
}

function onChoice(key: AutoStartChoiceKey, value: string | undefined): void {
  const entry = autoStartChoices[key]
  const option = entry.options.find((candidate) => candidate.value === value)
  if (option === undefined) return
  emit('change', key, option.value, `${entry.label}: ${option.label}`)
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

      <RooSettingsGroup title="Recording">
        <RooSettingRow v-for="row in recordingRows" :key="row.key" :label="row.label" :description="row.description">
          <RooSwitch :model-value="flagValue(row)" :disabled="loading" :aria-label="row.label" @update:model-value="(value) => onFlag(row, value)" />
        </RooSettingRow>
      </RooSettingsGroup>

      <RooSettingsGroup title="Agents">
        <RooSettingRow v-for="row in agentRows" :key="row.key" :label="row.label" :description="row.description">
          <RooSwitch :model-value="flagValue(row)" :disabled="loading" :aria-label="row.label" @update:model-value="(value) => onFlag(row, value)" />
        </RooSettingRow>
      </RooSettingsGroup>

      <RooSettingsGroup title="Auto-start agent">
        <RooSettingRow label="Agent" description="Starts a headless run when an item goes to a project with no listening session.">
          <RooSelect
            :model-value="choiceValue(values, 'autoStartAgent')"
            label="Agent"
            hide-label
            size="md"
            :disabled="loading"
            :options="choiceOptions('autoStartAgent')"
            @update:model-value="(value) => onChoice('autoStartAgent', value)"
          />
        </RooSettingRow>
        <template v-if="autoStartIsOn">
          <RooSettingRow v-for="key in modelAndEffortKeys" :key="key" :label="autoStartChoices[key].label">
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
          <RooSettingRow label="Runs" description="Headless runs going now.">
            <RooStateMark v-if="autoRuns === undefined" state="muted" label="Checking" />
            <RooStateMark v-else :state="autoRuns.length > 0 ? 'ok' : 'muted'" :label="runsText(autoRuns)" />
          </RooSettingRow>
        </template>
      </RooSettingsGroup>

      <RooSettingsGroup title="Agents server">
        <RooSettingRow label="Use another port" description="When another app has port 6742.">
          <RooButton variant="secondary" size="sm" aria-label="Use another port" @click="emit('useAnotherPort')">Use another port</RooButton>
        </RooSettingRow>
      </RooSettingsGroup>

      <RooSettingsGroup title="Window">
        <RooSettingRow v-for="row in windowRows" :key="row.key" :label="row.label" :description="row.description">
          <RooSwitch :model-value="flagValue(row)" :disabled="loading" :aria-label="row.label" @update:model-value="(value) => onFlag(row, value)" />
        </RooSettingRow>
      </RooSettingsGroup>

      <RooSettingsGroup title="Language">
        <RooSettingRow label="Speech language" description="Turned into text on this Mac.">
          <RooSelect :model-value="languageValue" label="Speech language" hide-label size="md" :disabled="loading" :options="languageOptions" @update:model-value="onLanguage" />
        </RooSettingRow>
      </RooSettingsGroup>

      <RooSettingsGroup title="Permissions">
        <RooSettingRow v-for="row in permissionRows" :key="row.which" :label="row.label" :description="row.description">
          <RooStateMark v-if="permissions === undefined" state="muted" label="Checking" />
          <RooStateMark v-else-if="permissions[row.which]" state="ok" label="Allowed" />
          <RooButton v-else variant="secondary" size="sm" :aria-label="`Allow ${row.label}`" @click="emit('allow', row.which)">Allow</RooButton>
        </RooSettingRow>
      </RooSettingsGroup>

      <RooSettingsGroup title="About">
        <RooSettingRow label="Check for updates" description="Looks for a new version of Pointroo.">
          <RooButton variant="secondary" size="sm" aria-label="Check for updates" @click="emit('checkUpdates')">Check for updates</RooButton>
        </RooSettingRow>
      </RooSettingsGroup>
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
