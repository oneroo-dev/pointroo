<script setup lang="ts">
// One recording. Top line: the way back (narrow only), where it stands, where it went (the project name is a menu to choose
// another one) and when, then Mark done and a "..." menu that holds the rest (copy, the whole recording, show in Finder, Trash). Then the crop as big as the window allows, with
// small crops to switch, and your words in full. It draws the item it is given and raises an event for every click.
import { computed, ref, watch } from 'vue'
import { RooButton, RooIconButton, RooTooltip } from '@roo/kit/controls'
import { RooIcon, RooListRow, RooSegmented, RooStateMark } from '@roo/kit'
import { RooMenu, RooMenuItem, RooMenuSeparator } from '@roo/kit/overlays'
import type { Item, Project, RecordingView } from './types'
import { projectIdFor, projectNameFor, tilesFor } from './projects'
import { isFinished, markFor, markOwnWords, plainWords } from './words'
import ProjectMenu from './ProjectMenu.vue'
import ProjectTiles from './ProjectTiles.vue'
import QuestionControls from './QuestionControls.vue'

const props = withDefaults(defineProps<{ item: Item; projects: Project[]; recording?: RecordingView | undefined; recordingOpen?: boolean; back?: boolean }>(), {
  recording: undefined,
  recordingOpen: false,
  back: false,
})

const emit = defineEmits<{
  back: []
  later: [item: Item]
  loadRecording: [session: string]
  send: [itemId: string, projectId: string]
  move: [itemId: string, projectId: string]
  done: [itemId: string]
  trash: [itemId: string]
  reopen: [itemId: string]
  copy: [itemId: string]
  reveal: [itemId: string]
  answer: [item: Item, text: string]
}>()

const mark = computed(() => markFor(props.item))
const isDone = computed(() => isFinished(props.item))
const notSent = computed(() => props.item.state === 'not-sent')
const words = computed(() => plainWords(props.item.said))
const ageTip = computed(() => props.item.atText ?? props.item.age)
const currentId = computed(() => projectIdFor(props.projects, props.item.project))
const choice = computed(() => tilesFor(props.projects, notSent.value ? props.item.suggested : currentId.value))
const projectName = computed(() => projectNameFor(props.projects, props.item.project) ?? 'Not sent')
// The project name is a menu for every item that is still open (waiting, working, asking, not sent).
const canChoose = computed(() => !isDone.value && props.item.state !== 'processing' && props.projects.length > 0)

const shotIndex = ref(0)
const side = ref('now')
const sideOptions = [
  { value: 'before', label: 'Before' },
  { value: 'now', label: 'Now' },
]
const hasAfter = computed(() => isDone.value && props.item.afterUrl !== undefined)
const heroUrl = computed(() => {
  if (hasAfter.value && side.value === 'now') return props.item.afterUrl
  return (props.item.crops[shotIndex.value] ?? props.item.crops[0])?.url
})

const recordingShown = ref(props.recordingOpen)
const enlargedFrame = ref<string | undefined>(undefined)
const saidPieces = computed(() => markOwnWords(props.recording?.said ?? [], props.item.said))
const menuOpen = ref(false)

// A new item starts on its first crop, with the whole recording closed.
watch(
  () => props.item.id,
  () => {
    shotIndex.value = 0
    side.value = 'now'
    recordingShown.value = false
    enlargedFrame.value = undefined
  },
)

watch(
  recordingShown,
  (shown) => {
    if (shown && props.item.session !== undefined) emit('loadRecording', props.item.session)
  },
  { immediate: true },
)

function toggleFrame(url: string): void {
  enlargedFrame.value = enlargedFrame.value === url ? undefined : url
}

function pick(projectId: string): void {
  if (notSent.value) emit('send', props.item.id, projectId)
  else emit('move', props.item.id, projectId)
}
</script>

