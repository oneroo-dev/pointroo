<script setup lang="ts">
// One click sends. The same row is used in the item detail, the queue list, the pill picker and the sidebar's quick keys.
import { computed } from 'vue'
import { RooButton } from '@roo/kit/controls'
import { RooChip, RooIcon, RooKbd, RooLetterTile, RooLiveDot, RooSwitcher } from '@roo/kit'
import type { ProjectTile } from '../data/types'

const props = withDefaults(
  defineProps<{
    size: 'small' | 'large'
    tiles: ProjectTile[]
    selectedId?: string
    showKeys?: boolean
    showMore?: boolean
    moreRows?: ProjectTile[]
    label?: string
  }>(),
  { selectedId: undefined, showKeys: false, showMore: false, moreRows: () => [], label: 'Send to' },
)

const large = computed(() => props.size === 'large')
const hasChoice = computed(() => props.selectedId !== undefined)
const switcherRows = computed(() => props.moreRows.map((tile) => ({ id: tile.id, name: tile.name, meta: tile.live ? 'listening' : '' })))
</script>

<template>
  <div class="tiles" role="group" :aria-label="label">
    <RooButton
      v-for="(tile, index) in tiles"
      :key="tile.id"
      :variant="tile.id === selectedId ? 'primary' : 'secondary'"
      :size="large ? 'lg' : 'sm'"
      :aria-pressed="tile.id === selectedId"
    >
      <span class="tile">
        <RooLetterTile :name="tile.name" :size="large ? 22 : 18" />
        <span class="tile-name">{{ tile.name }}</span>
        <RooChip v-if="large && tile.suggested && !hasChoice" size="small" tone="accent" label="Suggested" />
        <RooLiveDot v-if="large && tile.live" state="live" word="Live" />
        <RooKbd v-if="showKeys" :keys="String(index + 1)" />
      </span>
    </RooButton>
    <RooSwitcher v-if="showMore && moreRows.length > 0" :rows="switcherRows" label="More projects" search search-placeholder="Type to filter" grouping="none" hints>
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
.tiles {
  display: flex;
  flex-wrap: wrap;
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
