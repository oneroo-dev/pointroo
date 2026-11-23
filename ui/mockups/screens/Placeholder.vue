<script setup lang="ts">
// Scaffold check only. The real screens follow the UX spec (design/ux-spec.md) and replace this file.
import { RooEmpty } from '@roo/kit'
import { RooButton } from '@roo/kit/controls'
import { appName, tagline } from '../data/app'
</script>

<template>
  <main class="placeholder">
    <RooEmpty :title="appName" :description="tagline">
      <RooButton variant="primary">Start recording</RooButton>
    </RooEmpty>
  </main>
</template>
