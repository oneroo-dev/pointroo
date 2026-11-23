<script setup lang="ts">
import { computed, ref } from 'vue'
import { RooButton, RooChipGroup, RooIconButton, RooTooltip } from '@roo/kit/controls'
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
  RooStateCard,
  RooToast,
  RooWindow,
} from '@roo/kit'
import AppGlyph from './AppGlyph.vue'
import ItemDetail from './ItemDetail.vue'
import ItemList from './ItemList.vue'
import ProjectSidebar from './ProjectSidebar.vue'
import SetupView from './SetupView.vue'
import TrafficLights from './TrafficLights.vue'
import { orderedProjects, projects } from '../data/projects'
import { asks, doneCount, doneItems, justSent, nowCount, nowItems, notSent, processing, working } from '../data/items'
import type { Item } from '../data/types'

export type Scenario =
  | 'queue'
  | 'asks'
  | 'done'
  | 'not-sent'
  | 'just-sent'
  | 'processing'
  | 'none-selected'
  | 'empty'
  | 'now-empty'
  | 'loading'
  | 'permission'
  | 'port-busy'
  | 'mcp-error'
  | 'no-session'
  | 'update'
  | 'updating'
  | 'setup'
  | 'setup-done'

const props = withDefaults(defineProps<{ width?: number; height?: number; scenario?: Scenario; detailOpen?: boolean }>(), {
  width: 960,
  height: 620,
  scenario: 'queue',
  detailOpen: true,
})

const sidebarWidth = ref(220)
const paneWidth = ref(380)
const tab = ref<'now' | 'done'>(props.scenario === 'done' || props.scenario === 'now-empty' ? 'done' : 'now')

const isWide = computed(() => props.width >= 900)
const hasSidebar = computed(() => props.width >= 720)
const isSetup = computed(() => props.scenario === 'setup' || props.scenario === 'setup-done')
const isEmptyList = computed(() => props.scenario === 'empty' || props.scenario === 'now-empty' || props.scenario === 'loading')

const rows = computed<Item[]>(() => {
  switch (props.scenario) {
    case 'done':
      return doneItems
    case 'processing':
      return [processing, ...nowItems]
    case 'not-sent':
      return [notSent, ...nowItems]
    case 'just-sent':
      return [justSent, ...nowItems]
    case 'empty':
    case 'now-empty':
    case 'loading':
      return []
    default:
      return nowItems
  }
})

const selectedItem = computed<Item | undefined>(() => {
  switch (props.scenario) {
    case 'asks':
      return asks
    case 'done':
      return doneItems[0]
    case 'not-sent':
      return notSent
    case 'just-sent':
      return justSent
    case 'none-selected':
    case 'processing':
      return undefined
    case 'queue':
    case 'permission':
    case 'port-busy':
    case 'mcp-error':
    case 'no-session':
    case 'update':
    case 'updating':
      return working
    default:
      return undefined
  }
})

const problem = computed(() => ['permission', 'port-busy', 'mcp-error'].includes(props.scenario))
const projectChoice = ref('all')
// Narrow window: one chip row, All first, then projects that listen, then the most recent. The chosen chip is the accent one.
const filterChips = computed(() => [
  { id: 'all', label: 'All', tone: projectChoice.value === 'all' ? ('accent' as const) : ('neutral' as const) },
  ...orderedProjects.map((project) => ({ id: project.id, label: project.name, tone: projectChoice.value === project.id ? ('accent' as const) : ('neutral' as const) })),
])
const setupStep = computed(() => (props.scenario === 'setup-done' ? 'done' : 'accessibility'))
</script>

