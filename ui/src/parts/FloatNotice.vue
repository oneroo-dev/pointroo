<script setup lang="ts">
// A notice card, 340 wide (the D4 frame D4NoticeDone). `done` is a notice from notices.list: the two pictures first (Before, Now),
// then "Done in Project", the agent's note (two lines at most), Reply and Open. The keys Enter, R and Esc still work (FloatApp).
// `question` shows the text (two lines at most), up to three choices with the keys 1 to 3, and Later (L).
import { RooButton, RooIconButton } from '@roo/kit/controls'
import { RooChip, RooIcon, RooKbd, RooStateMark } from '@roo/kit'
import FloatingSurface from './FloatingSurface.vue'
import { doneNoticeNote, noticeChoices, noticeProject } from '../floatModel'
import type { Notice } from '../types'

defineProps<{ notice: Notice }>()

const emit = defineEmits<{ open: [itemId: string]; sayMore: [itemId: string]; dismiss: []; answer: [text: string]; later: [] }>()
</script>

<template>
  <FloatingSurface v-if="notice.kind === 'done'" class="notice" role="status" :aria-label="`Done in ${noticeProject(notice)}`">
    <div class="notice-shots">
      <figure class="shot">
        <span class="shot-box">
          <img v-if="notice.cropURL" class="shot-image" :src="notice.cropURL" alt="Before" />
          <RooIcon v-else name="image" :size="16" />
        </span>
        <figcaption class="shot-tag"><RooChip size="small" shape="pill" label="Before" /></figcaption>
      </figure>
      <figure class="shot">
        <span class="shot-box">
          <img v-if="notice.afterURL" class="shot-image" :src="notice.afterURL" alt="Now" />
          <RooIcon v-else name="image" :size="16" />
        </span>
        <figcaption class="shot-tag"><RooChip size="small" shape="pill" label="Now" /></figcaption>
      </figure>
    </div>
    <header class="notice-head notice-line">
      <h2 class="notice-title"><RooStateMark state="ok" :label="`Done in ${noticeProject(notice)}`" /></h2>
      <RooIconButton icon="x" variant="ghost" size="xxs" label="Dismiss" tooltip="Dismiss" shortcut="Escape" @click="emit('dismiss')" />
    </header>
    <p class="notice-note notice-line">{{ doneNoticeNote(notice) }}</p>
    <div class="notice-actions notice-buttons">
      <RooButton variant="ghost" size="sm" @click="emit('sayMore', notice.id)">Reply</RooButton>
      <RooButton variant="secondary" size="sm" @click="emit('open', notice.id)">Open</RooButton>
    </div>
  </FloatingSurface>

  <FloatingSurface v-else class="notice" role="group" :aria-label="`${noticeProject(notice)} asks`">
    <header class="notice-head">
      <RooIcon name="circle-help" :size="16" />
      <h2 class="notice-title">{{ noticeProject(notice) }} asks</h2>
      <RooIconButton icon="x" variant="ghost" size="xxs" label="Dismiss" tooltip="Dismiss" @click="emit('later')" />
    </header>
    <p class="notice-question">{{ notice.text }}</p>
    <div class="notice-choices">
      <RooButton
        v-for="(choice, index) in noticeChoices(notice)"
        :key="choice"
        :variant="index === 0 ? 'primary' : 'secondary'"
        size="md"
        class="choice"
        @click="emit('answer', choice)"
      >
        <span class="choice-label"><span class="choice-text">{{ choice }}</span><RooKbd :keys="String(index + 1)" /></span>
      </RooButton>
    </div>
    <div class="notice-actions">
      <RooButton variant="ghost" size="sm" flush @click="emit('later')">
        <span class="button-label"><span>Later</span><RooKbd keys="L" /></span>
      </RooButton>
    </div>
  </FloatingSurface>
</template>

<style scoped>
.notice {
  display: flex;
  width: 340px;
  flex: none;
  flex-direction: column;
  gap: var(--roo-space-item);
  padding: var(--roo-space-item);
}

.notice-head {
  display: flex;
  align-items: center;
  gap: var(--roo-space-item);
}

.notice-line {
  padding-inline: var(--roo-space-item);
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

.notice-note {
  display: -webkit-box;
  margin: 0;
  overflow: hidden;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
  font-size: var(--roo-p-size-13);
  line-height: 1.4;
}

.notice-buttons {
  justify-content: flex-end;
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
  position: relative;
  min-width: 0;
  margin: 0;
}

.shot-box {
  display: flex;
  aspect-ratio: 16 / 10;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  border: 1px solid var(--roo-border);
  border-radius: var(--roo-p-radius-medium);
  background: var(--roo-raised);
  color: var(--roo-muted);
}

.shot-image {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.shot-tag {
  position: absolute;
  inset-block-end: var(--roo-p-space-1);
  inset-inline-start: var(--roo-p-space-1);
  display: flex;
  border-radius: var(--roo-p-radius-pill);
  background: var(--roo-surface);
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
