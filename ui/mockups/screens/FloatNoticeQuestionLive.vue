<script setup lang="ts">
import FloatNotice from '../../src/parts/FloatNotice.vue'
import type { QuestionNotice } from '../../src/types'
import Stage from '../parts/Stage.vue'
import { questionNotice } from '../data/notices'

const notice: QuestionNotice = {
  kind: 'question',
  id: 'sample',
  project: questionNotice.project,
  agent: questionNotice.agent,
  text: questionNotice.text,
  choices: questionNotice.choices,
  asked: 0,
}
</script>

<template>
  <Stage><FloatNotice :notice="notice" /></Stage>
</template>
