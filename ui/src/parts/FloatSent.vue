<script setup lang="ts">
// The "Sent to X / Undo" pill (the D4 frame D4Pill, sent state): where it went and Undo, on one line. Undo takes the send back
// (key U). The `note` (why the app chose that project) is kept for callers but no longer shown.
import { RooButton, RooTooltip } from '@roo/kit/controls'
import { RooStateMark } from '@roo/kit'
import FloatingSurface from './FloatingSurface.vue'

defineProps<{ label: string; note?: string }>()

const emit = defineEmits<{ undo: [] }>()
</script>

<template>
  <FloatingSurface pill class="sent" role="status" aria-label="Sent">
    <RooStateMark state="ok" :label="label" />
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
