<script setup lang="ts">
// The main window, drawn from the data it is given. The mockups pass sample data; the app passes the store. It fills its
// parent. macOS draws the real window buttons, so the bar only leaves the inset for them.
// One bar (Record, Search, Settings), then the project chips, then the queue. From 900 px the open recording shows beside the
// queue; below that it is its own page with a way back. There is no sidebar, no Now / Done row and no footer: Done is one quiet
// button at the end of the chips.
import { computed, nextTick, ref, watch } from 'vue'
import { RooButton, RooChip, RooIconButton, RooInput, RooTooltip } from '@roo/kit/controls'
import { RooAppMark, RooBar, RooBarChip, RooEmpty, RooIcon, RooKbd, RooSkeleton, RooToast, RooWindow } from '@roo/kit'
import { RooMenu, RooMenuItem } from '@roo/kit/overlays'
import AppGlyph from './AppGlyph.vue'
import ItemDetail from './ItemDetail.vue'
import ItemList from './ItemList.vue'
import SearchView from './SearchView.vue'
import StatusBanner from './StatusBanner.vue'
import { orderProjects, visibleProjects } from './projects'
import type { SearchFilter } from '../types'
import type { Item, MainBanner, MainTab, MainToast, Project, RecordingView, SearchHit } from './types'

const props = withDefaults(
  defineProps<{
    /** The width of the window, which picks the layout: the recording beside the queue from 900, its own page below that. */
    width: number
    projects: Project[]
    items: Item[]
    selectedItem?: Item | undefined
    nowCount: number
    doneCount: number
    detailOpen?: boolean
    loading?: boolean
    /** What the empty list says: nothing recorded yet, or everything is done. */
    emptyKind?: 'nothing' | 'all-done'
    banner?: MainBanner | undefined
    recordState?: 'idle' | 'recording' | 'processing'
    recordDisabled?: boolean
    update?: 'ready' | 'updating' | undefined
    /** The first-run set up replaces the list; it fills the `setup` slot. */
    setup?: boolean
    /** Settings replace the chips and the list; they fill the `settings` slot. The gear shows as pressed. */
    settingsOpen?: boolean
    toast?: MainToast | undefined
    /** The ids of the recordings the app just sent: their rows are tinted and the first carries Undo. */
    freshIds?: string[]
    /** The whole recording of the selected item, once loaded (see store.loadRecording). */
    recording?: RecordingView | undefined
    /** The detail starts with its whole recording open (the mockups). */
    recordingOpen?: boolean
    /** The search box is open in the bar. With words in it, the results replace the queue. */
    searchOpen?: boolean
    searchHits?: SearchHit[]
    searchLoading?: boolean
    searchError?: string | undefined
  }>(),
  {
    selectedItem: undefined,
    detailOpen: true,
    loading: false,
    emptyKind: 'nothing',
    banner: undefined,
    recordState: 'idle',
    recordDisabled: false,
    update: undefined,
    setup: false,
    settingsOpen: false,
    toast: undefined,
    freshIds: () => [],
    recording: undefined,
    recordingOpen: false,
    searchOpen: false,
    searchHits: () => [],
    searchLoading: false,
    searchError: undefined,
  },
)

const emit = defineEmits<{
  record: []
  settings: []
  restart: []
  drag: []
  select: [itemId: string]
  closeDetail: []
  send: [itemId: string, projectId: string]
  sendAll: [itemIds: string[], projectId: string]
  move: [itemId: string, projectId: string]
  done: [itemId: string]
  trash: [itemId: string]
  reopen: [itemId: string]
  copy: [itemId: string]
  reveal: [itemId: string]
  answer: [item: Item, text: string]
  later: [item: Item]
  loadRecording: [session: string]
  allow: [which: NonNullable<MainBanner['which']>]
  useOtherPort: []
  details: []
  retry: []
  copyHint: []
  undo: []
  undoSent: []
  toastAction: []
  dismissToast: []
  openSearch: []
  closeSearch: []
  openResult: [itemId: string]
}>()

