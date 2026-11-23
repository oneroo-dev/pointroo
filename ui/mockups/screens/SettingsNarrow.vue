<script setup lang="ts">
import MainWindow from "../parts/MainWindow.vue"
import Stage from "../parts/Stage.vue"
</script>

<template>
  <Stage><MainWindow scenario="settings" :width="640" :height="760" /></Stage>
</template>
