<script setup lang="ts">
// The Wake group in Settings: one switch, then "Who owns each project" (each project picks one open Claude session, or
// Automatic), then the last wake as one quiet line. It draws what it is given and raises an event for each change.
import { computed } from 'vue'
import { RooSelect, RooSwitch } from '@roo/kit/controls'
import { RooSettingRow, RooSettingsGroup } from '@roo/kit'
import type { WakeSettingsView } from './types'

const props = defineProps<{ settings: WakeSettingsView }>()

const emit = defineEmits<{
  toggle: [enabled: boolean]
  owner: [projectId: string, owner: string]
}>()

const options = computed(() => [{ value: 'auto', label: 'Automatic' }, ...props.settings.sessions.map((session) => ({ value: session.value, label: session.label }))])
</script>

<template>
  <RooSettingsGroup title="Wake">
    <RooSettingRow label="Wake the project's Claude session for each new recording">
      <RooSwitch :model-value="settings.enabled" aria-label="Wake the project's Claude session for each new recording" @update:model-value="(value) => emit('toggle', value)" />
    </RooSettingRow>
    <template v-if="settings.enabled">
      <RooSettingRow label="Who owns each project" description="Automatic uses the session with the project's name, then the one in its folder." />
      <RooSettingRow v-for="row in settings.owners" :key="row.projectId" :label="row.name">
        <RooSelect
          :model-value="row.owner"
          :label="`Session for ${row.name}`"
          hide-label
          size="md"
          :options="options"
          @update:model-value="(value) => value !== undefined && emit('owner', row.projectId, value)"
        />
      </RooSettingRow>
      <RooSettingRow v-if="settings.lastWake !== undefined" label="Last wake" :description="settings.lastWake" />
    </template>
  </RooSettingsGroup>
</template>
