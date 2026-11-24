<script setup lang="ts">
// The project picker, 360 wide (the D3 frame PickerOpen): the guess first and marked, number keys on the rows, a countdown
// line and Skip (Esc). A click raises `pick` with the folder; the keys are handled by the app itself.
import { RooButton, RooTooltip } from '@roo/kit/controls'
import { RooCountdown, RooKbd } from '@roo/kit'
import FloatingSurface from './FloatingSurface.vue'
import ProjectTiles from './ProjectTiles.vue'
import type { ProjectTile } from './types'

defineProps<{ tiles: ProjectTile[]; endsAt?: number | undefined }>()

const emit = defineEmits<{ pick: [path: string]; skip: [] }>()
</script>

<template>
  <FloatingSurface class="picker" role="group" aria-label="Pick a project">
    <h2 class="picker-title">Which project is this for?</h2>
    <ProjectTiles size="large" layout="list" :tiles="tiles" label="Which project is this for?" show-keys show-more @pick="(path) => emit('pick', path)" />
    <div class="picker-foot">
      <span class="picker-note"><RooCountdown v-if="endsAt !== undefined" :ends-at="endsAt" :warn-seconds="0" suffix="until it skips" /></span>
      <RooTooltip text="Keep it not sent" shortcut="Escape">
        <RooButton variant="ghost" size="sm" @click="emit('skip')">
          <span class="picker-skip"><span>Skip</span><RooKbd keys="Esc" /></span>
        </RooButton>
      </RooTooltip>
    </div>
  </FloatingSurface>
</template>

<style scoped>
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

.picker-foot {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--roo-space-group);
}

.picker-note {
  min-width: 0;
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
}

.picker-skip {
  display: inline-flex;
  align-items: center;
  gap: var(--roo-space-item);
}
</style>