const tab = defineModel<MainTab>('tab', { default: 'now' })
const filter = defineModel<string>('filter', { default: 'all' })
const searchQuery = defineModel<string>('searchQuery', { default: '' })
const searchStatus = defineModel<SearchFilter>('searchStatus', { default: 'all' })

const searchField = ref<InstanceType<typeof RooInput> | null>(null)
const showSearch = computed(() => props.searchOpen && searchQuery.value.trim() !== '' && !props.setup && !props.settingsOpen)

// The box takes the keyboard as soon as it opens (Mod+K or the search button).
watch(
  () => props.searchOpen,
  async (open) => {
    if (!open) return
    await nextTick()
    searchField.value?.focus()
  },
  { immediate: true, flush: 'post' },
)

function onSearchEnter(): void {
  const first = props.searchHits[0]
  if (showSearch.value && first !== undefined) emit('openResult', first.item.id)
}

const isWide = computed(() => props.width >= 900)
// The results use the whole window, as in the search mockups: no recording beside them while they show.
const showPane = computed(() => isWide.value && !showSearch.value && props.items.length > 0)
// Below 900 px an open recording takes the whole column, with a way back to the queue.
const showDetailPage = computed(() => !isWide.value && !showSearch.value && props.detailOpen && props.selectedItem !== undefined && props.items.length > 0)
const isEmptyList = computed(() => props.items.length === 0)
const isDoneTab = computed(() => tab.value === 'done')
// How many project chips fit: two in a narrow window, four from 640 px, all of them from 900 px.
const chipLimit = computed(() => (isWide.value ? props.projects.length : props.width >= 640 ? 4 : 2))
const chips = computed(() => visibleProjects(orderProjects(props.projects), filter.value, chipLimit.value))
const recordTip = computed(() => (props.recordDisabled ? 'Allow the microphone first' : 'Start recording ⌃⌃'))

function chipTone(project: Project): 'accent' | 'ok' | 'neutral' {
  if (project.id === filter.value) return 'accent'
  return project.listening ? 'ok' : 'neutral'
}

function chipTip(project: Project): string {
  if (project.listening) return `Listening in ${project.folder}`
  if (project.sessionOpen === true) return `${project.folder}. A session is open but not listening.`
  return `${project.folder}. No agent is listening.`
}

// A new choice on the chips shows the queue again, also from an open recording on a narrow window.
function chooseFilter(projectId: string): void {
  filter.value = projectId
  if (!isWide.value) emit('closeDetail')
}

function toggleDone(): void {
  tab.value = isDoneTab.value ? 'now' : 'done'
  if (!isWide.value) emit('closeDetail')
}

// A press on the bar's empty background drags the window; a press on any control keeps its own job.
function onBarPress(event: MouseEvent): void {
  if (event.button !== 0) return
  if (event.target instanceof Element && event.target.closest('button, input, a, select, textarea, [role="button"], [tabindex]') !== null) return
  emit('drag')
}
</script>

