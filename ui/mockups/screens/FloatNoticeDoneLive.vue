<script setup lang="ts">
import FloatNotice from '../../src/parts/FloatNotice.vue'
import type { DoneNotice } from '../../src/types'
import Stage from '../parts/Stage.vue'
import { doneNotice } from '../data/notices'

const notice: DoneNotice = { kind: 'done', id: 'sample', agent: doneNotice.agent, projectName: doneNotice.project, note: doneNotice.note }
</script>

<template>
  <Stage><FloatNotice :notice="notice" /></Stage>
</template>
