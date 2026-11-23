<script setup lang="ts">
// One recording in full. It draws the item it is given and raises an event for every click.
import { computed } from 'vue'
import { RooButton } from '@roo/kit/controls'
import { RooChip, RooFormSection, RooIcon, RooListRow, RooStateMark, RooTooltip } from '@roo/kit'
import type { Item, Project } from './types'
import { projectIdFor, tilesFor } from './projects'
import { markFor, pointsWord, sentToLine } from './words'
import ProjectTiles from './ProjectTiles.vue'
import QuestionControls from './QuestionControls.vue'

const props = defineProps<{ item: Item; projects: Project[] }>()

const emit = defineEmits<{
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
      <QuestionControls :question="item.question.text" :choices="item.question.choices" show-later @answer="(text) => emit('answer', item, text)" />
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

    <RooFormSection v-if="isDone && item.note" title="Agent's note">
      <div class="detail-sent">
        <p class="detail-said roo-selectable">{{ item.note }}</p>
        <ul class="detail-crops" aria-label="Before and now">
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
