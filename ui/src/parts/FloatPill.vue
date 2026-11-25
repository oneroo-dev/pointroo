<script setup lang="ts">
// The live pill (the D4 frames D4Pill): 44 high and only as wide as it needs. Recording shows a red dot, the time, how many points,
// Stop and a small x (Cancel). While the items are made it shows a ring and "Writing it up".
import { RooIconButton } from '@roo/kit/controls'
import { RooIcon, RooProgressRing } from '@roo/kit'
import FloatingSurface from './FloatingSurface.vue'

defineProps<{ phase: 'recording' | 'processing'; elapsed: string; points: number }>()

const emit = defineEmits<{ stop: []; cancel: [] }>()
</script>

<template>
  <FloatingSurface pill class="pill" role="status" :aria-label="phase === 'recording' ? 'Recording' : 'Writing it up'">
    <template v-if="phase === 'recording'">
      <span class="dot roo-move-breathe" aria-hidden="true" />
      <span class="roo-visually-hidden">Recording</span>
      <span class="time">{{ elapsed }}</span>
      <span class="points"><RooIcon name="mouse-pointer-click" :size="14" />{{ points }}</span>
      <RooIconButton icon="stop" variant="primary" size="xs" shape="round" label="Stop" tooltip="Stop and send" shortcut="Control Control" @click="emit('stop')" />
      <RooIconButton icon="x" variant="ghost" size="xxs" shape="round" label="Cancel" tooltip="Cancel and keep nothing" shortcut="Escape" @click="emit('cancel')" />
    </template>
    <template v-else>
      <RooProgressRing :size="16" label="Writing it up" />
      <span class="text">Writing it up</span>
    </template>
  </FloatingSurface>
</template>

<style scoped>
.pill {
  display: inline-flex;
  height: 44px;
  flex: none;
  align-items: center;
  gap: var(--roo-space-item);
  padding-inline: var(--roo-space-group);
  white-space: nowrap;
}

.dot {
  display: block;
  width: 10px;
  height: 10px;
  flex: none;
  border-radius: var(--roo-p-radius-pill);
  background: var(--roo-danger);
}

.time {
  font-variant-numeric: tabular-nums;
  font-weight: 500;
}

.text {
  white-space: nowrap;
}

.points {
  display: inline-flex;
  align-items: center;
  gap: var(--roo-p-space-1);
  margin-inline-end: var(--roo-space-item);
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
  font-variant-numeric: tabular-nums;
}
</style>
