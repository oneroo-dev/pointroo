<script setup lang="ts">
// A notice of the kit window, 360 wide. `done` is what done.recent gives: the project, the agent's note on one line, the screen
// before and after, Open and Say more. `question` is what questions.list gives: the text (two lines at most), up to three choices
// with the keys 1 to 3, and Later (L).
import { RooButton, RooIconButton } from '@roo/kit/controls'
import { RooIcon, RooKbd, RooLetterTile } from '@roo/kit'
import FloatingSurface from './FloatingSurface.vue'
import { doneNotice, questionNotice } from '../data/notices'

defineProps<{ kind: 'done' | 'question' }>()

const maxChoices = 3
</script>

<template>
  <FloatingSurface v-if="kind === 'done'" class="notice" role="status" :aria-label="`${doneNotice.project} is done`">
    <header class="notice-head">
      <RooLetterTile :name="doneNotice.project" :size="22" />
      <h2 class="notice-title">{{ doneNotice.project }} is done</h2>
      <span class="notice-agent">{{ doneNotice.agent }}</span>
      <RooIconButton icon="x" variant="ghost" size="xxs" label="Dismiss" tooltip="Dismiss" shortcut="Escape" />
    </header>
    <p class="notice-note">{{ doneNotice.note }}</p>
    <div class="notice-shots">
      <figure class="shot">
        <span class="shot-box"><RooIcon name="image" :size="16" /></span>
        <figcaption class="shot-caption">Before</figcaption>
      </figure>
      <figure class="shot">
        <span class="shot-box"><RooIcon name="image" :size="16" /></span>
        <figcaption class="shot-caption">After</figcaption>
      </figure>
    </div>
    <div class="notice-actions">
      <RooButton variant="primary" size="sm">
        <span class="button-label"><span>Open</span><RooKbd keys="Enter" /></span>
      </RooButton>
      <RooButton variant="secondary" size="sm">
        <span class="button-label"><span>Say more</span><RooKbd keys="R" /></span>
      </RooButton>
    </div>
  </FloatingSurface>

  <FloatingSurface v-else class="notice" role="group" :aria-label="`${questionNotice.project} asks`">
    <header class="notice-head">
      <RooIcon name="circle-help" :size="16" />
      <h2 class="notice-title">{{ questionNotice.project }} asks</h2>
      <span class="notice-agent">{{ questionNotice.agent }}</span>
      <RooIconButton icon="x" variant="ghost" size="xxs" label="Dismiss" tooltip="Dismiss" />
    </header>
    <p class="notice-question">{{ questionNotice.text }}</p>
    <div class="notice-choices">
      <RooButton v-for="(choice, index) in questionNotice.choices.slice(0, maxChoices)" :key="choice" :variant="index === 0 ? 'primary' : 'secondary'" size="md" class="choice">
        <span class="choice-label"><span class="choice-text">{{ choice }}</span><RooKbd :keys="String(index + 1)" /></span>
      </RooButton>
    </div>
    <div class="notice-actions">
      <RooButton variant="ghost" size="sm" flush>
        <span class="button-label"><span>Later</span><RooKbd keys="L" /></span>
      </RooButton>
    </div>
  </FloatingSurface>
</template>

<style scoped>
.notice {
  display: flex;
  width: 360px;
  box-sizing: border-box;
  flex-direction: column;
  gap: var(--roo-space-item);
  padding: var(--roo-space-group);
}

.notice-head {
  display: flex;
  align-items: center;
  gap: var(--roo-space-item);
}

.notice-title {
  min-width: 0;
  margin: 0;
  flex: 1 1 auto;
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
  font-size: var(--roo-p-size-13);
  font-weight: 600;
}

.notice-agent {
  white-space: nowrap;
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
}

.notice-note {
  margin: 0;
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
}

.notice-question {
  display: -webkit-box;
  margin: 0;
  overflow: hidden;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
  font-size: var(--roo-p-size-13);
  line-height: 1.4;
}

.notice-shots {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: var(--roo-space-item);
}

.shot {
  display: flex;
  min-width: 0;
  margin: 0;
  flex-direction: column;
  gap: var(--roo-space-item);
}

.shot-box {
  display: flex;
  aspect-ratio: 16 / 9;
  align-items: center;
  justify-content: center;
  border: 1px solid var(--roo-border);
  border-radius: var(--roo-p-radius-card);
  background: var(--roo-raised);
  color: var(--roo-muted);
}

.shot-caption {
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
}

.notice-choices {
  display: flex;
  flex-direction: column;
  gap: var(--roo-space-item);
}

.choice {
  width: 100%;
}

.choice-label {
  display: flex;
  width: 100%;
  align-items: center;
  justify-content: space-between;
  gap: var(--roo-space-group);
}

.choice-text {
  min-width: 0;
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
}

.notice-actions {
  display: flex;
  flex-wrap: nowrap;
  align-items: center;
  gap: var(--roo-space-item);
}

.button-label {
  display: inline-flex;
  align-items: center;
  gap: var(--roo-space-item);
}
</style>