<template>
  <article class="detail" aria-label="Recording">
    <header class="top">
      <RooButton v-if="back" variant="ghost" size="sm" flush @click="emit('back')">
        <template #icon><RooIcon name="arrow-left" :size="16" /></template>
        Queue
      </RooButton>
      <span class="status">
        <RooStateMark :state="mark.state" :label="mark.label" />
        <span class="where">
          <ProjectMenu v-if="canChoose" :name="projectName" :projects="projects" :current-id="currentId" @pick="pick" />
          <template v-else>{{ projectName }}</template>
          <RooTooltip :text="ageTip"><span class="age">{{ ` · ${item.age}` }}</span></RooTooltip>
        </span>
      </span>
      <span class="spacer" />
      <RooIconButton v-if="isDone" icon="rotate-ccw" variant="ghost" size="sm" label="Open again" tooltip="Open again" @click="emit('reopen', item.id)" />
      <RooIconButton v-else icon="check" variant="ghost" size="sm" label="Mark done" tooltip="Mark done" shortcut="D" @click="emit('done', item.id)" />
      <RooMenu v-model:open="menuOpen" align="end">
        <template #trigger>
          <RooIconButton icon="more" variant="ghost" size="sm" label="More" tooltip="Copy, whole recording, Trash" :pressed="menuOpen" />
        </template>
        <RooMenuItem icon="copy" @select="emit('copy', item.id)">Copy for an agent</RooMenuItem>
        <RooMenuItem v-if="item.session !== undefined" icon="list" @select="recordingShown = true">The whole recording</RooMenuItem>
        <RooMenuItem icon="folder-open" @select="emit('reveal', item.id)">Show in Finder</RooMenuItem>
        <RooMenuSeparator />
        <RooMenuItem icon="trash" destructive shortcut="Delete" @select="emit('trash', item.id)">Move to Trash</RooMenuItem>
      </RooMenu>
    </header>

    <section v-if="item.question" class="ask" aria-label="The agent asks">
      <QuestionControls :question="item.question.text" :choices="item.question.choices" show-later @answer="(text) => emit('answer', item, text)" @later="emit('later', item)" />
    </section>

    <figure class="hero">
      <img v-if="heroUrl" class="hero-image" :src="heroUrl" :alt="hasAfter && side === 'now' ? 'The screen now' : 'Where you pointed'" />
      <span v-else class="hero-empty"><RooIcon name="image" :size="16" /></span>
      <div v-if="hasAfter" class="hero-switch">
        <RooSegmented v-model="side" label="Picture" :options="sideOptions" />
      </div>
    </figure>

    <div v-if="item.crops.length > 1 && !hasAfter" class="strip" aria-label="Crops">
      <span
        v-for="(crop, index) in item.crops"
        :key="crop.number"
        class="thumb"
        role="button"
        tabindex="0"
        :aria-label="`Crop ${index + 1}`"
        :aria-pressed="index === shotIndex"
        :data-on="index === shotIndex ? 'true' : undefined"
        @click="shotIndex = index"
        @keydown.enter.prevent="shotIndex = index"
        @keydown.space.prevent="shotIndex = index"
      >
        <img v-if="crop.url" class="thumb-image" :src="crop.url" alt="" />
      </span>
    </div>

    <p class="said roo-selectable">{{ words === '' ? 'No speech.' : words }}</p>

    <p v-if="item.note" class="note">
      <span class="note-icon"><RooIcon name="check" :size="16" /></span>
      <span class="roo-selectable">{{ item.note }}</span>
    </p>

    <section v-if="notSent" class="send" aria-label="Send to">
      <p class="send-title">Send to</p>
      <ProjectTiles size="large" layout="list" :tiles="choice.tiles" :more-rows="choice.rest" label="Send to" show-keys show-more @pick="pick" />
    </section>

    <section v-if="recordingShown" class="whole" aria-label="The whole recording">
      <div class="whole-head">
        <span class="whole-title">The whole recording</span>
        <span v-if="recording?.summary" class="muted">{{ recording.summary }}</span>
        <span class="spacer" />
        <RooButton variant="ghost" size="sm" @click="recordingShown = false">Hide</RooButton>
      </div>
      <p v-if="!recording || recording.state === 'loading'" class="muted">Loading the recording…</p>
      <p v-else-if="recording.state === 'error'" class="muted">{{ recording.message || 'The recording could not be loaded.' }}</p>
      <template v-else>
        <p v-if="saidPieces.length === 0" class="muted">No speech.</p>
        <p v-else class="whole-said roo-selectable">
          <template v-for="(piece, index) in saidPieces" :key="index"><mark v-if="piece.own" class="own">{{ piece.text }}</mark><template v-else>{{ piece.text }}</template>{{ ' ' }}</template>
        </p>
        <div v-if="recording.frames.length > 0" class="frames">
          <img v-if="enlargedFrame" class="frame-big" :src="enlargedFrame" alt="Frame, enlarged. Click to shrink." role="button" tabindex="0" @click="enlargedFrame = undefined" @keydown.enter.prevent="enlargedFrame = undefined" @keydown.space.prevent="enlargedFrame = undefined" />
          <div class="frame-strip">
            <img
              v-for="(frame, index) in recording.frames"
              :key="frame"
              class="frame"
              :data-on="frame === enlargedFrame ? 'true' : undefined"
              :src="frame"
              :alt="`Frame ${index + 1}. Click to enlarge.`"
              role="button"
              tabindex="0"
              @click="toggleFrame(frame)"
              @keydown.enter.prevent="toggleFrame(frame)"
              @keydown.space.prevent="toggleFrame(frame)"
            />
          </div>
        </div>
        <div v-if="recording.points.length > 0" class="points" aria-label="Points">
          <RooListRow v-for="(point, index) in recording.points" :key="index" size="dense" :title="point">
            <template #tile><RooIcon name="mouse-pointer-click" :size="16" /></template>
          </RooListRow>
        </div>
      </template>
    </section>
  </article>
