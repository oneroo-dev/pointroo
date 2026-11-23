<script setup lang="ts">
import { computed } from 'vue'
import { RooIcon, RooIconButton, RooListRow, RooProgressLine, RooSegmented, RooSidebarGroup, RooStateMark } from '@roo/kit'
import type { Item } from '../data/types'
import { markFor, subtitleFor } from './words'

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
          <template v-if="item.state !== 'processing'" #actions>
            <RooIconButton icon="copy" size="xs" variant="ghost" label="Copy for an agent" tooltip="Copy for an agent" />
            <RooIconButton :icon="item.state === 'done' || item.state === 'done-by-you' ? 'rotate-ccw' : 'check'" size="xs" variant="ghost" :label="item.state === 'done' || item.state === 'done-by-you' ? 'Open again' : 'Mark done'" :tooltip="item.state === 'done' || item.state === 'done-by-you' ? 'Open again' : 'Mark done'" />
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
