<script setup lang="ts">
// One recording in full. It draws the item it is given and raises an event for every click.
import { computed, ref, watch } from 'vue'
import { RooButton } from '@roo/kit/controls'
import { RooChip, RooCollapse, RooFormSection, RooIcon, RooListRow, RooStateMark, RooTooltip } from '@roo/kit'
import type { Item, Project, RecordingView } from './types'
import { projectIdFor, tilesFor } from './projects'
import { markFor, markOwnWords, pointsWord, sentToLine } from './words'
import ProjectTiles from './ProjectTiles.vue'
import QuestionControls from './QuestionControls.vue'

const props = withDefaults(defineProps<{ item: Item; projects: Project[]; recording?: RecordingView | undefined; recordingOpen?: boolean }>(), {
  recording: undefined,
  recordingOpen: false,
})

const emit = defineEmits<{
  later: [item: Item]
  loadRecording: [session: string]
  send: [itemId: string, projectId: string]
  move: [itemId: string, projectId: string]
  done: [itemId: string]
  trash: [itemId: string]
  reopen: [itemId: string]
  copy: [itemId: string]
  answer: [item: Item, text: string]
}>()

const mark = computed(() => markFor(props.item))
const isDone = computed(() => props.item.state === 'done' || props.item.state === 'done-by-you')
const notSent = computed(() => props.item.state === 'not-sent')
const headline = computed(() => [props.item.project ?? 'Not sent yet', mark.value.label, props.item.agent].filter(Boolean).join(' · '))
const saidParts = computed(() => props.item.said.split(/(\[\d+\])/).filter((part) => part !== ''))
const currentId = computed(() => projectIdFor(props.projects, props.item.project))
const choice = computed(() => tilesFor(props.projects, notSent.value ? props.item.suggested : currentId.value))
const sentLine = computed(() => (props.item.state === 'working' && props.item.agent ? `${props.item.agent} is on it.` : sentToLine(props.item)))
const ageTip = computed(() => props.item.atText ?? props.item.age)

const showAfter = computed(() => isDone.value && (!!props.item.note || props.item.afterUrl !== undefined))
const beforeUrl = computed(() => props.item.crops[0]?.url)

const recordingShown = ref(props.recordingOpen)
const enlargedFrame = ref<string | undefined>(undefined)
const saidPieces = computed(() => markOwnWords(props.recording?.said ?? [], props.item.said))

// A new item starts with the Recording section closed.
watch(
  () => props.item.id,
  () => {
    recordingShown.value = false
    enlargedFrame.value = undefined
  },
)

watch(recordingShown, (shown) => {
  if (shown && props.item.session !== undefined) emit('loadRecording', props.item.session)
})

function toggleFrame(url: string): void {
  enlargedFrame.value = enlargedFrame.value === url ? undefined : url
}

function pick(projectId: string): void {
  if (notSent.value) emit('send', props.item.id, projectId)
  else emit('move', props.item.id, projectId)
}
</script>

