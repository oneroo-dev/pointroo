<script setup lang="ts">
// The real main window: the shared MainWindow part, fed by the store. The native window draws the traffic lights.
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { RooTooltipProvider } from '@roo/kit/controls'
import { bridge } from './bridge'
import MainWindow from './parts/MainWindow.vue'
import { projectIdFor, tilesFor } from './parts/projects'
import SettingsScreen from './parts/SettingsScreen.vue'
import type { Item } from './parts/types'
import { createStore } from './store'

const store = createStore(bridge)
const width = ref(window.innerWidth)

const isNarrow = computed(() => width.value < 900)
// The project picker is open: the bar still shows the busy Record button.
const recordState = computed(() => (store.recording.phase === 'picking' ? 'processing' : store.recording.phase))
const recordDisabled = computed(() => store.status !== undefined && !store.status.microphone)

function onResize(): void {
  width.value = window.innerWidth
}

// A press on the bar's empty background drags the window. The app may not have the method yet; that is fine.
function startDrag(): void {
  bridge.call('window.startDrag', {}).catch(() => undefined)
}

function onRecord(): void {
  store.showToast('Press Control twice to record.', 'muted', false)
}

// The gear and Cmd+, open Settings; pressed again they close it.
function onSettings(): void {
  if (store.view === 'settings') {
    store.closeSettings()
    return
  }
  store.closeSearch()
  void store.openSettings()
}

function onReveal(): void {
  store.showToast('Show in Finder is not available yet.', 'muted', false)
}

function onUseOtherPort(): void {
  void store.useAnotherPort()
}

function onCopyHint(): void {
  void store.copyText('work through Pointroo')
}

function onSendAll(itemIds: string[], projectId: string): void {
  void store.send(itemIds, projectId)
}

function onAnswer(item: Item, text: string): void {
  void store.answer(item.question, text)
}

function onLater(item: Item): void {
  void store.later(item.question)
}

const selectedRecording = computed(() => {
  const session = store.selectedItem?.session
  return session === undefined ? undefined : store.recordings[session]
})

// The tiles a number key picks: the same order the detail shows them in.
function tilesForSelected(item: Item) {
  const guess = item.state === 'not-sent' ? item.suggested : projectIdFor(store.projects, item.project)
  return tilesFor(store.projects, guess).tiles
}

