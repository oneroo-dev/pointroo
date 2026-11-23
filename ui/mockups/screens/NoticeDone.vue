<script setup lang="ts">
import { RooToast } from '@roo/kit'
import Stage from '../parts/Stage.vue'
</script>

<template>
  <Stage>
    <RooToast title="Tinkeroo is done" message="Moved Delete to the left and made it red." tone="ok" action-label="Reply" :count="2" :width="360" />
  </Stage>
</template>