<template>
  <div class="window">
    <RooWindow>
      <template #bar>
        <RooBar platform="mac" data-drag-region @mousedown="onBarPress">
          <template #leading><RooAppMark><AppGlyph /></RooAppMark></template>
          <template v-if="searchOpen" #jump>
            <RooInput
              ref="searchField"
              v-model="searchQuery"
              class="search-field"
              type="search"
              size="md"
              aria-label="Search recordings"
              placeholder="Search recordings"
              @keydown.enter="onSearchEnter"
            >
              <template #trailing>
                <RooIconButton icon="x" variant="ghost" size="xxs" label="Clear search" tooltip="Clear search" shortcut="Escape" @click="emit('closeSearch')" />
              </template>
            </RooInput>
          </template>
          <template #tools>
            <RooTooltip v-if="update === 'ready'" text="Pointroo has an update. Restarts in a second.">
              <RooBarChip interactive label="Restart to update" @click="emit('restart')">
                <template #leading><RooIcon name="update" :size="14" /></template>
              </RooBarChip>
            </RooTooltip>
            <RooBarChip v-if="update === 'updating'" interactive label="Restarting…">
              <template #leading><RooIcon name="loader" :size="14" /></template>
            </RooBarChip>
            <RooTooltip :text="recordTip">
              <RooButton variant="primary" size="sm" :disabled="recordDisabled" :busy="recordState !== 'idle'" disabled-reason="Allow the microphone first" @click="emit('record')">Record</RooButton>
            </RooTooltip>
            <RooIconButton v-if="!searchOpen" icon="search" variant="ghost" label="Search" tooltip="Search" shortcut="Mod+K" @click="emit('openSearch')" />
            <RooIconButton icon="settings" variant="ghost" label="Settings" tooltip="Settings" shortcut="Mod+," :pressed="settingsOpen" @click="emit('settings')" />
          </template>
        </RooBar>
      </template>

      <template #main>
        <slot v-if="setup" name="setup" />
        <slot v-else-if="settingsOpen" name="settings" />
        <div v-else class="main">
          <StatusBanner
            v-if="banner"
            :banner="banner"
            @allow="(which) => emit('allow', which)"
            @use-other-port="emit('useOtherPort')"
            @details="emit('details')"
            @retry="emit('retry')"
            @copy="emit('copyHint')"
          />

          <nav v-if="!showSearch" class="chips" aria-label="Projects">
            <RooChip shape="pill" :interactive="filter !== 'all'" :tone="filter === 'all' ? 'accent' : 'neutral'" @click="chooseFilter('all')">
              All<span v-if="nowCount > 0" class="chip-count">{{ nowCount }}</span>
            </RooChip>
            <RooTooltip v-for="project in chips.shown" :key="project.id" :text="chipTip(project)">
              <RooChip
                shape="pill"
                :interactive="project.id !== filter"
                :tone="chipTone(project)"
                :status-dot="project.id === filter && project.listening"
                @click="chooseFilter(project.id)"
              >
                {{ project.name }}<span v-if="project.count > 0" class="chip-count">{{ project.count }}</span>
              </RooChip>
            </RooTooltip>
            <RooMenu v-if="chips.hidden.length > 0" align="start">
              <template #trigger>
                <RooChip shape="pill" interactive tone="outline" :label="`+${chips.hidden.length}`" :aria-label="`${chips.hidden.length} more projects`" />
              </template>
              <RooMenuItem v-for="project in chips.hidden" :key="project.id" :hint="project.count > 0 ? String(project.count) : ''" @select="chooseFilter(project.id)">{{ project.name }}</RooMenuItem>
            </RooMenu>
            <span class="chips-spacer" />
            <RooButton :variant="isDoneTab ? 'secondary' : 'ghost'" size="sm" :aria-pressed="isDoneTab" @click="toggleDone">
              Done<span v-if="doneCount > 0" class="chip-count">{{ doneCount }}</span>
            </RooButton>
          </nav>

          <div class="body" :data-split="showPane ? 'true' : undefined">
            <div class="column">
              <SearchView
                v-if="showSearch"
                v-model:status="searchStatus"
                :query="searchQuery"
                :hits="searchHits"
                :loading="searchLoading"
                :error="searchError"
                @open="(itemId) => emit('openResult', itemId)"
                @clear="emit('closeSearch')"
              />

              <div v-else-if="isEmptyList" class="empty">
                <RooSkeleton v-if="loading" row :rows="5" />
                <RooEmpty v-else-if="isDoneTab" filtered title="Nothing done yet" description="Finished recordings show up here." icon="check" />
                <RooEmpty v-else-if="emptyKind === 'all-done'" filtered title="All done. Nothing waiting." description="New recordings show up here." icon="check" />
                <RooEmpty v-else title="Nothing waiting" description="Press Control twice, then point and talk." icon="mouse-pointer-click">
                  <RooKbd keys="Control Control" />
                </RooEmpty>
              </div>

              <ItemDetail
                v-else-if="showDetailPage && selectedItem"
                :key="selectedItem.id"
                :item="selectedItem"
                :projects="projects"
                :recording="recording"
                :recording-open="recordingOpen"
                back
                @back="emit('closeDetail')"
                @send="(itemId, projectId) => emit('send', itemId, projectId)"
                @move="(itemId, projectId) => emit('move', itemId, projectId)"
                @done="(itemId) => emit('done', itemId)"
                @trash="(itemId) => emit('trash', itemId)"
                @reopen="(itemId) => emit('reopen', itemId)"
                @copy="(itemId) => emit('copy', itemId)"
                @reveal="(itemId) => emit('reveal', itemId)"
                @answer="(item, text) => emit('answer', item, text)"
                @later="(item) => emit('later', item)"
                @load-recording="(session) => emit('loadRecording', session)"
              />

              <ItemList
                v-else
                :items="items"
                :projects="projects"
                :selected-id="selectedItem?.id"
                :fresh-ids="freshIds"
                @select="(itemId) => emit('select', itemId)"
                @send-all="(itemIds, projectId) => emit('sendAll', itemIds, projectId)"
                @send="(itemId, projectId) => emit('send', itemId, projectId)"
                @move="(itemId, projectId) => emit('move', itemId, projectId)"
                @undo-sent="emit('undoSent')"
              />
            </div>

            <aside v-if="showPane" class="column column-pane" aria-label="Recording">
              <ItemDetail
                v-if="selectedItem"
                :key="selectedItem.id"
                :item="selectedItem"
                :projects="projects"
                :recording="recording"
                :recording-open="recordingOpen"
                @send="(itemId, projectId) => emit('send', itemId, projectId)"
                @move="(itemId, projectId) => emit('move', itemId, projectId)"
                @done="(itemId) => emit('done', itemId)"
                @trash="(itemId) => emit('trash', itemId)"
                @reopen="(itemId) => emit('reopen', itemId)"
                @copy="(itemId) => emit('copy', itemId)"
                @reveal="(itemId) => emit('reveal', itemId)"
                @answer="(item, text) => emit('answer', item, text)"
                @later="(item) => emit('later', item)"
                @load-recording="(session) => emit('loadRecording', session)"
              />
              <div v-else class="empty">
                <RooEmpty title="Pick a recording" description="See what you said and pointed at." icon="mouse-pointer-click" />
              </div>
            </aside>
          </div>
        </div>
      </template>
    </RooWindow>
    <RooToast
      v-if="toast"
      class="window-toast"
      :tone="toast.tone"
      :message="toast.message"
      :undo="toast.undo"
      :action-label="toast.actionLabel ?? ''"
      @undo="emit('undo')"
      @action="emit('toastAction')"
      @dismiss="emit('dismissToast')"
    />
  </div>
