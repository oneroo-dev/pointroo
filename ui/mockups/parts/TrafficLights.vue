<script setup lang="ts">
// macOS draws the real window buttons; neutral stand-ins only keep the Bar inset visible in a review frame.
</script>

<template>
  <span class="lights" aria-hidden="true"><i /><i /><i /></span>
</template>

<style scoped>
.lights {
  display: flex;
  gap: var(--roo-space-item);
}

.lights i {
  display: block;
  width: 12px;
  height: 12px;
  border-radius: var(--roo-p-radius-pill);
  background: var(--roo-border);
}
</style>
