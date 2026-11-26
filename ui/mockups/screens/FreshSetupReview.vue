<script setup lang="ts">
// The fresh-install screens on one long page: setup (ready, fresh Mac), the wake group, item rows and detail with the wake note,
// and the three hints. Each is drawn twice, light then dark, the same way RealReview does it. Keep the shell on Light; with the
// shell on Dark both copies are dark.
import { RooTooltipProvider } from '@roo/kit/controls'
import HintToast from '../../src/parts/HintToast.vue'
import ItemDetail from '../../src/parts/ItemDetail.vue'
import ItemList from '../../src/parts/ItemList.vue'
import SetupChecklist from '../../src/parts/SetupChecklist.vue'
import WakeSettings from '../../src/parts/WakeSettings.vue'
import { projects } from '../data/projects'
import { hints, setupAllGreen, setupFresh, wakeItems, wakeSettings } from '../data/setup'

const sections = [
  { id: 'ready', title: 'Setup when everything is ready', note: 'Every row has a green tick.' },
  { id: 'fresh', title: 'Setup on a fresh Mac', note: 'Each row that is not done has one button. The speech model is still downloading.' },
  { id: 'wake', title: 'Waking Claude sessions', note: 'One switch, who owns each project, and the last wake.' },
  { id: 'rows', title: 'Item rows with the wake note', note: 'A small line after the time: woke a session, no session, busy, or Claude Code too old. The last frame is the same line in the item view.' },
  { id: 'hints', title: 'Hints', note: 'Short messages the app shows when something needs you.' },
]

const looks = [
  { name: 'Light', dark: false },
  { name: 'Dark', dark: true },
]

const detailItem = wakeItems[0]
</script>

<template>
  <RooTooltipProvider>
    <div class="page">
      <header class="intro">
        <h1 class="page-title">Setup and waking Claude</h1>
        <p class="note">Every screen, light then dark. Keep the Light switch on at the top of this tool.</p>
      </header>

      <section v-for="section in sections" :key="section.id" class="section">
        <h2 class="title">{{ section.title }}</h2>
        <p class="note">{{ section.note }}</p>
        <div class="bands">
          <div v-for="look in looks" :key="look.name" class="band" :class="{ dark: look.dark }" :data-app="look.dark ? 'oneroo' : undefined">
            <span class="band-name">{{ look.name }}</span>
            <div class="band-frames">
              <div v-if="section.id === 'ready'" class="panel"><SetupChecklist :rows="setupAllGreen" /></div>
              <div v-else-if="section.id === 'fresh'" class="panel"><SetupChecklist :rows="setupFresh" /></div>
              <div v-else-if="section.id === 'wake'" class="panel"><WakeSettings :settings="wakeSettings" /></div>
              <template v-else-if="section.id === 'rows'">
                <div class="panel"><ItemList :items="wakeItems" :projects="projects" /></div>
                <div v-if="detailItem" class="panel detail"><ItemDetail :item="detailItem" :projects="projects" /></div>
              </template>
              <div v-else class="toasts">
                <HintToast v-for="hint in hints" :key="hint.message" :hint="hint" />
              </div>
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

.panel {
  width: 560px;
  max-width: 100%;
}

.detail {
  width: 480px;
}

.toasts {
  display: flex;
  flex-direction: column;
  gap: var(--roo-space-item);
}
</style>
