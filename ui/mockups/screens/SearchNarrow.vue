<script setup lang="ts">
import SearchWindow from '../parts/SearchWindow.vue'
import Stage from '../parts/Stage.vue'
import { searchQuery } from '../data/search'
</script>

<template>
  <Stage><SearchWindow :width="640" :query="searchQuery" /></Stage>
</template>
