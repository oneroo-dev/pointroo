<script setup lang="ts">
// The answer controls of an agent's question. The notice (4.5) and the item detail show the same thing.
// A choice or the typed text raises `answer` with the words.
import { ref } from 'vue'
import { RooButton, RooIconButton, RooInput, RooTooltip } from '@roo/kit/controls'
import { RooKbd } from '@roo/kit'

withDefaults(defineProps<{ question: string; choices: string[]; showLater?: boolean; laterMinutes?: number }>(), { showLater: false, laterMinutes: 30 })
const emit = defineEmits<{ answer: [text: string]; later: [] }>()

const typed = ref('')

function sendTyped(): void {
  const text = typed.value.trim()
  if (text === '') return
  emit('answer', text)
  typed.value = ''
}
</script>

<template>
  <div class="question">
    <p class="question-text">{{ question }}</p>
    <div class="question-choices">
      <RooButton v-for="(choice, index) in choices" :key="choice" :variant="index === 0 ? 'primary' : 'secondary'" size="md" class="question-choice" @click="emit('answer', choice)">
        <span class="question-label"><span>{{ choice }}</span><RooKbd :keys="String(index + 1)" /></span>
      </RooButton>
    </div>
    <div class="question-free">
      <RooInput v-model="typed" class="question-input" aria-label="Type an answer" placeholder="Or type an answer…" @keydown.enter.prevent="sendTyped" />
      <RooIconButton icon="send" variant="secondary" label="Send" tooltip="Send" shortcut="Enter" @click="sendTyped" />
    </div>
    <div v-if="showLater" class="question-later">
      <RooTooltip :text="`Ask me again in ${laterMinutes} minutes`" shortcut="L"><RooButton variant="ghost" size="sm" flush @click="emit('later')">Later</RooButton></RooTooltip>
    </div>
  </div>
</template>

<style scoped>
.question {
  display: flex;
  flex-direction: column;
  gap: var(--roo-space-item);
}

.question-text {
  max-height: 4lh;
  margin: 0;
  overflow-y: auto;
  font-size: var(--roo-p-size-13);
  line-height: 1.4;
}

.question-choices {
  display: flex;
  flex-direction: column;
  gap: var(--roo-space-item);
}

.question-choice {
  width: 100%;
}

.question-label {
  display: flex;
  width: 100%;
  align-items: center;
  justify-content: space-between;
  gap: var(--roo-space-group);
}

.question-free {
  display: flex;
  align-items: center;
  gap: var(--roo-space-item);
}

.question-input {
  flex: 1 1 auto;
  min-width: 0;
}
</style>
