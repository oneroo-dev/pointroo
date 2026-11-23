<script setup lang="ts">
// The live pill of the kit window, 360 by 56. Recording shows a dot, the time and the points, with Stop and Cancel as icon
// buttons. Processing shows "Making items" and nothing to click. The data is what recording.get gives (phase, points, startedAt).
import { RooIconButton } from '@roo/kit/controls'
import { RooProgressRing, RooStateMark } from '@roo/kit'
import FloatingSurface from './FloatingSurface.vue'
import { recordingSample } from '../data/pill'

defineProps<{ phase: 'recording' | 'processing' }>()
</script>

<template>
  <FloatingSurface class="pill" role="status" :aria-label="phase === 'recording' ? 'Recording' : 'Making items'">
    <template v-if="phase === 'recording'">
      <RooStateMark state="err" label="Recording" class="pill-dot" />
      <span class="pill-time">{{ recordingSample.elapsed }}</span>
      <span class="pill-note">{{ recordingSample.points }} points</span>
      <span class="pill-spacer" />
      <RooIconButton icon="stop" variant="primary" size="sm" label="Stop" tooltip="Stop and make items" shortcut="Control Control" />
      <RooIconButton icon="x" variant="ghost" size="sm" label="Cancel" tooltip="Cancel and keep nothing" shortcut="Escape" />
    </template>
    <template v-else>
      <RooProgressRing :size="16" label="Making items" />
      <span class="pill-text">Making items</span>
      <span class="pill-spacer" />
      <span class="pill-note">{{ recordingSample.points }} points</span>
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
