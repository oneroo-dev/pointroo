<script setup lang="ts">
import FloatSent from '../../src/parts/FloatSent.vue'
import { sentView } from '../../src/floatModel'
import Stage from '../parts/Stage.vue'
import { onlySession } from '../data/pill'

const view = sentView({ session: 'sample', project: onlySession.path, projectName: onlySession.name, how: 'only', ids: ['sample#1'] })
</script>

<template>
  <Stage><FloatSent v-if="view !== undefined" :label="view.label" :note="view.note" /></Stage>
</template>
