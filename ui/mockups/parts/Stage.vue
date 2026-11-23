<script setup lang="ts">
// Every frame sits in a Stage: one tooltip provider and an even margin round the frame, at its real size.
import { RooTooltipProvider } from '@roo/kit/controls'
</script>

<template>
  <RooTooltipProvider>
    <div class="stage"><slot /></div>
  </RooTooltipProvider>
</template>

<style scoped>
.stage {
  display: flex;
  min-height: 100vh;
  box-sizing: border-box;
  align-items: flex-start;
  gap: var(--roo-space-section);
  padding: var(--roo-space-page);
  background: var(--roo-bg);
  color: var(--roo-text);
}
</style>
