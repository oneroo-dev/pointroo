<script setup lang="ts">
// The project picker of the kit window, 360 wide, drawn from the picker.get reply: the guess first and marked, number keys on the
// rows, a countdown line and Skip (Esc). With `one-session` there is no picker: the recording went to the only listening session
// and the pill says so with Undo.
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { RooButton, RooTooltip } from '@roo/kit/controls'
import { RooCountdown, RooKbd, RooStateMark } from '@roo/kit'
import ProjectTiles from '../../src/parts/ProjectTiles.vue'
import FloatingSurface from './FloatingSurface.vue'
import { onlySession, pickerReply, pickerTiles } from '../data/pill'

const props = defineProps<{ kind: 'open' | 'one-session' }>()

// The mockup holds the countdown still: the end time is pushed on every half second, so a still frame never reads "expired".
const endsAt = ref(Date.now() + pickerReply.countdown * 1000)
let hold: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  if (props.kind !== 'open') return
  hold = setInterval(() => {
    endsAt.value = Date.now() + pickerReply.countdown * 1000
  }, 500)
})
onBeforeUnmount(() => clearInterval(hold))
</script>

<template>
  <FloatingSurface v-if="kind === 'open'" class="picker" role="group" aria-label="Pick a project">
    <h2 class="picker-title">Which project is this for?</h2>
    <ProjectTiles size="large" layout="list" :tiles="pickerTiles" label="Which project is this for?" show-keys />
    <div class="picker-foot">
      <span class="picker-note"><RooCountdown :ends-at="endsAt" :warn-seconds="0" suffix="until it skips" /></span>
      <RooTooltip text="Keep it not sent" shortcut="Escape">
        <RooButton variant="ghost" size="sm">
          <span class="picker-skip"><span>Skip</span><RooKbd keys="Esc" /></span>
        </RooButton>
      </RooTooltip>
    </div>
  </FloatingSurface>

  <FloatingSurface v-else class="sent" role="status" aria-label="Sent">
    <div class="sent-text">
      <RooStateMark state="ok" :label="`Sent to ${onlySession.name}`" />
      <span class="sent-note">Only session listening</span>
    </div>
    <RooTooltip text="Undo" shortcut="Mod+Z"><RooButton variant="ghost" size="sm">Undo</RooButton></RooTooltip>
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
