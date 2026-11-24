<script setup lang="ts">
// The live pill, 360 by 56 (the D3 frames PillRecording and PillProcessing). Recording shows a dot, the time and the points, with
// Stop and Cancel as icon buttons. Processing shows "Making items" and nothing to click.
import { computed } from 'vue'
import { RooIconButton } from '@roo/kit/controls'
import { RooProgressRing, RooStateMark } from '@roo/kit'
import FloatingSurface from './FloatingSurface.vue'

const props = defineProps<{ phase: 'recording' | 'processing'; elapsed: string; points: number }>()

const emit = defineEmits<{ stop: []; cancel: [] }>()

const pointsText = computed(() => `${props.points} ${props.points === 1 ? 'point' : 'points'}`)
</script>

<template>
  <FloatingSurface class="pill" role="status" :aria-label="phase === 'recording' ? 'Recording' : 'Making items'">
    <template v-if="phase === 'recording'">
      <RooStateMark state="err" label="Recording" class="pill-dot" />
      <span class="pill-time">{{ elapsed }}</span>
      <span class="pill-note">{{ pointsText }}</span>
      <span class="pill-spacer" />
      <RooIconButton icon="stop" variant="primary" size="sm" label="Stop" tooltip="Stop and make items" shortcut="Control Control" @click="emit('stop')" />
      <RooIconButton icon="x" variant="ghost" size="sm" label="Cancel" tooltip="Cancel and keep nothing" shortcut="Escape" @click="emit('cancel')" />
    </template>
    <template v-else>
      <RooProgressRing :size="16" label="Making items" />
      <span class="pill-text">Making items</span>
      <span class="pill-spacer" />
      <span class="pill-note">{{ pointsText }}</span>
    </template>
  </FloatingSurface>
</template>

<style scoped>
.pill {
  display: flex;
  width: 360px;
  height: 56px;
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
  white-space: nowrap;
}

.pill-text {
  white-space: nowrap;
}

.pill-note {
  white-space: nowrap;
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
}

.pill-spacer {
  flex: 1 1 auto;
}
</style>