<template>
  <div class="frame" :style="{ width: `${width}px`, height: `${height}px` }">
    <TrafficLights class="frame-lights" />
    <RooWindow
      v-model:sidebar-width="sidebarWidth"
      v-model:pane-width="paneWidth"
      :main-min="320"
      :parts="{ sidebar: { show: hasSidebar && !isSetup }, pane: { show: isWide && !isSetup } }"
    >
      <template #bar>
        <RooBar platform="mac">
          <template #leading><RooAppMark><AppGlyph /></RooAppMark></template>
          <template #tools>
            <RooTooltip v-if="scenario === 'update'" text="Pointroo 1.4 is ready. Restarts in a second.">
              <RooBarChip interactive label="Restart to update">
                <template #leading><RooIcon name="update" :size="14" /></template>
              </RooBarChip>
            </RooTooltip>
            <RooBarChip v-if="scenario === 'updating'" interactive label="Restarting…">
              <template #leading><RooIcon name="loader" :size="14" /></template>
            </RooBarChip>
            <RooTooltip :text="scenario === 'permission' ? 'Allow the microphone first' : 'Start recording ⌃⌃'">
              <RooButton variant="primary" size="sm" :disabled="scenario === 'permission'" :busy="scenario === 'processing'" disabled-reason="Allow the microphone first">Record</RooButton>
            </RooTooltip>
            <RooJumpField form="trigger" label="Search" keys="Mod+K" />
            <RooIconButton icon="settings" variant="ghost" label="Settings" tooltip="Settings" shortcut="Mod+," />
          </template>
        </RooBar>
      </template>

      <template v-if="hasSidebar && !isSetup" #sidebar>
        <ProjectSidebar :projects="projects" :total="nowCount" selected="all" />
      </template>

      <template #main>
        <SetupView v-if="isSetup" :step="setupStep" />
        <div v-else class="main">
          <RooStateCard
            v-if="scenario === 'permission'"
            layout="band"
            kind="warn"
            title="Pointroo can't hear you"
            description="Microphone is off: no speech recorded."
          >
            <template #actions><RooButton size="sm" variant="secondary">Allow</RooButton></template>
          </RooStateCard>
          <RooStateCard
            v-if="scenario === 'port-busy'"
            layout="band"
            kind="error"
            title="Agents can't reach Pointroo"
            description="Port 6742 is used by another app."
          >
            <template #actions>
              <RooButton size="sm" variant="primary">Use another port</RooButton>
              <RooButton size="sm" variant="ghost">Details</RooButton>
            </template>
          </RooStateCard>
          <RooStateCard
            v-if="scenario === 'mcp-error'"
            layout="band"
            kind="error"
            title="Agents can't reach Pointroo"
            description="The server could not start (error 13)."
          >
            <template #actions><RooButton size="sm" variant="primary">Try again</RooButton></template>
          </RooStateCard>
          <RooStateCard
            v-if="scenario === 'no-session'"
            layout="strip"
            kind="info"
            title="No Claude session is listening"
            description="Say 'work through Pointroo' in Claude Code."
          >
            <template #actions><RooButton size="sm" variant="secondary">Copy</RooButton></template>
          </RooStateCard>

          <div v-if="!hasSidebar" class="main-filter">
            <RooChipGroup :chips="filterChips" />
          </div>

          <div v-if="isEmptyList" class="main-empty">
            <RooSkeleton v-if="scenario === 'loading'" row :rows="5" />
            <RooEmpty v-else-if="scenario === 'now-empty'" filtered title="All done. Nothing waiting." description="New recordings show up here." icon="check" />
            <RooEmpty v-else title="Nothing yet" description="Press Control twice, point, and talk." icon="mouse-pointer-click">
              <RooKeyHint keys="Control Control">Start</RooKeyHint>
            </RooEmpty>
          </div>

          <RooSplit v-else-if="!isWide" class="main-split" :sheet="true" :second-open="detailOpen && !!selectedItem" sheet-label="Recording">
            <template #first>
              <ItemList v-model:tab="tab" :items="rows" :tab="tab" :now-count="nowCount" :done-count="doneCount" :selected-id="selectedItem?.id" :grouped="projectChoice === 'all'" />
            </template>
            <template #second>
              <ItemDetail v-if="selectedItem" :item="selectedItem" />
            </template>
          </RooSplit>

          <ItemList v-else v-model:tab="tab" :items="rows" :tab="tab" :now-count="nowCount" :done-count="doneCount" :selected-id="selectedItem?.id" grouped />
        </div>
      </template>

      <template v-if="isWide && !isSetup" #pane>
        <ItemDetail v-if="selectedItem" :item="selectedItem" />
        <RooEmpty v-else title="Pick a recording" description="See what you said and pointed at." icon="mouse-pointer-click" />
      </template>

      <template #ledge>
        <RooLedge>
          <RooLedgeFact form="popover" label="Sessions" :value="scenario === 'no-session' ? 'None listening' : '2 listening'" :tone="scenario === 'no-session' ? 'warn' : undefined">
            <template #popover>
              <ul class="facts">
                <li v-for="project in projects.filter((entry) => entry.listening)" :key="project.id"><RooLiveDot state="live" :word="project.name" /><code>{{ project.folder }}</code></li>
              </ul>
            </template>
          </RooLedgeFact>
          <RooLedgeFact v-if="problem" label="Status" value="Needs you" tone="warn" />
          <RooLedgeFact form="text" label="Agents" value="Claude Code, Codex" />
          <RooLedgeFact form="menu" label="Speech" value="English" />
        </RooLedge>
      </template>
    </RooWindow>
    <RooToast v-if="scenario === 'just-sent'" class="frame-toast" tone="ok" message="Sent to Tinkeroo" undo />
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

.frame-toast {
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
