<script setup lang="ts">
// The project name in a small kit chip with a chevron. A click opens a menu of the projects (listening ones first, the current one
// checked); a pick raises `pick` with the project id. The screen that holds it decides what a pick does (send or move).
import { computed, ref } from 'vue'
import { RooChip, RooIcon } from '@roo/kit'
import { RooMenu, RooMenuItem } from '@roo/kit/overlays'
import { orderProjects } from './projects'
import type { Project } from './types'

const props = withDefaults(defineProps<{ name: string; projects: Project[]; currentId?: string | undefined }>(), { currentId: undefined })

const emit = defineEmits<{ pick: [projectId: string] }>()

const open = ref(false)
const choices = computed(() => orderProjects(props.projects))

function onSelect(projectId: string): void {
  if (projectId !== props.currentId) emit('pick', projectId)
}
</script>

<template>
  <RooMenu v-model:open="open" align="start">
    <template #trigger>
      <RooChip interactive size="small" tone="neutral" class="project-menu" :aria-label="`${name}. Choose a project`" @click.stop>
        <span class="project-name">{{ name }}</span>
        <RooIcon name="chevron-down" :size="12" />
      </RooChip>
    </template>
    <RooMenuItem v-for="project in choices" :key="project.id" :checked="project.id === currentId" :hint="project.listening ? 'listening' : project.sessionOpen === true ? 'open' : ''" @select="onSelect(project.id)">{{ project.name }}</RooMenuItem>
  </RooMenu>
</template>

<style scoped>
.project-menu {
  min-width: 0;
  max-width: 100%;
  flex: 0 1 auto;
}

.project-name {
  min-width: 0;
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
}
</style>
