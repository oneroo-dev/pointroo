<script setup lang="ts">
// Every real redesigned screen on one long page, so nobody has to use the frame select box. Each part is the real one
// from ui/src, drawn twice: light, then dark. The dark copy sits in a wrapper with the kit's `dark` class, so keep the
// shell on Light; with the shell on Dark both copies are dark.
import { RooTooltipProvider } from '@roo/kit/controls'
import FloatPickerFrame from '../parts/FloatPickerFrame.vue'
import MainWindow from '../parts/MainWindow.vue'
import FloatNotice from '../../src/parts/FloatNotice.vue'
import FloatPill from '../../src/parts/FloatPill.vue'
import FloatSent from '../../src/parts/FloatSent.vue'
import { sentView } from '../../src/floatModel'
import type { DoneNotice } from '../../src/types'
import { doneNotice } from '../data/notices'
import { onlySession, recordingSample } from '../data/pill'

const sections = [
  { title: 'Queue', note: 'What you asked, where it went, is it done. Narrow, then wide.' },
  { title: 'One recording', note: 'One recording open, narrow, then wide.' },
  { title: 'Just sent', note: 'The new recording is on top, with its own Undo.' },
  { title: 'Nothing waiting', note: 'Nothing is in the queue.' },
  { title: 'Settings', note: 'The settings screen at 640 wide.' },
  { title: 'Recording pill', note: 'Recording, writing it up, sent (with Change and Undo).' },
  { title: 'Project picker', note: 'The first row is the guess. Press its number or click it; when time runs out it stays in the queue.' },
  { title: 'Done notice', note: 'The agent says it is done.' },
]

const looks = [
  { name: 'Light', dark: false },
  { name: 'Dark', dark: true },
]

const sentLook = sentView({ session: 'sample', project: onlySession.path, projectName: onlySession.name, how: 'only', ids: ['sample#1'] })
const notice: DoneNotice = { kind: 'done', id: 'sample', agent: doneNotice.agent, projectName: doneNotice.project, note: doneNotice.note }
</script>

<template>
  <RooTooltipProvider>
    <div class="page">
      <header class="intro">
        <h1 class="page-title">Redesign: the real screens</h1>
        <p class="note">Every screen, light then dark. Keep the Light switch on at the top of this tool.</p>
      </header>

      <section v-for="section in sections" :key="section.title" class="section">
        <h2 class="title">{{ section.title }}</h2>
        <p class="note">{{ section.note }}</p>
        <div class="bands">
          <div v-for="look in looks" :key="look.name" class="band" :class="{ dark: look.dark }" :data-app="look.dark ? 'oneroo' : undefined">
            <span class="band-name">{{ look.name }}</span>
            <div class="band-frames">
              <template v-if="section.title === 'Queue'">
                <MainWindow scenario="queue" :width="480" :height="560" :detail-open="false" />
                <MainWindow scenario="queue" :width="720" :height="620" :detail-open="false" />
              </template>
              <template v-else-if="section.title === 'One recording'">
                <MainWindow scenario="queue" :width="480" :height="560" :detail-open="true" />
                <MainWindow scenario="queue" :width="720" :height="620" :detail-open="true" />
              </template>
              <MainWindow v-else-if="section.title === 'Just sent'" scenario="just-sent" />
              <MainWindow v-else-if="section.title === 'Nothing waiting'" scenario="empty" />
              <MainWindow v-else-if="section.title === 'Settings'" scenario="settings" :width="640" :height="760" />
              <template v-else-if="section.title === 'Recording pill'">
                <FloatPill phase="recording" :elapsed="recordingSample.elapsed" :points="recordingSample.points" />
                <FloatPill phase="processing" :elapsed="recordingSample.elapsed" :points="recordingSample.points" />
                <FloatSent v-if="sentLook !== undefined" :label="sentLook.label" :note="sentLook.note" />
              </template>
              <FloatPickerFrame v-else-if="section.title === 'Project picker'" />
              <FloatNotice v-else-if="section.title === 'Done notice'" :notice="notice" />
            </div>
          </div>
        </div>
      </section>
    </div>
  </RooTooltipProvider>
</template>

<style scoped>
.page {
  display: flex;
  min-height: 100vh;
  box-sizing: border-box;
  flex-direction: column;
  gap: var(--roo-space-section);
  padding: var(--roo-space-page);
  background: var(--roo-bg);
  color: var(--roo-text);
}

.intro,
.section {
  display: flex;
  flex-direction: column;
  gap: var(--roo-space-item);
}

.page-title {
  margin: 0;
  font-size: var(--roo-p-size-22);
  font-weight: 600;
}

.title {
  margin: 0;
  font-size: var(--roo-p-size-16);
  font-weight: 600;
}

.note {
  margin: 0;
  color: var(--roo-muted);
  font-size: var(--roo-p-size-13);
}

.bands {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-start;
  gap: var(--roo-space-group);
}

.band {
  display: flex;
  flex-direction: column;
  gap: var(--roo-space-item);
  padding: var(--roo-space-group);
  border: 1px solid var(--roo-border);
  border-radius: var(--roo-p-radius-large);
  background: var(--roo-bg);
  color: var(--roo-text);
}

.band-name {
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
  font-weight: 600;
}

.band-frames {
  display: flex;
  align-items: flex-start;
  gap: var(--roo-space-group);
}
</style>
