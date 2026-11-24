<script setup lang="ts">
// The main area while a search is set (D3 SearchOpen, SearchNarrow, SearchEmpty): the status chips as a segmented control, the
// result count, then the results. With none there is one line and Clear search; while the app answers there are placeholder
// rows; if it fails there is one line.
import { computed } from 'vue'
import { RooButton } from '@roo/kit/controls'
import { RooEmpty, RooKbd, RooSegmented, RooSkeleton } from '@roo/kit'
import SearchResults from './SearchResults.vue'
import type { SearchFilter } from '../types'
import type { SearchHit } from './types'

const props = withDefaults(defineProps<{ query: string; hits: SearchHit[]; loading?: boolean; error?: string | undefined }>(), { loading: false, error: undefined })
const emit = defineEmits<{ open: [itemId: string]; clear: [] }>()
const status = defineModel<SearchFilter>('status', { default: 'all' })

const options = [
  { value: 'open', label: 'Open' },
  { value: 'in_progress', label: 'In progress' },
  { value: 'done', label: 'Done' },
  { value: 'all', label: 'All' },
]

function onStatus(value: string): void {
  if (value === 'open' || value === 'in_progress' || value === 'done' || value === 'all') status.value = value
}

const countText = computed(() => `${props.hits.length} ${props.hits.length === 1 ? 'result' : 'results'}`)
</script>

<template>
  <div class="search-main">
    <div class="search-filters">
      <RooSegmented :model-value="status" label="Show" size="md" :options="options" @update:model-value="onStatus" />
      <span v-if="!loading && error === undefined" class="search-count">{{ countText }}</span>
    </div>
    <div v-if="loading" class="search-placeholder"><RooSkeleton row :rows="5" /></div>
    <div v-else-if="error !== undefined" class="search-empty">
      <RooEmpty filtered :title="error" />
    </div>
    <SearchResults v-else-if="hits.length > 0" :results="hits" :query="query" @open="(itemId) => emit('open', itemId)" />
    <div v-else class="search-empty">
      <RooEmpty filtered :title="`No items match &quot;${query}&quot;`">
        <RooButton variant="secondary" size="sm" @click="emit('clear')">
          <span class="clear-label"><span>Clear search</span><RooKbd keys="Esc" /></span>
        </RooButton>
      </RooEmpty>
    </div>
  </div>
</template>

<style scoped>
.search-main {
  display: flex;
  height: 100%;
  min-height: 0;
  flex-direction: column;
  gap: var(--roo-space-item);
}

.search-filters {
  display: flex;
  flex-wrap: nowrap;
  align-items: center;
  justify-content: space-between;
  gap: var(--roo-space-group);
  padding: var(--roo-space-group);
}

.search-count {
  white-space: nowrap;
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
}

.search-placeholder {
  padding-inline: var(--roo-space-group);
}

.search-empty {
  display: flex;
  flex: 1 1 auto;
  align-items: center;
  justify-content: center;
  padding: var(--roo-space-group);
}

.clear-label {
  display: inline-flex;
  align-items: center;
  gap: var(--roo-space-item);
}
</style>