</template>

<style scoped>
.window {
  position: relative;
  width: 100%;
  height: 100%;
  min-height: 0;
}

.window-toast {
  position: absolute;
  z-index: 5;
  inset-block-end: var(--roo-space-section);
  inset-inline-end: var(--roo-space-group);
}

.main {
  display: flex;
  height: 100%;
  min-height: 0;
  flex-direction: column;
}

.search-field {
  width: 260px;
}

.chips {
  display: flex;
  min-width: 0;
  flex: none;
  align-items: center;
  gap: var(--roo-space-item);
  overflow: hidden;
  padding: var(--roo-space-group) var(--roo-space-group) var(--roo-space-item);
}

.chip-count {
  margin-inline-start: var(--roo-p-space-1);
  opacity: 0.6;
  font-variant-numeric: tabular-nums;
}

.chips-spacer {
  flex: 1 1 auto;
}

.body {
  display: grid;
  min-height: 0;
  flex: 1 1 auto;
  grid-template-columns: minmax(0, 1fr);
  grid-template-rows: minmax(0, 1fr);
}

.body[data-split] {
  grid-template-columns: minmax(0, 4fr) minmax(0, 5fr);
}

.column {
  min-width: 0;
  min-height: 0;
  overflow-y: auto;
}

.column-pane {
  border-inline-start: 1px solid var(--roo-border);
}

.empty {
  display: flex;
  height: 100%;
  box-sizing: border-box;
  align-items: center;
  justify-content: center;
  padding: var(--roo-space-group);
}
</style>
