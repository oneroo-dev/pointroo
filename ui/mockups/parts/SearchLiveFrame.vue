<script setup lang="ts">
// A review frame round the real main window part (src/parts/MainWindow.vue) with the search open. The sample results come from
// data/search.ts; the status chips filter them here the way the app's items.search status param does.
import { computed, ref } from 'vue'
import MainWindow from '../../src/parts/MainWindow.vue'
import type { Item, MainTab, SearchHit } from '../../src/parts/types'
import type { SearchFilter } from '../../src/types'
import TrafficLights from './TrafficLights.vue'
import { projects } from '../data/projects'
import { nowCount, doneCount, nowItems } from '../data/items'
import { searchQuery, searchResults } from '../data/search'

const props = withDefaults(defineProps<{ width?: number; height?: number; query?: string; results?: SearchHit[]; loading?: boolean; error?: string }>(), {
  width: 960,
  height: 520,
  query: searchQuery,
  results: () => searchResults,
  loading: false,
})

const tab = ref<MainTab>('now')
const filter = ref('all')
const typed = ref(props.query)
const status = ref<SearchFilter>('all')

function statusOf(item: Item): Exclude<SearchFilter, 'all'> {
  if (item.state === 'working') return 'in_progress'
  if (item.state === 'done' || item.state === 'done-by-you') return 'done'
  return 'open'
}

const shown = computed(() => (status.value === 'all' ? props.results : props.results.filter((hit) => statusOf(hit.item) === status.value)))
</script>

<template>
  <div class="frame" :style="{ width: `${width}px`, height: `${height}px` }">
    <TrafficLights class="frame-lights" />
    <MainWindow
      v-model:tab="tab"
      v-model:filter="filter"
      v-model:search-query="typed"
      v-model:search-status="status"
      :width="width"
      :projects="projects"
      :items="nowItems"
      :now-count="nowCount"
      :done-count="doneCount"
      :search-open="true"
      :search-hits="shown"
      :search-loading="loading"
      :search-error="error"
    />
  </div>
</template>

<style scoped>
.frame {
  position: relative;
  flex: none;
  overflow: hidden;
  border: 1px solid var(--roo-border);
  border-radius: var(--roo-p-radius-card);
  background: var(--roo-surface);
}

.frame-lights {
  position: absolute;
  z-index: 5;
  inset-block-start: 16px;
  inset-inline-start: var(--roo-space-group);
}
</style>
