<script setup lang="ts">
// The main window with the search box open in the bar. The status chips are a segmented control (the status param of
// items.search: open, in progress, done, any). The results fill the main area; with none there is one line and Clear search.
import { computed, ref } from 'vue'
import { RooButton, RooIconButton, RooInput, RooTooltip } from '@roo/kit/controls'
import { RooAppMark, RooBar, RooEmpty, RooKbd, RooSegmented, RooWindow } from '@roo/kit'
import AppGlyph from '../../src/parts/AppGlyph.vue'
import SearchResults from './SearchResults.vue'
import TrafficLights from './TrafficLights.vue'
import { searchResults } from '../data/search'
import type { SearchResult } from '../data/search'

const props = withDefaults(defineProps<{ width: number; height?: number; query: string; results?: SearchResult[] }>(), { height: 520, results: () => searchResults })

type StatusFilter = 'open' | 'in_progress' | 'done' | 'any'

const typed = ref(props.query)
const status = ref<StatusFilter>('any')

function statusOf(result: SearchResult): Exclude<StatusFilter, 'any'> {
  const state = result.item.state
  if (state === 'working') return 'in_progress'
  if (state === 'done' || state === 'done-by-you') return 'done'
  return 'open'
}

function countFor(filter: StatusFilter): number {
  return filter === 'any' ? props.results.length : props.results.filter((result) => statusOf(result) === filter).length
}

const options = computed(() => [
  { value: 'open', label: 'Open', count: countFor('open') },
  { value: 'in_progress', label: 'In progress', count: countFor('in_progress') },
  { value: 'done', label: 'Done', count: countFor('done') },
  { value: 'any', label: 'All', count: countFor('any') },
])

const shown = computed(() => (status.value === 'any' ? props.results : props.results.filter((result) => statusOf(result) === status.value)))
const countText = computed(() => `${shown.value.length} ${shown.value.length === 1 ? 'result' : 'results'}`)
</script>

<template>
  <div class="frame" :style="{ width: `${width}px`, height: `${height}px` }">
    <TrafficLights class="frame-lights" />
    <RooWindow :main-min="320" :parts="{ sidebar: { show: false }, pane: { show: false } }">
      <template #bar>
        <RooBar platform="mac">
          <template #leading><RooAppMark><AppGlyph /></RooAppMark></template>
          <template #jump>
            <RooInput v-model="typed" class="search-field" type="search" size="md" aria-label="Search recordings" placeholder="Search recordings">
              <template #trailing>
                <RooIconButton icon="x" variant="ghost" size="xxs" label="Clear search" tooltip="Clear search" shortcut="Escape" />
              </template>
            </RooInput>
          </template>
          <template #tools>
            <RooTooltip text="Start recording ⌃⌃"><RooButton variant="primary" size="sm">Record</RooButton></RooTooltip>
            <RooIconButton icon="settings" variant="ghost" label="Settings" tooltip="Settings" shortcut="Mod+," />
          </template>
        </RooBar>
      </template>

      <template #main>
        <div class="search-main">
          <div class="search-filters">
            <RooSegmented v-model="status" label="Show" size="md" :options="options" />
            <span class="search-count">{{ countText }}</span>
          </div>
          <SearchResults v-if="shown.length > 0" :results="shown" :query="typed" />
          <div v-else class="search-empty">
            <RooEmpty filtered :title="`No items match &quot;${typed}&quot;`">
              <RooButton variant="secondary" size="sm">
                <span class="clear-label"><span>Clear search</span><RooKbd keys="Esc" /></span>
              </RooButton>
            </RooEmpty>
          </div>
        </div>
      </template>
    </RooWindow>
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

.search-field {
  width: 260px;
}

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
