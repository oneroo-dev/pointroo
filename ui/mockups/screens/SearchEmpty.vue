<script setup lang="ts">
import SearchWindow from '../parts/SearchWindow.vue'
import Stage from '../parts/Stage.vue'
</script>

<template>
  <Stage><SearchWindow :width="960" query="fuzzy banner" :results="[]" /></Stage>
</template>
