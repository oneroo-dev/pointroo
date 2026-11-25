<script setup lang="ts">
// The main window, drawn from the data it is given. The mockups pass sample data; the app passes the store. It fills its
// parent. macOS draws the real window buttons, so the bar only leaves the inset for them.
import { computed, nextTick, ref, watch } from 'vue'
import { RooButton, RooChipGroup, RooIconButton, RooInput, RooTooltip } from '@roo/kit/controls'
import {
  RooAppMark,
  RooBar,
  RooBarChip,
  RooEmpty,
  RooIcon,
  RooJumpField,
  RooKeyHint,
  RooLedge,
  RooLedgeFact,
  RooLiveDot,
  RooSkeleton,
  RooSplit,
  RooToast,
  RooWindow,
} from '@roo/kit'
import AppGlyph from './AppGlyph.vue'
import ItemDetail from './ItemDetail.vue'
import ItemList from './ItemList.vue'
import ProjectSidebar from './ProjectSidebar.vue'
import SearchView from './SearchView.vue'
import StatusBanner from './StatusBanner.vue'
import { orderProjects } from './projects'
import type { SearchFilter } from '../types'
import type { Item, MainBanner, MainTab, MainToast, Project, RecordingView, SearchHit } from './types'

const props = withDefaults(
  defineProps<{
    /** The width of the window, which picks the layout: sidebar from 720, detail pane from 900, a sheet below that. */
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
    /** Settings replace the list, the sidebar and the detail pane; they fill the `settings` slot. The gear shows as pressed. */
    settingsOpen?: boolean
    sessionsText?: string
    sessionsWarn?: boolean
    agentsText?: string | undefined
    speechText?: string | undefined
    needsYou?: boolean
    toast?: MainToast | undefined
    /** The whole recording of the selected item, once loaded (see store.loadRecording). */
    recording?: RecordingView | undefined
    /** The detail starts with its Recording section open (the mockups). */
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
    sessionsText: '',
    sessionsWarn: false,
    agentsText: undefined,
    speechText: undefined,
    needsYou: false,
    toast: undefined,
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

const sidebarWidth = ref(220)
const paneWidth = ref(380)

const isWide = computed(() => props.width >= 900)
const hasSidebar = computed(() => props.width >= 720)
// The results use the whole window, as in the search mockups: no sidebar and no detail pane while they show.
const showSidebar = computed(() => hasSidebar.value && !props.setup && !props.settingsOpen && !showSearch.value)
const showPane = computed(() => isWide.value && !props.setup && !props.settingsOpen && !showSearch.value)
const isEmptyList = computed(() => props.items.length === 0)
const listeningProjects = computed(() => props.projects.filter((project) => project.listening))
const filterChips = computed(() => [
  { id: 'all', label: 'All', tone: filter.value === 'all' ? ('accent' as const) : ('neutral' as const) },
  ...orderProjects(props.projects).map((project) => ({ id: project.id, label: project.name, tone: filter.value === project.id ? ('accent' as const) : ('neutral' as const) })),
])
const recordTip = computed(() => (props.recordDisabled ? 'Allow the microphone first' : 'Start recording ⌃⌃'))

// A press on the bar's empty background drags the window; a press on any control keeps its own job.
function onBarPress(event: MouseEvent): void {
  if (event.button !== 0) return
  if (event.target instanceof Element && event.target.closest('button, input, a, select, textarea, [role="button"], [tabindex]') !== null) return
  emit('drag')
}

function onSheetChange(open: boolean): void {
  if (!open) emit('closeDetail')
}
</script>

<template>
  <div class="window">
    <RooWindow
      v-model:sidebar-width="sidebarWidth"
      v-model:pane-width="paneWidth"
      :main-min="320"
      :parts="{ sidebar: { show: showSidebar }, pane: { show: showPane } }"
    >
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
            <RooJumpField v-if="!searchOpen" form="trigger" label="Search" keys="Mod+K" @open="emit('openSearch')" />
            <RooIconButton icon="settings" variant="ghost" label="Settings" tooltip="Settings" shortcut="Mod+," :pressed="settingsOpen" @click="emit('settings')" />
          </template>
        </RooBar>
      </template>

      <template v-if="showSidebar" #sidebar>
        <ProjectSidebar :projects="projects" :total="nowCount" :selected="filter" @select="(projectId) => (filter = projectId)" />
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

          <template v-else>
          <div v-if="!hasSidebar" class="main-filter">
            <RooChipGroup :chips="filterChips" />
          </div>

          <div v-if="isEmptyList" class="main-empty">
            <RooSkeleton v-if="loading" row :rows="5" />
            <RooEmpty v-else-if="emptyKind === 'all-done'" filtered title="All done. Nothing waiting." description="New recordings show up here." icon="check" />
            <RooEmpty v-else title="Nothing yet" description="Press Control twice, point, and talk." icon="mouse-pointer-click">
              <RooKeyHint keys="Control Control">Start</RooKeyHint>
            </RooEmpty>
          </div>

          <RooSplit v-else-if="!isWide" class="main-split" :sheet="true" :second-open="detailOpen && !!selectedItem" sheet-label="Recording" @update:sheet-open="onSheetChange">
            <template #first>
              <ItemList
                v-model:tab="tab"
                :items="items"
                :projects="projects"
                :now-count="nowCount"
                :done-count="doneCount"
                :selected-id="selectedItem?.id"
                :grouped="filter === 'all'"
                @select="(itemId) => emit('select', itemId)"
                @send="(itemId, projectId) => emit('send', itemId, projectId)"
                @send-all="(itemIds, projectId) => emit('sendAll', itemIds, projectId)"
                @done="(itemId) => emit('done', itemId)"
                @trash="(itemId) => emit('trash', itemId)"
                @reopen="(itemId) => emit('reopen', itemId)"
                @copy="(itemId) => emit('copy', itemId)"
                @reveal="(itemId) => emit('reveal', itemId)"
              />
            </template>
            <template #head>
              <RooButton variant="ghost" size="sm" @click="emit('closeDetail')">
                <template #icon><RooIcon name="arrow-left" :size="14" /></template>
                All recordings
              </RooButton>
            </template>
            <template #second>
              <ItemDetail
                v-if="selectedItem"
                :item="selectedItem"
                :projects="projects"
                @send="(itemId, projectId) => emit('send', itemId, projectId)"
                @move="(itemId, projectId) => emit('move', itemId, projectId)"
                @done="(itemId) => emit('done', itemId)"
                @trash="(itemId) => emit('trash', itemId)"
                @reopen="(itemId) => emit('reopen', itemId)"
                @copy="(itemId) => emit('copy', itemId)"
                :recording="recording"
                :recording-open="recordingOpen"
                @answer="(item, text) => emit('answer', item, text)"
                @later="(item) => emit('later', item)"
                @load-recording="(session) => emit('loadRecording', session)"
              />
            </template>
          </RooSplit>

          <ItemList
            v-else
            v-model:tab="tab"
            :items="items"
            :projects="projects"
            :now-count="nowCount"
            :done-count="doneCount"
            :selected-id="selectedItem?.id"
            :grouped="filter === 'all'"
            @select="(itemId) => emit('select', itemId)"
            @send="(itemId, projectId) => emit('send', itemId, projectId)"
            @send-all="(itemIds, projectId) => emit('sendAll', itemIds, projectId)"
            @done="(itemId) => emit('done', itemId)"
            @trash="(itemId) => emit('trash', itemId)"
            @reopen="(itemId) => emit('reopen', itemId)"
            @copy="(itemId) => emit('copy', itemId)"
            @reveal="(itemId) => emit('reveal', itemId)"
          />
          </template>
        </div>
      </template>

      <template v-if="showPane" #pane>
        <ItemDetail
          v-if="selectedItem"
          :item="selectedItem"
          :projects="projects"
          @send="(itemId, projectId) => emit('send', itemId, projectId)"
          @move="(itemId, projectId) => emit('move', itemId, projectId)"
          @done="(itemId) => emit('done', itemId)"
          @trash="(itemId) => emit('trash', itemId)"
          @reopen="(itemId) => emit('reopen', itemId)"
          @copy="(itemId) => emit('copy', itemId)"
          :recording="recording"
          :recording-open="recordingOpen"
          @answer="(item, text) => emit('answer', item, text)"
          @later="(item) => emit('later', item)"
          @load-recording="(session) => emit('loadRecording', session)"
        />
        <RooEmpty v-else title="Pick a recording" description="See what you said and pointed at." icon="mouse-pointer-click" />
      </template>

      <template #ledge>
        <RooLedge>
          <RooLedgeFact form="popover" label="Sessions" :value="sessionsText" v-bind="sessionsWarn ? { tone: 'warn' as const } : {}">
            <template #popover>
              <ul class="facts">
                <li v-for="project in listeningProjects" :key="project.id"><RooLiveDot state="live" :word="project.name" /><code>{{ project.folder }}</code></li>
              </ul>
            </template>
          </RooLedgeFact>
          <RooLedgeFact v-if="needsYou" label="Status" value="Needs you" tone="warn" />
          <RooLedgeFact v-if="agentsText" form="text" label="Agents" :value="agentsText" />
          <RooLedgeFact v-if="speechText" form="menu" label="Speech" :value="speechText" />
        </RooLedge>
      </template>
    </RooWindow>
    <RooToast
      v-if="toast"
      class="window-toast"
      :tone="toast.tone"
      :message="toast.message"
      :undo="toast.undo"
      @undo="emit('undo')"
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
  gap: var(--roo-space-item);
}

.search-field {
  width: 260px;
}

.main-filter {
  padding: var(--roo-space-group) var(--roo-space-group) 0;
}

.main-empty {
  display: flex;
  flex: 1 1 auto;
  align-items: center;
  justify-content: center;
  padding: var(--roo-space-group);
}

.main-split {
  min-height: 0;
  flex: 1 1 auto;
}

.facts {
  display: flex;
  flex-direction: column;
  gap: var(--roo-space-item);
  margin: 0;
  padding: 0;
  list-style: none;
}
</style>
