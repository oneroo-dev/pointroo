// Serves or builds this app's mockups with the family runner in oneroo (tools/mockups), so no app has its own mockups build.
//   node --import ./scripts/register-resolve.mjs ./scripts/mockups.mjs serve [--port 5190]
//   node --import ./scripts/register-resolve.mjs ./scripts/mockups.mjs build
// ONEROO_ROOT points at the oneroo checkout (default ~/Workspace/oneroo). The runner's shell imports vue from its own
// folder, so vue is aliased to this app's copy here: one Vue in the shell, the kit and the screens.
import { createRequire } from 'node:module'
import { homedir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { parseArgs } from 'node:util'

const appRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const onerooRoot = process.env.ONEROO_ROOT ?? join(homedir(), 'Workspace', 'oneroo')
const { positionals, values } = parseArgs({ allowPositionals: true, options: { port: { type: 'string', default: '5190' } } })
const mode = positionals[0]
if (mode !== 'serve' && mode !== 'build') {
  console.error('usage: mockups.mjs serve|build [--port 5190]')
  process.exit(2)
}

const { createMockupsConfig } = await import(pathToFileURL(join(onerooRoot, 'tools/mockups/vite-config.mjs')).href)
const { createServer, build } = await import('vite')
const appRequire = createRequire(join(appRoot, 'package.json'))
const vueRuntime = join(dirname(appRequire.resolve('vue/package.json')), 'dist/vue.runtime.esm-bundler.js')

const base = createMockupsConfig({ appRoot, outDirectory: join(appRoot, 'mockups-dist'), port: Number(values.port) })
const config = {
  ...base,
  resolve: { ...base.resolve, alias: [{ find: /^vue$/, replacement: vueRuntime }] },
  plugins: base.plugins ?? [],
  server: { ...base.server, fs: { allow: [...base.server.fs.allow, appRoot] } },
}

try {
  if (mode === 'serve') {
    const server = await createServer(config)
    await server.listen()
    server.printUrls()
  } else {
    await build({ ...config, logLevel: 'warn' })
    console.log(`mockups: built ${join(appRoot, 'mockups-dist')}`)
  }
} catch (error) {
  console.error(`mockups: ${error.message}`)
  process.exit(1)
}
