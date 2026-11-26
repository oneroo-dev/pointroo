<script setup lang="ts">
// A hint the app shows in a toast (no project, speech download failed, port moved). The app shows it where toasts go; the
// mockups draw it in place.
import { RooToast } from '@roo/kit'
import type { HintView } from './types'

defineProps<{ hint: HintView }>()

const emit = defineEmits<{ action: []; dismiss: [] }>()
</script>

<template>
  <RooToast :tone="hint.tone" :message="hint.message" :action-label="hint.actionLabel ?? ''" @action="emit('action')" @dismiss="emit('dismiss')" />
</template>
