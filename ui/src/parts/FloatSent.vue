<script setup lang="ts">
// The "Sent to X / Change / Undo" pill (the D4 frame D4Pill, sent state): where it went, Change and Undo, on one line. Change opens
// the project picker for this recording (key C). Undo takes the send back (key U). The `note` (why the app chose that project) is
// kept for callers but no longer shown.
import { RooButton, RooTooltip } from '@roo/kit/controls'
import { RooStateMark } from '@roo/kit'
import FloatingSurface from './FloatingSurface.vue'

defineProps<{ label: string; note?: string }>()

const emit = defineEmits<{ undo: []; change: [] }>()
</script>

<template>
  <FloatingSurface pill class="sent" role="status" aria-label="Sent">
    <RooStateMark state="ok" :label="label" />
    <RooTooltip text="Choose another project" shortcut="C"><RooButton variant="ghost" size="sm" @click="emit('change')">Change</RooButton></RooTooltip>
    <RooTooltip text="Undo" shortcut="U"><RooButton variant="ghost" size="sm" @click="emit('undo')">Undo</RooButton></RooTooltip>
  </FloatingSurface>
</template>

<style scoped>
.sent {
  display: inline-flex;
  height: 44px;
  flex: none;
  align-items: center;
  gap: var(--roo-space-item);
  padding-inline: var(--roo-space-group);
  white-space: nowrap;
}
</style>
