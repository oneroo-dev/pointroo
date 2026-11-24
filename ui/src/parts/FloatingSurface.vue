<script setup lang="ts">
// The surface of a floating panel (kit gaps G1 and G6): kit surface, card radius and a kit shadow, on kit tokens only.
</script>

<template>
  <div class="surface"><slot /></div>
</template>

<style scoped>
.surface {
  border: 1px solid var(--roo-border);
  border-radius: var(--roo-p-radius-card);
  background: var(--roo-surface);
  box-shadow: var(--roo-shadow-popover);
}
</style>
