<script setup lang="ts">
// The line above the queue when something needs the user: a missing permission, a busy port, an MCP error, no listening session.
import { computed } from 'vue'
import { RooButton } from '@roo/kit/controls'
import { RooStateCard } from '@roo/kit'
import type { MainBanner } from './types'

const props = defineProps<{ banner: MainBanner }>()

const emit = defineEmits<{
  allow: [which: NonNullable<MainBanner['which']>]
  useOtherPort: []
  details: []
  retry: []
  copy: []
}>()

const words = computed(() => {
  switch (props.banner.kind) {
    case 'permission':
      return { title: "Pointroo can't hear you", description: 'Microphone is off: no speech recorded.' }
    case 'port-busy':
      return { title: "Agents can't reach Pointroo", description: 'Port 6742 is used by another app.' }
    case 'mcp-error':
      return { title: "Agents can't reach Pointroo", description: 'The server could not start (error 13).' }
    default:
      return { title: 'No Claude session is listening', description: "Say 'work through Pointroo' in Claude Code." }
  }
})
const title = computed(() => props.banner.title ?? words.value.title)
const description = computed(() => props.banner.description ?? words.value.description)
</script>

<template>
  <RooStateCard
    :layout="banner.kind === 'no-session' ? 'strip' : 'band'"
    :kind="banner.kind === 'permission' ? 'warn' : banner.kind === 'no-session' ? 'info' : 'error'"
    :title="title"
    :description="description"
  >
    <template #actions>
      <RooButton v-if="banner.kind === 'permission'" size="sm" variant="secondary" @click="emit('allow', banner.which ?? 'microphone')">Allow</RooButton>
      <template v-else-if="banner.kind === 'port-busy'">
        <RooButton size="sm" variant="primary" @click="emit('useOtherPort')">Use another port</RooButton>
        <RooButton size="sm" variant="ghost" @click="emit('details')">Details</RooButton>
      </template>
      <RooButton v-else-if="banner.kind === 'mcp-error'" size="sm" variant="primary" @click="emit('retry')">Try again</RooButton>
      <RooButton v-else size="sm" variant="secondary" @click="emit('copy')">Copy</RooButton>
    </template>
  </RooStateCard>
</template>