<template>
  <article class="detail" :aria-label="item.title">
    <header class="detail-head">
      <h2 class="detail-title">{{ item.title }}</h2>
      <p class="detail-line">
        <RooStateMark :state="mark.state" :label="mark.label" />
        <span>{{ headline.replace(`${mark.label} · `, '').replace(` · ${mark.label}`, '') }}</span>
        <RooTooltip :text="ageTip"><span class="detail-age">{{ item.age }}</span></RooTooltip>
      </p>
    </header>

    <RooFormSection v-if="item.question" title="The agent asks">
      <QuestionControls :question="item.question.text" :choices="item.question.choices" show-later @answer="(text) => emit('answer', item, text)" @later="emit('later', item)" />
    </RooFormSection>

    <RooFormSection title="What you said">
      <p class="detail-said roo-selectable">
        <template v-if="item.said === ''">No speech.</template>
        <template v-else>
          <template v-for="(part, index) in saidParts" :key="index">
            <RooChip v-if="/^\[\d+\]$/.test(part)" size="small" mono :label="part.slice(1, -1)" />
            <template v-else>{{ part }}</template>
          </template>
        </template>
      </p>
    </RooFormSection>

    <RooFormSection v-if="item.crops.length > 0" :title="`What you pointed at (${pointsWord(item.points)})`">
      <ul class="detail-crops" aria-label="Crops">
        <li v-for="crop in item.crops" :key="crop.number">
          <RooListRow size="dense" :title="crop.caption" tabindex="0">
            <template #tile>
              <img v-if="crop.url" class="thumb" :src="crop.url" alt="" />
              <RooIcon v-else name="image" :size="16" />
            </template>
            <template #title-prefix><RooChip size="small" mono :label="String(crop.number)" /></template>
          </RooListRow>
        </li>
      </ul>
    </RooFormSection>

    <RooFormSection v-if="showAfter" title="Agent's note">
      <div class="detail-sent">
        <p v-if="item.note" class="detail-said roo-selectable">{{ item.note }}</p>
        <div v-if="item.afterUrl" class="detail-compare" aria-label="Before and now">
          <figure class="detail-shot">
            <img v-if="beforeUrl" class="detail-shot-image" :src="beforeUrl" alt="Before: cropped when you pointed" />
            <div v-else class="detail-shot-image detail-shot-empty"><RooIcon name="image" :size="16" /></div>
            <figcaption class="detail-shot-caption">Before</figcaption>
          </figure>
          <figure class="detail-shot">
            <img class="detail-shot-image" :src="item.afterUrl" alt="Screen now: taken when the agent finished" />
            <figcaption class="detail-shot-caption">Screen now</figcaption>
          </figure>
        </div>
        <ul v-else class="detail-crops" aria-label="Before and now">
          <li>
            <RooListRow size="dense" title="Before" subtitle="Cropped when you pointed" tabindex="0">
              <template #tile>
                <img v-if="item.crops[0]?.url" class="thumb" :src="item.crops[0]?.url" alt="" />
                <RooIcon v-else name="image" :size="16" />
              </template>
            </RooListRow>
          </li>
          <li>
            <RooListRow size="dense" title="Screen now" subtitle="Taken when the agent finished" tabindex="0">
              <template #tile>
                <img v-if="item.afterUrl" class="thumb" :src="item.afterUrl" alt="" />
                <RooIcon v-else name="image" :size="16" />
              </template>
            </RooListRow>
          </li>
        </ul>
      </div>
    </RooFormSection>

    <RooFormSection v-if="item.session !== undefined" title="Recording" description="Everything said and shown in the whole recording.">
      <div class="detail-sent">
        <div class="detail-toggle">
          <RooButton variant="secondary" size="sm" :aria-expanded="recordingShown" @click="recordingShown = !recordingShown">{{ recordingShown ? 'Hide the recording' : 'Show the whole recording' }}</RooButton>
          <span v-if="recordingShown && recording?.summary" class="detail-muted">{{ recording?.summary }}</span>
        </div>
        <RooCollapse v-model:open="recordingShown">
          <div class="detail-sent detail-recording">
            <p v-if="!recording || recording.state === 'loading'" class="detail-muted">Loading the recording…</p>
            <p v-else-if="recording.state === 'error'" class="detail-muted">{{ recording.message || 'The recording could not be loaded.' }}</p>
            <template v-else>
              <p v-if="saidPieces.length === 0" class="detail-muted">No speech.</p>
              <p v-else class="detail-said roo-selectable">
                <template v-for="(piece, index) in saidPieces" :key="index"><mark v-if="piece.own" class="detail-own">{{ piece.text }}</mark><template v-else>{{ piece.text }}</template>{{ ' ' }}</template>
              </p>
              <div v-if="recording.frames.length > 0" class="detail-frames">
                <img v-if="enlargedFrame" class="detail-frame-big" :src="enlargedFrame" alt="Frame, enlarged. Click to shrink." role="button" tabindex="0" @click="enlargedFrame = undefined" @keydown.enter.prevent="enlargedFrame = undefined" @keydown.space.prevent="enlargedFrame = undefined" />
                <div class="detail-strip">
                  <img
                    v-for="(frame, index) in recording.frames"
                    :key="frame"
                    class="detail-frame"
                    :class="{ 'detail-frame-on': frame === enlargedFrame }"
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
              <ul v-if="recording.points.length > 0" class="detail-crops" aria-label="Points">
                <li v-for="(point, index) in recording.points" :key="index">
                  <RooListRow size="dense" :title="point">
                    <template #tile><RooIcon name="mouse-pointer-click" :size="16" /></template>
                  </RooListRow>
                </li>
              </ul>
            </template>
          </div>
        </RooCollapse>
      </div>
    </RooFormSection>

    <RooFormSection :title="notSent ? 'Send to' : 'Sent to'">
      <div class="detail-sent">
        <p class="detail-said">
          <template v-if="notSent">Not sent yet. One click on a project sends it.</template>
          <template v-else><strong>{{ item.project }}</strong>. {{ sentLine }}</template>
        </p>
        <ProjectTiles
          v-if="!isDone"
          :size="notSent ? 'large' : 'small'"
          layout="list"
          :tiles="choice.tiles"
          :more-rows="choice.rest"
          :selected-id="notSent ? undefined : currentId"
          :label="notSent ? 'Send to' : 'Move to'"
          show-keys
          show-more
          @pick="pick"
        />
      </div>
    </RooFormSection>

    <footer class="detail-actions">
      <RooButton v-if="isDone" variant="secondary" size="sm" @click="emit('reopen', item.id)">Open again</RooButton>
      <template v-else>
        <RooButton variant="secondary" size="sm" @click="emit('copy', item.id)">Copy for an agent</RooButton>
        <RooTooltip v-if="item.state === 'waiting' || notSent" text="Mark done" shortcut="D"><RooButton variant="ghost" size="sm" @click="emit('done', item.id)">Mark done</RooButton></RooTooltip>
      </template>
      <span class="detail-spacer" />
      <RooTooltip text="Move to Trash" shortcut="Delete"><RooButton variant="ghost" size="sm" @click="emit('trash', item.id)">Move to Trash</RooButton></RooTooltip>
    </footer>
  </article>