function typingInField(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false
  return target.isContentEditable || ['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName)
}

// Mod+K opens the search box in the bar (or puts the cursor back in it). Esc closes it, also while the cursor is in it.
function onSearchKey(event: KeyboardEvent): boolean {
  if (event.metaKey && !event.ctrlKey && !event.altKey && event.key.toLowerCase() === 'k') {
    event.preventDefault()
    if (store.view === 'settings') store.closeSettings()
    if (store.searchOpen) document.querySelector<HTMLInputElement>('input[type="search"]')?.focus()
    else store.openSearch()
    return true
  }
  if (store.searchOpen && store.view === 'queue' && event.key === 'Escape' && !event.metaKey && !event.ctrlKey && !event.altKey) {
    event.preventDefault()
    store.closeSearch()
    return true
  }
  return false
}

function onKey(event: KeyboardEvent): void {
  if (event.defaultPrevented || event.isComposing) return
  if (onSearchKey(event)) return
  if (typingInField(event.target)) return
  if (event.metaKey && !event.ctrlKey && !event.altKey && /^[1-9]$/.test(event.key)) {
    event.preventDefault()
    store.selectProjectNumber(Number(event.key))
    return
  }
  if (event.metaKey && event.key === ',') {
    event.preventDefault()
    onSettings()
    return
  }
  if (event.metaKey || event.ctrlKey || event.altKey) return

  if (store.view === 'settings') {
    if (event.key === 'Escape') {
      event.preventDefault()
      store.closeSettings()
    }
    return
  }

  if (event.key === 'Escape') {
    if (isNarrow.value && store.selectedItem !== undefined) {
      event.preventDefault()
      store.select(undefined)
    }
    return
  }

  if (event.key === 'Enter') {
    if (event.target instanceof HTMLElement && event.target.closest('button, a, [role="option"]') !== null) return
    const first = store.rows[0]
    if (store.selectedItem === undefined && first !== undefined) {
      event.preventDefault()
      store.select(first.id)
    }
    return
  }

  const item = store.selectedItem
  if (item === undefined) return
  const finished = item.state === 'done' || item.state === 'done-by-you'

  if (/^[1-5]$/.test(event.key) && !finished) {
    const tile = tilesForSelected(item)[Number(event.key) - 1]
    if (tile === undefined) return
    event.preventDefault()
    void store.send([item.id], tile.id)
  } else if (event.key.toLowerCase() === 'l' && item.state === 'asks') {
    event.preventDefault()
    onLater(item)
  } else if (event.key.toLowerCase() === 'd' && !finished) {
    event.preventDefault()
    void store.done(item.id)
  } else if (event.key === 'Delete' || event.key === 'Backspace') {
    event.preventDefault()
    void store.trash(item.id)
  }
}

let stopEvents: (() => void) | undefined

onMounted(() => {
  window.addEventListener('resize', onResize)
  window.addEventListener('keydown', onKey)
  stopEvents = store.start()
})

onBeforeUnmount(() => {
  window.removeEventListener('resize', onResize)
  window.removeEventListener('keydown', onKey)
  stopEvents?.()
})
</script>

<template>
  <RooTooltipProvider>
    <MainWindow
      v-model:tab="store.tab"
      v-model:filter="store.filter"
      :search-query="store.searchState.query"
      :search-status="store.searchState.status"
      :search-open="store.searchOpen"
      :search-hits="store.searchHits"
      :search-loading="store.searchState.loading"
      :search-error="store.searchState.error"
      :width="width"
      :projects="store.projects"
      :items="store.rows"
      :selected-item="store.selectedItem"
      :now-count="store.nowCount"
      :done-count="store.doneCount"
      :loading="store.loading"
      :empty-kind="store.emptyKind"
      :banner="store.banner"
      :record-state="recordState"
      :record-disabled="recordDisabled"
      :sessions-text="store.sessionsText"
      :sessions-warn="store.sessionsText === 'None listening'"
      :agents-text="store.agentsText"
      :needs-you="store.banner !== undefined && store.banner.kind !== 'no-session'"
      :settings-open="store.view === 'settings'"
      :toast="store.toast"
      :recording="selectedRecording"
      @update:search-query="(text) => void store.search(text)"
      @update:search-status="(status) => void store.setSearchStatus(status)"
      @open-search="store.openSearch"
      @close-search="store.closeSearch"
      @open-result="store.openSearchResult"
      @drag="startDrag"
      @record="onRecord"
      @settings="onSettings"
      @select="store.select"
      @close-detail="store.select(undefined)"
      @send="(itemId, projectId) => store.send([itemId], projectId)"
      @send-all="onSendAll"
      @move="(itemId, projectId) => store.send([itemId], projectId)"
      @done="store.done"
      @trash="store.trash"
      @reopen="store.reopen"
      @copy="store.copyFor"
      @reveal="onReveal"
      @answer="onAnswer"
      @later="onLater"
      @load-recording="store.loadRecording"
      @allow="store.allow"
      @use-other-port="onUseOtherPort"
      @details="store.refresh"
      @retry="store.refresh"
      @copy-hint="onCopyHint"
      @undo="store.undo"
      @dismiss-toast="store.dismissToast"
    >
      <template #settings>
        <SettingsScreen
          :values="store.settings"
          :loading="!store.settingsLoaded"
          :stopping="store.stoppingRuns"
          v-bind="
            store.status === undefined
              ? {}
              : { permissions: store.status, autoRuns: store.status.autoRuns, lastAutoRun: store.status.lastAutoRun }
          "
          @change="store.setSetting"
          @stop-run="store.stopAutoRun"
          @allow="store.allow"
          @use-another-port="store.useAnotherPort"
          @check-updates="store.checkUpdates"
          @back="store.closeSettings"
        />
      </template>
    </MainWindow>
  </RooTooltipProvider>
</template>
