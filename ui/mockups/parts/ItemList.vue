<script setup lang="ts">
import { computed } from 'vue'
import { RooButton } from '@roo/kit/controls'
import { RooIcon, RooIconButton, RooListRow, RooProgressLine, RooSegmented, RooSidebarGroup, RooStateMark } from '@roo/kit'
import type { Item } from '../data/types'
import { projects, tilesFor } from '../data/projects'
import { markFor, subtitleFor } from './words'
import ProjectTiles from './ProjectTiles.vue'

const props = defineProps<{
  items: Item[]
  tab: 'now' | 'done'
  nowCount: number
  doneCount: number
  selectedId?: string
  grouped?: boolean
}>()

const tabModel = defineModel<'now' | 'done'>('tab', { default: 'now' })

const options = computed(() => [
  { value: 'now', label: 'Now', count: props.nowCount },
  { value: 'done', label: 'Done', count: props.doneCount },
])

const groups = computed(() => {
  if (!props.grouped) return [{ name: '', rows: props.items }]
  const names: string[] = []
  for (const item of props.items) {
    const name = item.project ?? 'Not sent'
    if (!names.includes(name)) names.push(name)
  }
  return names.map((name) => ({ name, rows: props.items.filter((item) => (item.project ?? 'Not sent') === name) }))
})

function chipsFor(item: Item) {
  return tilesFor(item.suggested, 3).tiles
}

// "Send all" shows only when one guess fits every item of the Not sent group.
function sendAllTarget(groupName: string, rows: Item[]): string | undefined {
  if (groupName !== 'Not sent' || rows.length === 0) return undefined
  const guess = rows[0]?.suggested
  if (guess === undefined || rows.some((row) => row.suggested !== guess)) return undefined
  return projects.find((project) => project.id === guess)?.name
}

function isDoneState(item: Item): boolean {
  return item.state === 'done' || item.state === 'done-by-you'
}

function titleFor(item: Item): string {
  if (item.state === 'processing') return 'Writing it up…'
  return item.said === '' ? 'No speech' : item.title
}
</script>

<template>
  <section class="list" aria-label="Recordings">
    <div class="list-head">
      <RooSegmented v-model="tabModel" label="Show" size="sm" :options="options" />
    </div>
    <div class="list-body" role="listbox" aria-label="Recordings">
      <component :is="grouped ? RooSidebarGroup : 'div'" v-for="group in groups" :key="group.name" v-bind="grouped ? { label: group.name, count: group.rows.length, collapsible: true, placement: 'sidebar' } : {}">
        <template v-if="sendAllTarget(group.name, group.rows)" #actions>
          <RooButton variant="ghost" size="compact">Send all to {{ sendAllTarget(group.name, group.rows) }}</RooButton>
        </template>
        <RooListRow
          v-for="item in group.rows"
          :key="item.id"
          role="option"
          tabindex="0"
          :selected="item.id === selectedId"
          :aria-selected="item.id === selectedId"
          :title="titleFor(item)"
          :subtitle="item.state === 'processing' ? '' : subtitleFor(item, tab === 'done')"
        >
          <template #tile><RooIcon name="image" :size="16" /></template>
          <template #title-trailing>
            <RooStateMark v-if="item.state !== 'processing'" :state="markFor(item).state" :label="markFor(item).label" />
          </template>
          <template v-if="item.state === 'processing'" #subtitle><RooProgressLine busy :delay="0" /></template>
          <template v-if="item.state === 'not-sent'" #actions>
            <ProjectTiles size="small" :tiles="chipsFor(item)" label="Send to" />
          </template>
          <template v-else-if="item.state === 'waiting'" #actions>
            <RooIconButton icon="check" size="xs" variant="ghost" label="Mark done" tooltip="Mark done" shortcut="D" />
            <RooIconButton icon="trash" size="xs" variant="ghost" label="Move to Trash" tooltip="Move to Trash" shortcut="Delete" />
            <RooIconButton icon="copy" size="xs" variant="ghost" label="Copy for an agent" tooltip="Copy for an agent" />
          </template>
          <template v-else-if="item.state !== 'processing'" #actions>
            <RooIconButton icon="copy" size="xs" variant="ghost" label="Copy for an agent" tooltip="Copy for an agent" />
            <RooIconButton :icon="isDoneState(item) ? 'rotate-ccw' : 'check'" size="xs" variant="ghost" :label="isDoneState(item) ? 'Open again' : 'Mark done'" :tooltip="isDoneState(item) ? 'Open again' : 'Mark done'" />
            <RooIconButton icon="folder-open" size="xs" variant="ghost" label="Show in Finder" tooltip="Show in Finder" />
          </template>
        </RooListRow>
      </component>
    </div>
  </section>
</template>

<style scoped>
.list {
  display: flex;
  height: 100%;
  min-height: 0;
  flex-direction: column;
  gap: var(--roo-space-item);
}

.list-head {
  padding: var(--roo-space-group);
}

.list-body {
  display: flex;
  min-height: 0;
  flex: 1 1 auto;
  flex-direction: column;
  gap: var(--roo-space-item);
  overflow-y: auto;
  padding-inline: var(--roo-space-item);
}
</style>
