<script setup lang="ts">
import PillFrame from '../parts/PillFrame.vue'
import Stage from '../parts/Stage.vue'
</script>

<template>
  <Stage>
    <div class="pills">
      <PillFrame kind="recording" />
      <PillFrame kind="writing" />
      <PillFrame kind="sent" />
      <PillFrame kind="reply" />
      <PillFrame kind="error" />
      <PillFrame kind="kept" />
    </div>
  </Stage>
</template>

<style scoped>
.pills {
  display: flex;
  flex-direction: column;
  gap: var(--roo-space-group);
}
</style>
