<script setup lang="ts">
import { RooIconButton } from '@roo/kit/controls'
import { RooIcon, RooStateMark } from '@roo/kit'
import QuestionControls from '../../src/parts/QuestionControls.vue'
import FloatingSurface from '../parts/FloatingSurface.vue'
import Stage from '../parts/Stage.vue'
import { asks } from '../data/items'
</script>

<template>
  <Stage>
    <FloatingSurface class="notice" aria-label="Tinkeroo asks">
      <header class="notice-head">
        <RooIcon name="circle-help" :size="16" />
        <h2 class="notice-title">Tinkeroo asks</h2>
        <span class="notice-agent">Claude</span>
        <RooIconButton icon="x" variant="ghost" size="xxs" label="Dismiss" tooltip="Dismiss" />
      </header>
      <QuestionControls v-if="asks.question" :question="asks.question.text" :choices="asks.question.choices" show-later />
    </FloatingSurface>

    <FloatingSurface class="notice" aria-label="Answer sent">
      <RooStateMark state="ok" label="Sent to Claude" />
    </FloatingSurface>
  </Stage>
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
  margin: 0;
  flex: 1 1 auto;
  font-size: var(--roo-p-size-13);
  font-weight: 600;
}

.notice-agent {
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
}
</style>
