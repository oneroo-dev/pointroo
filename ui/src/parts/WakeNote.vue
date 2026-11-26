<script setup lang="ts">
// One small line next to "Sent to X": what the wake did for this recording.
import { computed } from 'vue'
import type { WakeNote } from './types'

const props = defineProps<{ note: WakeNote }>()

const text = computed(() => {
  switch (props.note.kind) {
    case 'woke':
      return props.note.name === undefined ? 'Woke the session' : `Woke ${props.note.name}`
    case 'no-session':
      return 'No session to wake'
    case 'busy':
      return 'Session busy, will see it next'
    case 'too-old':
      return 'Claude Code too old to wake'
  }
})
</script>

<template>
  <span class="wake" :data-kind="note.kind">{{ `· ${text}` }}</span>
</template>

<style scoped>
.wake {
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
  white-space: nowrap;
}
</style>
