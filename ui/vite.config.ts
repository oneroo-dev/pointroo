// The app build. `npm run dev` serves it for a browser (the fake bridge answers); `npm run build` writes ui/dist, which the
// app loads from a file:// address, so every path is relative and the script is a plain one (a module script with
// `crossorigin` does not load from file:// in a web view).
import vue from '@vitejs/plugin-vue'
import type { Plugin } from 'vite'
import { defineConfig } from 'vite'

function plainScriptForFiles(): Plugin {
  return {
    name: 'plain-script-for-files',
    apply: 'build',
    enforce: 'post',
    transformIndexHtml(html) {
      return html
        .replace(/<script type="module" crossorigin /g, '<script defer ')
        .replace(/<link rel="stylesheet" crossorigin /g, '<link rel="stylesheet" ')
    },
  }
}

export default defineConfig({
  base: './',
  plugins: [vue(), plainScriptForFiles()],
  resolve: { dedupe: ['vue'] },
  server: { port: 5191, strictPort: true },
  build: {
    target: 'safari16',
    outDir: 'dist',
    emptyOutDir: true,
    assetsInlineLimit: 0,
    rollupOptions: { output: { format: 'iife', inlineDynamicImports: true } },
  },
})
