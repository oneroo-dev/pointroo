<script setup lang="ts">
// One click sends. `row` is a single line of small buttons (queue row chips). `list` is one clickable row per project, for
// the narrow detail pane and the pill picker: at most four rows, then a More row that opens a RooSwitcher.
// A click raises `pick` with the project id; the screen that holds the tiles decides what a pick does.
import { computed } from 'vue'
import { RooButton } from '@roo/kit/controls'
import { RooChip, RooIcon, RooKbd, RooLetterTile, RooListRow, RooLiveDot, RooSwitcher } from '@roo/kit'
import type { RooSwitcherRow } from '@roo/kit'
import type { ProjectTile } from './types'

const listLimit = 4

const props = withDefaults(
  defineProps<{
    size: 'small' | 'large'
    layout?: 'row' | 'list'
    tiles: ProjectTile[]
    selectedId?: string | undefined
    showKeys?: boolean
    showMore?: boolean
    moreRows?: ProjectTile[]
    label?: string
  }>(),
  { layout: 'row', selectedId: undefined, showKeys: false, showMore: false, moreRows: () => [], label: 'Send to' },
)

const emit = defineEmits<{ pick: [projectId: string] }>()

const large = computed(() => props.size === 'large')
const isList = computed(() => props.layout === 'list')
const hasChoice = computed(() => props.selectedId !== undefined)
const shownTiles = computed(() => (isList.value ? props.tiles.slice(0, listLimit) : props.tiles))
const hiddenTiles = computed(() => [...(isList.value ? props.tiles.slice(listLimit) : []), ...props.moreRows])
const switcherRows = computed<RooSwitcherRow[]>(() => hiddenTiles.value.map((tile) => ({ id: tile.id, name: tile.name, meta: tile.live ? 'listening' : '' })))

function pickFromSwitcher(row: RooSwitcherRow): void {
  emit('pick', row.id)
}
</script>

<template>
  <div v-if="isList" class="rows" role="listbox" :aria-label="label">
    <RooListRow
      v-for="(tile, index) in shownTiles"
      :key="tile.id"
      size="dense"
      role="option"
      tabindex="0"
      :selected="tile.id === selectedId"
      :aria-selected="tile.id === selectedId"
      :title="tile.name"
      @click="emit('pick', tile.id)"
      @keydown.enter.prevent="emit('pick', tile.id)"
    >
      <template #tile><RooLetterTile :name="tile.name" :size="22" /></template>
      <template v-if="(tile.suggested && !hasChoice) || tile.live" #title-trailing>
        <span class="row-marks">
          <RooChip v-if="tile.suggested && !hasChoice" size="small" tone="accent" label="Suggested" />
          <RooLiveDot v-if="tile.live" state="live" word="Live" />
        </span>
      </template>
      <template v-if="showKeys" #trailing><RooKbd :keys="String(index + 1)" /></template>
    </RooListRow>
    <RooSwitcher v-if="showMore && hiddenTiles.length > 0" :rows="switcherRows" label="More projects" search search-placeholder="Type to filter" grouping="none" hints @select="pickFromSwitcher">
      <template #trigger="{ attrs }">
        <RooListRow v-bind="attrs" size="dense" role="option" tabindex="0" title="More">
          <template #tile><RooIcon name="search" :size="16" /></template>
        </RooListRow>
      </template>
    </RooSwitcher>
  </div>

  <div v-else class="tiles" role="group" :aria-label="label">
    <RooButton
      v-for="(tile, index) in tiles"
      :key="tile.id"
      :variant="tile.id === selectedId ? 'primary' : 'secondary'"
      :size="large ? 'lg' : 'sm'"
      :aria-pressed="tile.id === selectedId"
      @click="emit('pick', tile.id)"
    >
      <span class="tile">
        <RooLetterTile :name="tile.name" :size="large ? 22 : 18" />
        <span class="tile-name">{{ tile.name }}</span>
        <RooChip v-if="large && tile.suggested && !hasChoice" size="small" tone="accent" label="Suggested" />
        <RooLiveDot v-if="large && tile.live" state="live" word="Live" />
        <RooKbd v-if="showKeys" :keys="String(index + 1)" />
      </span>
    </RooButton>
    <RooSwitcher v-if="showMore && moreRows.length > 0" :rows="switcherRows" label="More projects" search search-placeholder="Type to filter" grouping="none" hints @select="pickFromSwitcher">
      <template #trigger="{ attrs }">
        <RooButton v-bind="attrs" variant="secondary" :size="large ? 'lg' : 'sm'">
          <span class="tile">
            <RooIcon name="search" :size="14" />
            <span class="tile-name">More</span>
          </span>
        </RooButton>
      </template>
    </RooSwitcher>
  </div>
</template>

<style scoped>
.rows {
  display: flex;
  flex-direction: column;
  gap: var(--roo-space-item);
}

.row-marks {
  display: inline-flex;
  align-items: center;
  gap: var(--roo-space-item);
}

.tiles {
  display: flex;
  flex-wrap: nowrap;
  align-items: center;
  gap: var(--roo-space-item);
}

.tile {
  display: inline-flex;
  align-items: center;
  gap: var(--roo-space-item);
}

.tile-name {
  white-space: nowrap;
}
</style>
