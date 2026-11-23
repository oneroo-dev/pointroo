<script setup lang="ts">
import { RooKeyHint, RooLiveDot, RooSidebar, RooTreeRow } from '@roo/kit'
import type { Project } from '../data/types'

defineProps<{ projects: Project[]; total: number; selected: string }>()
</script>

<template>
  <RooSidebar label="Projects">
    <RooTreeRow label="All" :selected="selected === 'all'" activation="single">
      <template #meta><span class="count">{{ total }}</span></template>
    </RooTreeRow>
    <RooTreeRow v-for="project in projects" :key="project.id" :label="project.name" :selected="selected === project.id" activation="single">
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
