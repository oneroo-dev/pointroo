<script setup lang="ts">
import { RooBarChip, RooKbd, RooListRow } from '@roo/kit'
import Stage from '../parts/Stage.vue'

const titles = ['2 working, 1 waiting', '1 asks you, 2 working', 'Needs you']
</script>

<template>
  <Stage>
    <div class="column">
      <p class="note">Menu bar title, by state. The real menu is a native NSMenu; this frame only shows its words.</p>
      <div class="titles"><RooBarChip v-for="title in titles" :key="title" :label="title" /></div>

      <ul class="menu surface" aria-label="Pointroo menu">
        <li><RooListRow size="single" title="Start recording"><template #trailing><RooKbd keys="Control Control" /></template></RooListRow></li>
        <li><RooListRow size="single" title="Open Pointroo"><template #trailing><RooKbd keys="Mod+O" /></template></RooListRow></li>
        <li class="heading">Tinkeroo</li>
        <li><RooListRow size="single" title="Asks you: Should Delete ask first?" /></li>
        <li><RooListRow size="single" title="Working: Move delete away from save" /></li>
        <li class="heading">Pointroo</li>
        <li><RooListRow size="single" title="Waiting: Make the pill a bit smaller" /></li>
        <li><RooListRow size="single" title="Settings…"><template #trailing><RooKbd keys="Mod+," /></template></RooListRow></li>
        <li><RooListRow size="single" title="Quit Pointroo"><template #trailing><RooKbd keys="Mod+Q" /></template></RooListRow></li>
      </ul>
    </div>
  </Stage>
</template>

<style scoped>
.column {
  display: flex;
  flex-direction: column;
  gap: var(--roo-space-group);
}

.note {
  max-width: 360px;
  margin: 0;
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
}

.titles {
  display: flex;
  gap: var(--roo-space-item);
}

.surface {
  border: 1px solid var(--roo-border);
  border-radius: var(--roo-p-radius-card);
  background: var(--roo-surface);
  box-shadow: var(--roo-shadow-popover);
}

.menu {
  display: flex;
  width: 320px;
  flex-direction: column;
  gap: var(--roo-space-item);
  margin: 0;
  padding: var(--roo-space-item);
  list-style: none;
}

.heading {
  padding: var(--roo-space-item) var(--roo-space-group) 0;
  color: var(--roo-muted);
  font-size: var(--roo-p-size-12);
}
</style>