</template>

<style scoped>
.detail {
  display: flex;
  min-height: 100%;
  box-sizing: border-box;
  flex-direction: column;
  gap: var(--roo-space-group);
  padding: var(--roo-space-group);
}

.detail-title {
  margin: 0;
  display: -webkit-box;
  overflow: hidden;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
  font-size: var(--roo-p-size-15);
  font-weight: 600;
  line-height: 1.3;
}

.detail-line {
  display: flex;
  align-items: center;
  gap: var(--roo-space-item);
  margin: var(--roo-space-item) 0 0;
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
}

.detail-said {
  margin: 0;
  font-size: var(--roo-p-size-13);
  line-height: 1.5;
}

.detail-crops {
  display: flex;
  flex-direction: column;
  gap: var(--roo-space-item);
  margin: 0;
  padding: 0;
  list-style: none;
}

.detail-sent {
  display: flex;
  flex-direction: column;
  gap: var(--roo-space-group);
}

.detail-compare {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: var(--roo-space-item);
}

.detail-shot {
  display: flex;
  min-width: 0;
  flex-direction: column;
  gap: var(--roo-space-item);
  margin: 0;
}

.detail-shot-image {
  display: block;
  width: 100%;
  aspect-ratio: 4 / 3;
  box-sizing: border-box;
  border: 1px solid var(--roo-border);
  border-radius: var(--roo-p-radius-card);
  object-fit: cover;
}

.detail-shot-empty {
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--roo-muted);
}

.detail-shot-caption {
  overflow: hidden;
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
  text-overflow: ellipsis;
  white-space: nowrap;
}

.detail-toggle {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: var(--roo-space-item);
}

.detail-muted {
  min-width: 0;
  margin: 0;
  overflow: hidden;
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
  text-overflow: ellipsis;
}

.detail-recording {
  padding-block-start: var(--roo-space-item);
}

.detail-own {
  border-radius: var(--roo-p-radius-card);
  background: var(--roo-accent-bg);
  color: var(--roo-accent-text);
}

.detail-frames {
  display: flex;
  flex-direction: column;
  gap: var(--roo-space-item);
}

.detail-frame-big {
  display: block;
  width: 100%;
  box-sizing: border-box;
  border: 1px solid var(--roo-border);
  border-radius: var(--roo-p-radius-card);
  cursor: zoom-out;
}

.detail-strip {
  display: flex;
  gap: var(--roo-space-item);
  overflow-x: auto;
}

.detail-frame {
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

.detail-frame-on {
  border-color: var(--roo-accent-ring);
}

.detail-actions {
  display: flex;
  align-items: center;
  gap: var(--roo-space-item);
  margin-top: auto;
}

.detail-spacer {
  flex: 1 1 auto;
}

.thumb {
  display: block;
  width: 100%;
  height: 100%;
  border-radius: inherit;
  object-fit: cover;
}
</style>
