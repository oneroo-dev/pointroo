<script setup lang="ts">
import { RooButton } from '@roo/kit/controls'
import { RooCodeBlock, RooPageIntro, RooSettingRow, RooSettingsGroup, RooStateCard, RooStateMark } from '@roo/kit'

defineProps<{ step: 'microphone' | 'accessibility' | 'screen' | 'agents' | 'done' }>()

const order = ['microphone', 'accessibility', 'screen']
const permissions = [
  { id: 'microphone', label: 'Microphone', description: 'Hears what you say while you point.' },
  { id: 'accessibility', label: 'Accessibility', description: 'Reads the button or field under your cursor.' },
  { id: 'screen', label: 'Screen recording', description: 'Takes the screenshots. Pointroo restarts once after this.' },
]

function allowed(step: string, id: string): boolean {
  if (step === 'agents' || step === 'done') return true
  return order.indexOf(id) < order.indexOf(step)
}
</script>

<template>
  <div class="setup">
    <div class="setup-column">
      <RooPageIntro title="Set up Pointroo" purpose="Three permissions and one click. About a minute." how-controls="how" />

      <RooSettingsGroup title="Allow three things">
        <RooSettingRow v-for="permission in permissions" :key="permission.id" :label="permission.label" :description="permission.description">
          <RooStateMark v-if="allowed(step, permission.id)" state="ok" label="Allowed" />
          <RooButton v-else :variant="permission.id === step ? 'primary' : 'secondary'" size="sm">Allow</RooButton>
        </RooSettingRow>
      </RooSettingsGroup>

      <RooSettingsGroup title="Coding agents">
        <RooSettingRow label="Coding agents" description="Adds Pointroo to Claude Code, Codex. Each config is backed up first.">
          <RooStateMark v-if="step === 'done'" state="ok" label="Connected" />
          <span v-else class="setup-actions">
            <RooButton variant="ghost" size="sm">Not now</RooButton>
            <RooButton :variant="step === 'agents' ? 'primary' : 'secondary'" size="sm">Connect</RooButton>
          </span>
        </RooSettingRow>
      </RooSettingsGroup>

      <template v-if="step === 'done'">
        <RooStateCard kind="ok" title="Try it" description="Point at this window and talk." />
        <RooSettingsGroup title="Connect a Claude session">
          <RooSettingRow label="In your project" description="Paste this into Claude Code to start taking work." stack>
            <RooCodeBlock code="work through Pointroo" label="Claude Code prompt" />
          </RooSettingRow>
        </RooSettingsGroup>
        <div class="setup-actions"><RooButton variant="primary" size="md">Done</RooButton></div>
      </template>
    </div>
  </div>
</template>

<style scoped>
.setup {
  display: flex;
  height: 100%;
  justify-content: center;
  overflow-y: auto;
  padding: var(--roo-space-section) var(--roo-space-group);
}

.setup-column {
  display: flex;
  width: 100%;
  max-width: 560px;
  flex-direction: column;
  gap: var(--roo-space-section);
}

.setup-actions {
  display: flex;
  align-items: center;
  gap: var(--roo-space-item);
}
</style>
