<script setup lang="ts">
// The surface of a floating panel (kit gaps G1 and G6): kit surface, a kit shadow and a radius, on kit tokens only.
// `pill` makes the ends fully round (the recording pill); the default is the card radius.
withDefaults(defineProps<{ pill?: boolean }>(), { pill: false })
</script>

<template>
  <div class="surface" :class="{ 'surface-pill': pill }"><slot /></div>
</template>

<style scoped>
.surface {
  box-sizing: border-box;
  border: 1px solid var(--roo-border);
  border-radius: var(--roo-p-radius-card);
  background: var(--roo-surface);
  box-shadow: var(--roo-shadow-popover);
  color: var(--roo-text);
  font-size: var(--roo-p-size-13);
}

.surface-pill {
  border-radius: var(--roo-p-radius-pill);
}
</style>