</template>

<style scoped>
.detail {
  display: flex;
  box-sizing: border-box;
  flex-direction: column;
  gap: var(--roo-space-group);
  padding: var(--roo-space-group);
}

.top {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: var(--roo-space-item);
}

.status {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: var(--roo-space-item);
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
}

.where {
  display: flex;
  min-width: 0;
  align-items: center;
  white-space: nowrap;
}

.age {
  flex: none;
}

.spacer {
  flex: 1 1 auto;
}

.ask {
  padding: var(--roo-space-group);
  border-radius: var(--roo-p-radius-card);
  background: var(--roo-raised);
}

.hero {
  position: relative;
  margin: 0;
  overflow: hidden;
  border: 1px solid var(--roo-border);
  border-radius: var(--roo-p-radius-card);
  background: var(--roo-raised);
  aspect-ratio: 16 / 10;
}

.hero-image {
  display: block;
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.hero-empty {
  display: flex;
  width: 100%;
  height: 100%;
  align-items: center;
  justify-content: center;
  color: var(--roo-muted);
}

.hero-switch {
  position: absolute;
  inset-block-end: var(--roo-space-item);
  inset-inline-start: var(--roo-space-item);
  border-radius: var(--roo-p-radius-medium);
  background: var(--roo-surface);
}

.strip {
  display: flex;
  gap: var(--roo-space-item);
}

.thumb {
  display: block;
  width: 72px;
  height: 46px;
  flex: none;
  box-sizing: border-box;
  overflow: hidden;
  border: 1px solid var(--roo-border);
  border-radius: var(--roo-p-radius-small);
  background: var(--roo-raised);
  opacity: 0.6;
  cursor: default;
}

.thumb[data-on] {
  border-color: var(--roo-accent-ring);
  outline: 1px solid var(--roo-accent-ring);
  opacity: 1;
}

.thumb:focus-visible {
  outline: 2px solid var(--roo-focus);
}

.thumb-image {
  display: block;
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.said {
  margin: 0;
  font-size: var(--roo-p-size-16);
  line-height: 1.5;
}

.note {
  display: flex;
  align-items: flex-start;
  gap: var(--roo-space-item);
  margin: 0;
  padding: var(--roo-space-group);
  border-radius: var(--roo-p-radius-card);
  background: var(--roo-ok-bg);
  font-size: var(--roo-p-size-13);
  line-height: 1.5;
}

.note-icon {
  display: flex;
  flex: none;
  color: var(--roo-ok);
}

.send {
  display: flex;
  flex-direction: column;
  gap: var(--roo-space-item);
}

.send-title {
  margin: 0;
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
}

.whole {
  display: flex;
  flex-direction: column;
  gap: var(--roo-space-group);
  padding-block-start: var(--roo-space-group);
  border-block-start: 1px solid var(--roo-border);
}

.whole-head {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: var(--roo-space-item);
}

.whole-title {
  font-size: var(--roo-p-size-13);
  font-weight: 600;
}

.whole-said {
  margin: 0;
  font-size: var(--roo-p-size-13);
  line-height: 1.5;
}

.muted {
  min-width: 0;
  margin: 0;
  overflow: hidden;
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
  text-overflow: ellipsis;
}

.own {
  border-radius: var(--roo-p-radius-card);
  background: var(--roo-accent-bg);
  color: var(--roo-accent-text);
}

.frames {
  display: flex;
  flex-direction: column;
  gap: var(--roo-space-item);
}

.frame-big {
  display: block;
  width: 100%;
  box-sizing: border-box;
  border: 1px solid var(--roo-border);
  border-radius: var(--roo-p-radius-card);
  cursor: zoom-out;
}

.frame-strip {
  display: flex;
  gap: var(--roo-space-item);
  overflow-x: auto;
}

.frame {
  display: block;
  width: 64px;
  height: 48px;
  flex: none;
  box-sizing: border-box;
  border: 1px solid var(--roo-border);
  border-radius: var(--roo-p-radius-card);
  cursor: zoom-in;
  object-fit: cover;
}

.frame[data-on] {
  border-color: var(--roo-accent-ring);
}

.points {
  display: flex;
  flex-direction: column;
  gap: var(--roo-space-item);
}
</style>
