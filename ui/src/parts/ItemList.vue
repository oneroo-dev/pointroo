<script setup lang="ts">
// The queue. One row is one recording: a big crop, your words on two lines, then one quiet line that says where it stands, where
// it went and when. It draws the items it is given and raises an event for every click; it holds no data of its own.
// A recording the app just sent is tinted and carries its own Undo, so no toast covers the list.
import { computed } from 'vue'
import { RooButton } from '@roo/kit/controls'
import { RooIcon, RooProgressLine, RooStateMark } from '@roo/kit'
import type { Item, Project } from './types'
import { markFor, plainWords, whereLine } from './words'
import type { Mark } from './words'

const props = withDefaults(
  defineProps<{
    items: Item[]
    projects: Project[]
    selectedId?: string | undefined
    /** The ids of the recordings the app just sent. Their rows are tinted; the first one carries Undo. */
    freshIds?: string[]
  }>(),
  { selectedId: undefined, freshIds: () => [] },
)

const emit = defineEmits<{
  select: [itemId: string]
  sendAll: [itemIds: string[], projectId: string]
  undoSent: []
}>()

const undoId = computed(() => props.items.find((item) => props.freshIds.includes(item.id))?.id)
const notSentRows = computed(() => props.items.filter((item) => item.state === 'not-sent'))

// "Send all" shows only when there are two or more recordings with no project and one guess fits every one of them.
const sendAllTarget = computed<Project | undefined>(() => {
  const rows = notSentRows.value
  if (rows.length < 2) return undefined
  const guess = rows[0]?.suggested
  if (guess === undefined || rows.some((row) => row.suggested !== guess)) return undefined
  return props.projects.find((project) => project.id === guess)
})

function isFresh(item: Item): boolean {
  return props.freshIds.includes(item.id)
}

function thumbFor(item: Item): string | undefined {
  return item.crops[0]?.url
}

function wordsFor(item: Item): string {
  if (item.state === 'processing') return 'Writing it up…'
  const words = plainWords(item.said)
  return words === '' ? 'No speech' : words
}

function markOf(item: Item): Mark {
  return isFresh(item) ? { state: 'ok', label: 'Sent' } : markFor(item)
}

function sendAll(): void {
  const target = sendAllTarget.value
  if (target !== undefined) {
    emit(
      'sendAll',
      notSentRows.value.map((row) => row.id),
      target.id,
    )
  }
}

function onRowKey(event: KeyboardEvent, itemId: string): void {
  if (event.target !== event.currentTarget) return
  event.preventDefault()
  emit('select', itemId)
}
</script>

<template>
  <section class="list" aria-label="Recordings">
    <div v-if="sendAllTarget" class="list-bulk">
      <RooButton variant="ghost" size="sm" @click="sendAll">Send all {{ notSentRows.length }} to {{ sendAllTarget.name }}</RooButton>
    </div>
    <div class="queue" role="listbox" aria-label="Recordings">
      <div
        v-for="item in items"
        :key="item.id"
        class="row"
        role="option"
        tabindex="0"
        :aria-selected="item.id === selectedId"
        :data-selected="item.id === selectedId ? 'true' : undefined"
        :data-fresh="isFresh(item) ? 'true' : undefined"
        @click="emit('select', item.id)"
        @keydown.enter="onRowKey($event, item.id)"
        @keydown.space="onRowKey($event, item.id)"
      >
        <span class="shot">
          <img v-if="thumbFor(item)" class="shot-image" :src="thumbFor(item)" alt="" />
          <span v-else class="shot-empty"><RooIcon name="image" :size="16" /></span>
          <span v-if="item.crops.length > 1" class="shot-count">{{ item.crops.length }}</span>
        </span>
        <span class="text">
          <span class="said">{{ wordsFor(item) }}</span>
          <RooProgressLine v-if="item.state === 'processing'" busy :delay="0" />
          <span v-else class="meta">
            <RooStateMark :state="markOf(item).state" :label="markOf(item).label" />
            <span class="where">{{ whereLine(item) }}</span>
          </span>
        </span>
        <RooButton v-if="item.id === undoId" variant="ghost" size="sm" @click.stop="emit('undoSent')">Undo</RooButton>
      </div>
    </div>
  </section>
</template>

<style scoped>
.list {
  display: flex;
  min-height: 0;
  flex-direction: column;
}

.list-bulk {
  padding: var(--roo-space-item) var(--roo-space-group) 0;
}

.queue {
  display: flex;
  flex-direction: column;
  gap: var(--roo-p-space-1);
  padding: var(--roo-space-item);
}

.row {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: var(--roo-space-group);
  padding: var(--roo-space-item);
  border-radius: var(--roo-p-radius-card);
  cursor: default;
}

.row:hover {
  background: var(--roo-raised-hover);
}

.row[data-selected] {
  background: var(--roo-select);
}

.row[data-fresh] {
  background: var(--roo-accent-bg);
}

.row:focus-visible {
  outline: 2px solid var(--roo-focus);
  outline-offset: -2px;
}

.shot {
  position: relative;
  display: block;
  width: 112px;
  height: 72px;
  flex: none;
  box-sizing: border-box;
  overflow: hidden;
  border: 1px solid var(--roo-border);
  border-radius: var(--roo-p-radius-medium);
  background: var(--roo-raised);
}

.shot-image {
  display: block;
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.shot-empty {
  display: flex;
  width: 100%;
  height: 100%;
  align-items: center;
  justify-content: center;
  color: var(--roo-muted);
}

.shot-count {
  position: absolute;
  inset-block-end: var(--roo-p-space-1);
  inset-inline-end: var(--roo-p-space-1);
  padding: 0 var(--roo-p-space-2);
  border-radius: var(--roo-p-radius-pill);
  background: var(--roo-surface);
  color: var(--roo-text);
  font-size: var(--roo-p-size-11);
  font-variant-numeric: tabular-nums;
  font-weight: 600;
  line-height: 1.6;
}

.text {
  display: flex;
  min-width: 0;
  flex: 1 1 auto;
  flex-direction: column;
  gap: var(--roo-space-item);
}

.said {
  display: -webkit-box;
  overflow: hidden;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
  font-size: var(--roo-p-size-14);
  font-weight: 500;
  line-height: 1.4;
}

.meta {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: var(--roo-space-item);
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
}

.where {
  min-width: 0;
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
}
</style>
