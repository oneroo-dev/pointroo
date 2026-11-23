<script setup lang="ts">
import MainWindow from "../parts/MainWindow.vue"
import Stage from "../parts/Stage.vue"
</script>

<template>
  <Stage><MainWindow scenario="queue" :width="720" :height="620" :detail-open="false" /></Stage>
</template>
