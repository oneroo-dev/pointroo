<script setup lang="ts">
import { RooButton, RooIconButton, RooTooltip } from '@roo/kit/controls'
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { RooCountdown, RooIcon, RooKbd, RooProgressLine, RooStateMark } from '@roo/kit'
import { tilesFor } from '../data/projects'
import { notSent } from '../data/items'
import FloatingSurface from './FloatingSurface.vue'
import ProjectTiles from './ProjectTiles.vue'

export type PillKind = 'recording' | 'writing' | 'sent' | 'sent-undo' | 'reply' | 'error' | 'kept' | 'picker' | 'picker-auto'

const props = defineProps<{ kind: PillKind }>()

const choice = tilesFor(notSent.suggested, 5)
const suggestedName = choice.tiles.find((tile) => tile.suggested)?.name ?? ''

// The mockup holds the countdown at 3 seconds: the end time is pushed on every half second, so a still frame never reads "expired".
const endsAt = ref(Date.now() + 3000)
let hold: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  if (props.kind !== 'picker-auto') return
  hold = setInterval(() => {
    endsAt.value = Date.now() + 3000
  }, 500)
})
onBeforeUnmount(() => clearInterval(hold))
</script>

<template>
  <FloatingSurface v-if="kind === 'picker' || kind === 'picker-auto'" class="picker" role="group" aria-label="Pick a project">
    <h2 class="picker-title">{{ kind === 'picker-auto' ? `Sending to ${suggestedName}` : 'Which project is this for?' }}</h2>
    <p v-if="kind === 'picker-auto'" class="picker-note">
      <RooCountdown :ends-at="endsAt" :warn-seconds="0" suffix="until it sends" />
    </p>
    <ProjectTiles size="large" :tiles="choice.tiles" :more-rows="choice.rest" label="Which project is this for?" show-keys show-more />
    <p class="picker-note">
      <RooKbd keys="Esc" />
      <span>Keep it not sent</span>
    </p>
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
    <template v-else-if="kind === 'sent-undo'">
      <RooStateMark state="ok" label="Sent to Pointroo" />
      <span class="pill-spacer" />
      <RooButton variant="ghost" size="sm"><span class="pill-action">Undo<RooKbd keys="Mod+Z" /></span></RooButton>
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

.picker-note {
  display: flex;
  align-items: center;
  gap: var(--roo-space-item);
  margin: 0;
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
}

.pill-action {
  display: inline-flex;
  align-items: center;
  gap: var(--roo-space-item);
}
</style>
