<script setup lang="ts">
import FloatPill from '../../src/parts/FloatPill.vue'
import Stage from '../parts/Stage.vue'
import { recordingSample } from '../data/pill'
</script>

<template>
  <Stage><FloatPill phase="recording" :elapsed="recordingSample.elapsed" :points="recordingSample.points" /></Stage>
</template>
