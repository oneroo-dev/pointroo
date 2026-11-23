<script setup lang="ts">
import { ref } from 'vue'
import { RooHowItWorks } from '@roo/kit'
import Stage from '../parts/Stage.vue'

const open = ref(true)
const example = [
  { term: 'You say', value: 'make this button smaller' },
  { term: 'It goes to', value: 'Tinkeroo, the project on screen' },
  { term: 'The agent', value: 'fixes it, then a notice shows the note' },
]
</script>

<template>
  <Stage>
    <RooHowItWorks id="how" v-model:open="open" title="How Pointroo works" :example="example">
      <template #what>Press Control twice, point and talk, press Control twice again. The right Claude session fixes it and tells you when it is done.</template>
      <template #when>Any time showing is faster than typing.</template>
    </RooHowItWorks>
  </Stage>
</template>
