<script setup lang="ts">
// The Setup checklist: every thing Pointroo needs, one row each. A row that is fine shows a green tick; a row that is not shows
// one button. It draws the rows it is given and raises `action` with the row id; it holds no data of its own.
import { RooButton } from '@roo/kit/controls'
import { RooSettingRow, RooSettingsGroup, RooStateMark } from '@roo/kit'
import type { SetupRow } from './types'

defineProps<{ rows: SetupRow[] }>()

const emit = defineEmits<{ action: [rowId: string] }>()
</script>

<template>
  <RooSettingsGroup title="Setup">
    <RooSettingRow v-for="row in rows" :key="row.id" :label="row.label" :description="row.description">
      <RooStateMark v-if="row.state === 'done'" state="ok" :label="row.doneLabel ?? 'Ready'" />
      <RooStateMark v-else-if="row.state === 'busy'" state="running" :label="row.busyLabel ?? 'Working...'" />
      <RooButton v-else variant="secondary" size="sm" @click="emit('action', row.id)">{{ row.actionLabel ?? 'Fix' }}</RooButton>
      <template v-if="row.note !== undefined" #description>
        <span>{{ row.description }}</span>
        <span class="note">{{ row.note }}</span>
      </template>
    </RooSettingRow>
  </RooSettingsGroup>
</template>

<style scoped>
.note {
  display: block;
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
}
</style>
