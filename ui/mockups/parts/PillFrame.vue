<script setup lang="ts">
import { RooButton, RooIconButton, RooTooltip } from '@roo/kit/controls'
import { RooIcon, RooProgressLine, RooStateMark, RooSwitcher } from '@roo/kit'
import FloatingSurface from './FloatingSurface.vue'

export type PillKind = 'recording' | 'writing' | 'sent' | 'reply' | 'error' | 'kept' | 'picker'

defineProps<{ kind: PillKind }>()

const rows = [
  { id: 'tinkeroo', name: 'Tinkeroo', meta: 'listening', dot: 'var(--roo-muted)' },
  { id: 'pointroo', name: 'Pointroo', meta: 'listening', dot: 'var(--roo-muted)' },
  { id: 'tableroo', name: 'Tableroo', meta: 'listening', dot: 'var(--roo-muted)' },
]
</script>

<template>
  <FloatingSurface v-if="kind === 'picker'" class="picker" role="group" aria-label="Pick a project">
    <h2 class="picker-title">Which project is this for?</h2>
    <RooSwitcher :open="true" :rows="rows" label="Which project is this for?" search search-placeholder="Type to filter" grouping="none" shortcuts hints />
  </FloatingSurface>

  <FloatingSurface v-else class="pill" role="status">
    <template v-if="kind === 'recording' || kind === 'reply'">
      <RooStateMark state="err" label="Recording" class="pill-dot" />
      <span class="pill-time">{{ kind === 'reply' ? '0:04' : '0:12' }}</span>
      <span class="pill-note">{{ kind === 'reply' ? 'Reply to Tinkeroo' : '3 points' }}</span>
      <span class="pill-spacer" />
      <RooIconButton icon="x" variant="ghost" size="xs" label="Cancel" tooltip="Cancel and keep nothing" shortcut="Escape" />
      <RooTooltip text="Stop ⌃⌃"><RooButton variant="primary" size="sm">Stop</RooButton></RooTooltip>
    </template>
    <template v-else-if="kind === 'writing'">
      <RooIcon name="loader" :size="16" />
      <span class="pill-text">Writing it up…</span>
      <RooProgressLine busy :delay="0" />
    </template>
    <template v-else-if="kind === 'sent'">
      <RooStateMark state="ok" label="Sent to Tinkeroo · you said its name" />
    </template>
    <template v-else-if="kind === 'kept'">
      <RooStateMark state="muted" label="Kept in the queue. Send it from Pointroo later." />
    </template>
    <template v-else>
      <RooStateMark state="warn" label="Couldn't start: microphone is busy" />
      <span class="pill-spacer" />
      <RooButton variant="secondary" size="sm">OK</RooButton>
    </template>
  </FloatingSurface>
</template>

<style scoped>
.pill {
  display: flex;
  width: 280px;
  height: 44px;
  box-sizing: border-box;
  align-items: center;
  gap: var(--roo-space-item);
  padding-inline: var(--roo-space-group);
  font-size: var(--roo-p-size-13);
}

.pill-dot :deep(.roo-state-mark-label) {
  position: absolute;
  width: 1px;
  height: 1px;
  overflow: hidden;
  clip-path: inset(50%);
}

.pill-time {
  font-variant-numeric: tabular-nums;
}

.pill-note {
  white-space: nowrap;
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
}

.pill-spacer {
  flex: 1 1 auto;
}

.picker {
  display: flex;
  width: 360px;
  box-sizing: border-box;
  flex-direction: column;
  gap: var(--roo-space-item);
  padding: var(--roo-space-group);
}

.picker-title {
  margin: 0;
  font-size: var(--roo-p-size-13);
  font-weight: 600;
}
</style>
