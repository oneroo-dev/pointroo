<script setup lang="ts">
// A floating panel (the kit pill, picker or notice card): one small page the app opens in a borderless panel. It uses the same
// store and bridge as the main window, and tells the app how tall it is so the panel fits (0 hides it).
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { RooTooltipProvider } from '@roo/kit/controls'
import { bridge } from './bridge'
import { postFloatMessage } from './floatChannel'
import { currentNotice, pickerEndsAt, pickerTiles, pillView, sizeToReport } from './floatModel'
import type { FloatRoute } from './floatRoute'
import FloatNotice from './parts/FloatNotice.vue'
import FloatPicker from './parts/FloatPicker.vue'
import FloatPill from './parts/FloatPill.vue'
import { createStore } from './store'
import type { Notice, QuestionNotice } from './types'

const props = defineProps<{ route: FloatRoute }>()

const store = createStore(bridge)
const root = ref<HTMLElement | null>(null)
const nowMilliseconds = ref(Date.now())
const lastPoints = ref(0)
const endsAt = ref<number | undefined>(undefined)

const pill = computed(() => pillView(store.recording, nowMilliseconds.value, lastPoints.value))
const tiles = computed(() => (store.picker === null ? [] : pickerTiles(store.picker)))
const notice = computed(() => currentNotice(store.notices))

const hasContent = computed(() => {
  if (props.route === 'pill') return pill.value !== undefined
  if (props.route === 'picker') return store.picker !== null
  return notice.value !== undefined
})

watch(
  () => store.recording.pointCount,
  (count) => {
    if (store.recording.phase === 'recording') lastPoints.value = count
  },
  { immediate: true },
)

watch(
  () => store.picker,
  (picker) => {
    endsAt.value = picker === null ? undefined : pickerEndsAt(picker, Date.now())
  },
  { immediate: true },
)

function reportSize(): void {
  const box = root.value?.getBoundingClientRect()
  postFloatMessage({ kind: 'size', ...sizeToReport(box?.width ?? 0, box?.height ?? 0, hasContent.value) })
}

function onPick(path: string): void {
  void store.pickProject(path)
}

function onSkip(): void {
  void store.skipPicker()
}

function onOpen(itemId: string): void {
  postFloatMessage({ kind: 'open', itemId })
  void store.markNoticesSeen([itemId])
}

async function onSayMore(itemId: string): Promise<void> {
  await store.sayMore(itemId)
  await store.markNoticesSeen([itemId])
}

function onDismiss(shown: Notice): void {
  if (shown.kind === 'done') void store.markNoticesSeen([shown.id])
}

function dismissShown(): void {
  const shown = notice.value
  if (shown !== undefined) onDismiss(shown)
}

async function onAnswer(shown: QuestionNotice, text: string): Promise<void> {
  await store.answer(shown, text)
  await store.loadNotices().catch(() => undefined)
}

async function onLater(shown: QuestionNotice): Promise<void> {
  await store.later(shown)
  await store.loadNotices().catch(() => undefined)
}

function answerShown(text: string): void {
  const shown = notice.value
  if (shown?.kind === 'question') void onAnswer(shown, text)
}

function laterShown(): void {
  const shown = notice.value
  if (shown?.kind === 'question') void onLater(shown)
}

function typingInField(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false
  return target.isContentEditable || ['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName)
}

// The card's keys work while the card has the key focus (the app's panel does not take focus on its own).
function onKey(event: KeyboardEvent): void {
  if (props.route !== 'notice' || event.defaultPrevented || event.isComposing || event.metaKey || event.ctrlKey || event.altKey) return
  if (typingInField(event.target)) return
  const shown = notice.value
  if (shown === undefined) return
  const key = event.key.toLowerCase()
  if (shown.kind === 'done') {
    if (key === 'enter') onOpen(shown.id)
    else if (key === 'r') void onSayMore(shown.id)
    else if (key === 'escape') onDismiss(shown)
    else return
    event.preventDefault()
    return
  }
  const choice = /^[1-3]$/.test(key) ? shown.choices[Number(key) - 1] : undefined
  if (choice !== undefined) void onAnswer(shown, choice)
  else if (key === 'l') void onLater(shown)
  else return
  event.preventDefault()
}

let stopEvents: (() => void) | undefined
let clock: ReturnType<typeof setInterval> | undefined
let observer: ResizeObserver | undefined

watch(hasContent, () => reportSize(), { flush: 'post' })

onMounted(() => {
  stopEvents = store.startFloating()
  window.addEventListener('keydown', onKey)
  clock = setInterval(() => {
    nowMilliseconds.value = Date.now()
  }, 1000)
  if (root.value !== null) {
    observer = new ResizeObserver(() => reportSize())
    observer.observe(root.value)
  }
  reportSize()
})

onBeforeUnmount(() => {
  stopEvents?.()
  window.removeEventListener('keydown', onKey)
  clearInterval(clock)
  observer?.disconnect()
})
</script>

<template>
  <RooTooltipProvider>
    <div ref="root" class="float-root">
      <template v-if="route === 'pill'">
        <FloatPill v-if="pill !== undefined" :phase="pill.phase" :elapsed="pill.elapsed" :points="pill.points" @stop="store.stopRecording" @cancel="store.cancelRecording" />
      </template>
      <template v-else-if="route === 'picker'">
        <FloatPicker v-if="store.picker !== null" :tiles="tiles" :ends-at="endsAt" @pick="onPick" @skip="onSkip" />
      </template>
      <template v-else>
        <FloatNotice
          v-if="notice !== undefined"
          :notice="notice"
          @open="onOpen"
          @say-more="onSayMore"
          @dismiss="dismissShown"
          @answer="answerShown"
          @later="laterShown"
        />
      </template>
    </div>
  </RooTooltipProvider>
</template>

<style scoped>
/* A clear margin round the card, so its shadow is not cut off by the panel's edge. */
.float-root {
  display: inline-block;
  padding: var(--roo-space-group);
}
</style>
