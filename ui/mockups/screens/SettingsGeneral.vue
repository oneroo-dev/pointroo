<script setup lang="ts">
import SettingsFrame from "../parts/SettingsFrame.vue"
import Stage from "../parts/Stage.vue"
</script>

<template>
  <Stage><SettingsFrame start="general" :port-busy="false" /></Stage>
</template>
