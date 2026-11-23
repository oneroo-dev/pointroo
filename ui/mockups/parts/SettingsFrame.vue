<script setup lang="ts">
import { ref } from 'vue'
import { RooButton, RooCodeBlock, RooInput, RooSelect, RooSwitch } from '@roo/kit/controls'
import { RooAbout, RooDialog, RooSettingRow, RooSettingsGroup, RooSettingsLayout, RooStateMark } from '@roo/kit'
import type { RooSettingsSection } from '@roo/kit'
import MainWindow from './MainWindow.vue'

const props = withDefaults(defineProps<{ start?: string; portBusy?: boolean }>(), { start: 'recording', portBusy: false })

const current = ref(props.start)
const open = ref(true)
const sections: RooSettingsSection[] = [
  { id: 'recording', label: 'Recording', icon: 'mouse-pointer-click', description: 'How you start and stop.', keywords: ['control', 'speech', 'language', 'sounds'] },
  { id: 'agents', label: 'Agents', icon: 'plug', description: 'Which coding agents can read your recordings.', keywords: ['claude', 'codex', 'port', 'mcp', 'server'] },
  { id: 'privacy', label: 'Privacy', icon: 'shield', description: 'What leaves your screen.', keywords: ['blur', 'permissions', 'microphone'] },
  { id: 'general', label: 'General', icon: 'settings', description: 'Start, updates, about.', keywords: ['login', 'version', 'update'] },
]

const languages = ['Same as the Mac', 'English', 'German', 'French', 'Spanish', 'Italian', 'Portuguese', 'Dutch', 'Japanese', 'Chinese'].map((name) => ({ value: name, label: name }))
const followUps = ['Off', '1 min', '3 min', '5 min'].map((name) => ({ value: name, label: name }))
const language = ref('English')
const followUp = ref('3 min')
const port = ref(6742)

const configSnippet = `{
  "mcpServers": {
    "pointroo": { "type": "http", "url": "http://127.0.0.1:6742/mcp" }
  }
}`
</script>

<template>
  <MainWindow />
  <RooDialog v-model:open="open" size="settings" title="Settings" :modal="true">
    <RooSettingsLayout v-model:section="current" :sections="sections">
      <template #default="{ section }">
        <template v-if="section.id === 'recording'">
          <RooSettingsGroup title="Start and stop">
            <RooSettingRow label="Control twice" description="Starts and stops from any app."><RooSwitch :model-value="true" aria-label="Control twice" /></RooSettingRow>
            <RooSettingRow label="Esc cancels" description="Stops and moves it to the Trash."><RooSwitch :model-value="true" aria-label="Esc cancels" /></RooSettingRow>
            <RooSettingRow label="Sounds" description="A soft sound at start and when it is sent."><RooSwitch :model-value="true" aria-label="Sounds" /></RooSettingRow>
          </RooSettingsGroup>
          <RooSettingsGroup title="Speech">
            <RooSettingRow label="Speech language" description="Turned into text on this Mac."><RooSelect v-model="language" label="Speech language" hide-label size="md" :options="languages" /></RooSettingRow>
            <RooSettingRow label="Show recordings with no speech"><RooSwitch :model-value="false" aria-label="Show recordings with no speech" /></RooSettingRow>
            <RooSettingRow label="Follow-up window" description="A new recording soon after a done item goes to the same project."><RooSelect v-model="followUp" label="Follow-up window" hide-label size="md" :options="followUps" /></RooSettingRow>
          </RooSettingsGroup>
        </template>

        <template v-else-if="section.id === 'agents'">
          <RooSettingsGroup title="Coding agents">
            <RooSettingRow label="Claude Code" description="Connected"><RooButton variant="ghost" size="sm">Disconnect</RooButton></RooSettingRow>
            <RooSettingRow label="Codex" description="Not connected"><RooButton variant="secondary" size="sm">Connect</RooButton></RooSettingRow>
            <RooSettingRow label="Connect new agents by themselves"><RooSwitch :model-value="true" aria-label="Connect new agents by themselves" /></RooSettingRow>
          </RooSettingsGroup>
          <RooSettingsGroup title="Shared server">
            <RooSettingRow label="Status">
              <RooStateMark v-if="portBusy" state="err" label="Port 6742 is busy" />
              <RooStateMark v-else state="ok" label="Running on 127.0.0.1:6742" />
            </RooSettingRow>
            <RooSettingRow label="Port" for="port-input">
              <span class="row">
                <RooInput id="port-input" v-model="port" type="number" aria-label="Port" size="md" />
                <RooButton variant="secondary" size="sm">Apply</RooButton>
              </span>
            </RooSettingRow>
            <RooSettingRow label="Set up by hand" description="Add this to an agent that is not listed." stack>
              <RooCodeBlock :code="configSnippet" label="MCP config" language="json" />
            </RooSettingRow>
          </RooSettingsGroup>
        </template>

        <template v-else-if="section.id === 'privacy'">
          <RooSettingsGroup title="Screenshots">
            <RooSettingRow label="Blur secrets in screenshots" description="Hides keys and tokens before anything is saved."><RooSwitch :model-value="true" aria-label="Blur secrets in screenshots" /></RooSettingRow>
          </RooSettingsGroup>
          <RooSettingsGroup title="Permissions">
            <RooSettingRow label="Microphone"><RooStateMark state="ok" label="Allowed" /></RooSettingRow>
            <RooSettingRow label="Accessibility"><RooStateMark state="ok" label="Allowed" /></RooSettingRow>
            <RooSettingRow label="Screen recording"><RooButton variant="secondary" size="sm">Allow</RooButton></RooSettingRow>
          </RooSettingsGroup>
          <RooSettingsGroup title="Storage">
            <RooSettingRow label="Recordings folder"><RooButton variant="secondary" size="sm">Show in Finder</RooButton><template #description><code>~/Pointroo/sessions</code></template></RooSettingRow>
          </RooSettingsGroup>
        </template>

        <template v-else>
          <RooSettingsGroup title="Start and updates">
            <RooSettingRow label="Open at login"><RooSwitch :model-value="false" aria-label="Open at login" /></RooSettingRow>
            <RooSettingRow label="Version"><span class="row"><span>1.3.0</span><RooButton variant="ghost" size="sm">Check for updates</RooButton></span></RooSettingRow>
          </RooSettingsGroup>
          <RooAbout
            app-name="Pointroo"
            tagline="Show, don't type."
            version="1.3.0"
            :links="{ licence: { name: 'MIT', url: 'https://opensource.org/license/mit' } }"
            :extra-rows="[{ key: 'based-on', label: 'Based on', value: 'Point and Yap by Marc Maurer (MIT)' }]"
          />
        </template>
      </template>
    </RooSettingsLayout>
  </RooDialog>
</template>

<style scoped>
.row {
  display: flex;
  align-items: center;
  gap: var(--roo-space-item);
}
</style>
