<script setup lang="ts">
// The project name as quiet text with a small chevron. A click opens a menu of the projects (listening ones first, the current one
// checked); a pick raises `pick` with the project id. The screen that holds it decides what a pick does (send or move).
import { computed, ref } from 'vue'
import { RooIcon } from '@roo/kit'
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
      <button type="button" class="project-menu" :aria-label="`${name}. Choose a project`" :data-open="open ? 'true' : undefined" @click.stop>
        <span class="project-name">{{ name }}</span>
        <RooIcon name="chevron-down" :size="12" />
      </button>
    </template>
    <RooMenuItem v-for="project in choices" :key="project.id" :checked="project.id === currentId" :hint="project.listening ? 'listening' : ''" @select="onSelect(project.id)">{{ project.name }}</RooMenuItem>
  </RooMenu>
</template>

<style scoped>
.project-menu {
  display: inline-flex;
  min-width: 0;
  align-items: center;
  gap: var(--roo-p-space-1);
  padding: 0;
  border: 0;
  background: none;
  color: inherit;
  cursor: default;
  font: inherit;
}

.project-menu:hover,
.project-menu[data-open] {
  color: var(--roo-text);
}

.project-menu:focus-visible {
  border-radius: var(--roo-p-radius-small);
  outline: 2px solid var(--roo-focus);
  outline-offset: 2px;
}

.project-name {
  min-width: 0;
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
}
</style>
