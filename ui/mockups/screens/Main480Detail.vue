<script setup lang="ts">
import MainWindow from "../parts/MainWindow.vue"
import Stage from "../parts/Stage.vue"
</script>

<template>
  <Stage><MainWindow scenario="queue" :width="480" :height="560" :detail-open="true" /></Stage>
</template>
