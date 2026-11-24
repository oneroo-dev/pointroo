<script setup lang="ts">
// A review frame round the real floating picker part (src/parts/FloatPicker.vue). The sample choices come from data/pill.ts. The
// frame holds the countdown still: the end time is pushed on every half second, so a still frame never reads "expired".
import { onBeforeUnmount, onMounted, ref } from 'vue'
import FloatPicker from '../../src/parts/FloatPicker.vue'
import { pickerReply, pickerTiles } from '../data/pill'

const endsAt = ref(Date.now() + pickerReply.countdown * 1000)
let hold: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  hold = setInterval(() => {
    endsAt.value = Date.now() + pickerReply.countdown * 1000
  }, 500)
})
onBeforeUnmount(() => clearInterval(hold))
</script>

<template>
  <FloatPicker :tiles="pickerTiles" :ends-at="endsAt" />
</template>
