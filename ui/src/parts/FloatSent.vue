<script setup lang="ts">
// The "Sent to X / Undo" pill, 360 by 56 (the D3 frame PickerOneSession): a recording the app sent by itself. The first line says
// where it went, the second why. Undo takes the send back (key U).
import { RooButton, RooTooltip } from '@roo/kit/controls'
import { RooStateMark } from '@roo/kit'
import FloatingSurface from './FloatingSurface.vue'

defineProps<{ label: string; note: string }>()

const emit = defineEmits<{ undo: [] }>()
</script>

<template>
  <FloatingSurface class="sent" role="status" aria-label="Sent">
    <div class="sent-text">
      <RooStateMark state="ok" :label="label" />
      <span class="sent-note">{{ note }}</span>
    </div>
    <RooTooltip text="Undo" shortcut="U"><RooButton variant="ghost" size="sm" @click="emit('undo')">Undo</RooButton></RooTooltip>
  </FloatingSurface>
</template>

<style scoped>
.sent {
  display: flex;
  width: 360px;
  height: 56px;
  box-sizing: border-box;
  align-items: center;
  justify-content: space-between;
  gap: var(--roo-space-group);
  padding-inline: var(--roo-space-group);
  font-size: var(--roo-p-size-13);
}

.sent-text {
  display: flex;
  min-width: 0;
  flex-direction: column;
  gap: var(--roo-space-item);
}

.sent-note {
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
}
</style>
