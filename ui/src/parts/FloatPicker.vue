<script setup lang="ts">
// The project picker (the D4 frame D4Picker): the projects only. The first row is the guess, marked as picked. Every row shows its
// number key. When the timer runs out the app sends nowhere (ProjectPicker keeps it in the queue), so the bottom line says how long
// is left to pick, and Skip (Esc).
// A click raises `pick` with the folder; the keys are handled by the app itself.
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { RooButton, RooTooltip } from '@roo/kit/controls'
import { RooKbd, RooLetterTile, RooListRow, RooProgressRing } from '@roo/kit'
import { secondsLeft } from '../floatModel'
import FloatingSurface from './FloatingSurface.vue'
import type { ProjectTile } from './types'

const props = defineProps<{ tiles: ProjectTile[]; endsAt?: number | undefined }>()

const emit = defineEmits<{ pick: [path: string]; skip: [] }>()

const nowMilliseconds = ref(Date.now())
const totalSeconds = ref(1)
let clock: ReturnType<typeof setInterval> | undefined

/** The guess: the row the app marked, else the first row. */
const guess = computed(() => props.tiles.find((tile) => tile.suggested === true) ?? props.tiles[0])
const remaining = computed(() => (props.endsAt === undefined ? undefined : secondsLeft(props.endsAt, nowMilliseconds.value)))
const percent = computed(() => (remaining.value === undefined ? 0 : Math.round((remaining.value / totalSeconds.value) * 100)))

watch(
  () => props.endsAt,
  (endsAt) => {
    nowMilliseconds.value = Date.now()
    if (endsAt !== undefined) totalSeconds.value = Math.max(1, secondsLeft(endsAt, nowMilliseconds.value))
  },
  { immediate: true },
)

onMounted(() => {
  clock = setInterval(() => {
    nowMilliseconds.value = Date.now()
  }, 1000)
})

onBeforeUnmount(() => {
  clearInterval(clock)
})
</script>

<template>
  <FloatingSurface class="picker" role="group" aria-label="Pick a project">
    <div class="rows" role="listbox" aria-label="Pick a project">
      <RooListRow
        v-for="(tile, index) in tiles"
        :key="tile.id"
        size="dense"
        role="option"
        tabindex="0"
        :selected="tile.id === guess?.id"
        :aria-selected="tile.id === guess?.id"
        :title="tile.name"
        @click="emit('pick', tile.id)"
        @keydown.enter.prevent="emit('pick', tile.id)"
      >
        <template #tile><RooLetterTile :name="tile.name" :size="22" /></template>
        <template #trailing><RooKbd :keys="String(index + 1)" /></template>
      </RooListRow>
    </div>
    <div class="foot">
      <template v-if="remaining !== undefined">
        <RooProgressRing :size="14" :value="percent" :label="`${remaining} seconds left`" />
        <span class="note">{{ remaining }} s to pick</span>
      </template>
      <span class="spacer" />
      <RooTooltip text="Keep it not sent" shortcut="Escape">
        <RooButton variant="ghost" size="sm" @click="emit('skip')">
          <span class="skip"><span>Skip</span><RooKbd keys="Esc" /></span>
        </RooButton>
      </RooTooltip>
    </div>
  </FloatingSurface>
</template>

<style scoped>
.picker {
  display: flex;
  width: 280px;
  flex: none;
  flex-direction: column;
  gap: var(--roo-p-space-1);
  padding: var(--roo-space-item);
}

.rows {
  display: flex;
  flex-direction: column;
  gap: var(--roo-p-space-1);
}

.foot {
  display: flex;
  align-items: center;
  gap: var(--roo-space-item);
  padding-inline-start: var(--roo-space-item);
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
}

.note {
  white-space: nowrap;
}

.spacer {
  flex: 1 1 auto;
}

.skip {
  display: inline-flex;
  align-items: center;
  gap: var(--roo-space-item);
}
</style>
