<script setup lang="ts">
// The results of items.search: one row per item, the title, the match snippet on one line with the typed words in bold, and the
// field that matched marked with a small chip. The first row is the keyboard cursor (Enter opens it).
import { computed } from 'vue'
import { RooChip, RooIcon, RooKeyHint, RooListRow, RooLetterTile, RooMeta } from '@roo/kit'
import type { SearchField } from '../types'
import { lastFolderName } from './projects'
import type { SearchHit } from './types'

const props = defineProps<{ results: SearchHit[]; query: string }>()
const emit = defineEmits<{ open: [itemId: string] }>()

const fieldWords: Record<SearchField, string> = {
  title: 'Title',
  body: 'Details',
  said: 'You said',
  alsoSaid: 'Also said',
  note: 'Agent note',
  project: 'Project',
  firstElement: 'Pointed at',
}

interface Piece {
  text: string
  hit: boolean
}

const words = computed(() => props.query.toLowerCase().split(/\s+/).filter((word) => word !== ''))

function piecesFor(snippet: string): Piece[] {
  if (words.value.length === 0) return [{ text: snippet, hit: false }]
  const lower = snippet.toLowerCase()
  const marked = new Array<boolean>(snippet.length).fill(false)
  for (const word of words.value) {
    let from = lower.indexOf(word)
    while (from !== -1) {
      for (let index = from; index < from + word.length; index += 1) marked[index] = true
      from = lower.indexOf(word, from + word.length)
    }
  }
  const pieces: Piece[] = []
  for (let index = 0; index < snippet.length; index += 1) {
    const hit = marked[index] === true
    const last = pieces[pieces.length - 1]
    if (last !== undefined && last.hit === hit) last.text += snippet.charAt(index)
    else pieces.push({ text: snippet.charAt(index), hit })
  }
  return pieces
}
</script>

<template>
  <div class="results">
    <div class="results-list" role="listbox" aria-label="Search results">
      <RooListRow
        v-for="(result, index) in results"
        :key="result.item.id"
        role="option"
        tabindex="0"
        :selected="index === 0"
        :aria-selected="index === 0"
        :title="result.item.title"
        @click="emit('open', result.item.id)"
        @keydown.enter="emit('open', result.item.id)"
      >
        <template #tile>
          <RooLetterTile v-if="result.item.project !== null" :name="lastFolderName(result.item.project)" :size="22" />
          <RooIcon v-else name="image" :size="16" />
        </template>
        <template #title-trailing>
          <RooChip size="small" :label="fieldWords[result.match.field]" />
        </template>
        <template #subtitle>
          <template v-for="(piece, pieceIndex) in piecesFor(result.match.snippet)" :key="pieceIndex"><span :class="{ hit: piece.hit }">{{ piece.text }}</span></template>
        </template>
        <template #trailing><RooMeta>{{ result.item.age }}</RooMeta></template>
      </RooListRow>
    </div>
    <div class="results-hints">
      <RooKeyHint keys="Enter">Open</RooKeyHint>
      <RooKeyHint keys="Esc">Close search</RooKeyHint>
    </div>
  </div>
</template>

<style scoped>
.results {
  display: flex;
  min-height: 0;
  flex: 1 1 auto;
  flex-direction: column;
  gap: var(--roo-space-item);
}

.results-list {
  display: flex;
  min-height: 0;
  flex: 1 1 auto;
  flex-direction: column;
  gap: var(--roo-space-item);
  overflow-y: auto;
  padding-inline: var(--roo-space-item);
}

.results-hints {
  display: flex;
  flex-wrap: nowrap;
  align-items: center;
  gap: var(--roo-space-group);
  padding: var(--roo-space-item) var(--roo-space-group) var(--roo-space-group);
}

.hit {
  color: var(--roo-text);
  font-weight: 600;
}
</style>
