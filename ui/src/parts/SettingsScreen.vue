<script setup lang="ts">
// Settings as a screen inside the main window (the old Settings dialog is gone). Every switch saves at once: one click
// raises `change` and the store saves it and shows an Undo toast. The values come from the app; a key that is not there
// yet shows the app's own default. The mockups pass sample values.
import { computed } from 'vue'
import { RooButton, RooIconButton, RooSelect, RooSwitch } from '@roo/kit/controls'
import { RooSettingRow, RooSettingsGroup, RooStateMark } from '@roo/kit'
import type { PermissionName, SettingKey, SettingValue, SettingsValues } from '../types'

type FlagKey = Exclude<SettingKey, 'locale'>

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
    loading?: boolean
  }>(),
  { permissions: undefined, loading: false },
)

const emit = defineEmits<{
  change: [key: SettingKey, value: SettingValue, message: string]
  allow: [which: PermissionName]
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
