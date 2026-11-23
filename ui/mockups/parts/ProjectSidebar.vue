<script setup lang="ts">
import { computed } from 'vue'
import { RooKbd, RooKeyHint, RooLiveDot, RooSidebar, RooTreeRow } from '@roo/kit'
import type { Project } from '../data/types'

const props = defineProps<{ projects: Project[]; total: number; selected: string }>()

// Projects that listen come first, then the most recently used. The number shows on hover: Cmd+1 to 9 jumps there.
const ordered = computed(() =>
  [...props.projects].sort((first, second) => {
    if (first.listening !== second.listening) return first.listening ? -1 : 1
    return first.recentRank - second.recentRank
  }),
)
</script>

<template>
  <RooSidebar label="Projects">
    <RooTreeRow label="All" :selected="selected === 'all'" activation="single">
      <template #meta><span class="count">{{ total }}</span></template>
    </RooTreeRow>
    <RooTreeRow v-for="(project, index) in ordered" :key="project.id" :label="project.name" :selected="selected === project.id" activation="single">
      <template #actions><RooKbd :keys="`Mod+${index + 1}`" /></template>
      <template #meta>
        <span class="meta">
          <RooLiveDot v-if="project.listening" state="live" word="Listening" />
          <span v-if="project.count > 0" class="count">{{ project.count }}</span>
        </span>
      </template>
    </RooTreeRow>
    <template #caption>
      <RooKeyHint class="hint" keys="Ctrl Ctrl">Record from any app</RooKeyHint>
    </template>
  </RooSidebar>
</template>

<style scoped>
.meta {
  display: flex;
  align-items: center;
  gap: var(--roo-space-group);
}

.hint {
  flex-wrap: wrap;
}

.count {
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
  font-variant-numeric: tabular-nums;
}
</style>
