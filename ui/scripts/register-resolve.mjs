// The oneroo checkout on this Mac has no node_modules, so the shared mockups runner (oneroo/tools/mockups) cannot find
// vite or the Vue plugin from its own folder. This hook sends a bare import that fails there to this app's node_modules.
import { register } from 'node:module'

register('./resolve-hooks.mjs', import.meta.url)
