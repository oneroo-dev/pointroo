// The family checks on this app, one command (run `npm run mockups:build` first):
//   1. oneroo tools/kit-strict.mjs on this folder
//   2. oneroo tools/kit-fork-check.mjs findingsFor() on this folder (copies of kit parts, restyled kit classes)
//   3. oneroo tools/family-2c.mjs on every built frame, light and dark, at 1440 wide
// ONEROO_ROOT points at the oneroo checkout (default ~/Workspace/oneroo).
import { spawnSync } from 'node:child_process'
import { createServer } from 'node:http'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, extname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { chromium } from 'playwright-core'

const appRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const onerooRoot = process.env.ONEROO_ROOT ?? join(homedir(), 'Workspace', 'oneroo')
const distRoot = join(appRoot, 'mockups-dist')
let failed = false

const strict = spawnSync('node', [join(onerooRoot, 'tools/kit-strict.mjs'), '--app', appRoot], { encoding: 'utf8' })
process.stdout.write(strict.stdout + strict.stderr)
if (strict.status !== 0) failed = true

const { findingsFor } = await import(pathToFileURL(join(onerooRoot, 'tools/kit-fork-check.mjs')).href)
const forks = findingsFor(appRoot, ['mockups', 'src'])
const forkCount = forks === null ? 0 : (forks.forks?.length ?? 0) + (forks.overrides?.length ?? 0)
console.log(`kit-fork-check: ${forkCount} findings`)
if (forkCount > 0) {
  console.log(JSON.stringify(forks, null, 2))
  failed = true
}

if (!existsSync(join(distRoot, 'mockups.json'))) {
  console.error('family-2c: mockups-dist is missing, run npm run mockups:build first')
  process.exit(1)
}
const { runFamily2c } = await import(pathToFileURL(join(onerooRoot, 'tools/family-2c.mjs')).href)
const listing = JSON.parse(readFileSync(join(distRoot, 'mockups.json'), 'utf8'))
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.woff2': 'font/woff2', '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg' }
const server = createServer((request, response) => {
  const path = join(distRoot, decodeURIComponent(new URL(request.url, 'http://x').pathname).replace(/^\/$/, '/index.html'))
  if (!path.startsWith(distRoot) || !existsSync(path)) {
    response.writeHead(404).end()
    return
  }
  response.writeHead(200, { 'content-type': types[extname(path)] ?? 'application/octet-stream' }).end(readFileSync(path))
})
await new Promise((done) => server.listen(0, '127.0.0.1', done))
const origin = `http://127.0.0.1:${server.address().port}`
// playwright-core wants its own browser build; any headless shell already in the cache does the job (nothing is downloaded).
function cachedHeadlessShell() {
  const cache = join(homedir(), 'Library', 'Caches', 'ms-playwright')
  if (!existsSync(cache)) return undefined
  const folders = readdirSync(cache).filter((name) => name.startsWith('chromium_headless_shell-')).sort().reverse()
  for (const folder of folders) {
    const candidate = join(cache, folder, 'chrome-headless-shell-mac-arm64', 'chrome-headless-shell')
    if (existsSync(candidate)) return candidate
  }
  return undefined
}
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH ?? cachedHeadlessShell() })
let frameCount = 0
let findingCount = 0
for (const screen of listing.screens) {
  for (const appearance of ['light', 'dark']) {
    const page = await browser.newPage({ viewport: { width: 1440, height: 900 } })
    await page.goto(`${origin}/index.html?bare=1&appearance=${appearance}&deterministic=1#/${encodeURIComponent(screen.name)}`)
    await page.waitForSelector('html[data-ready]', { timeout: 20000 })
    const ready = await page.evaluate(() => document.documentElement.getAttribute('data-ready'))
    const findings = ready === 'true' ? await runFamily2c((source) => page.evaluate(source), { stackBelow: 640 }) : [{ rule: 'load', detail: `data-ready=${ready}` }]
    frameCount += 1
    findingCount += findings.length
    console.log(`family-2c ${screen.name} ${appearance}: ${findings.length} findings`)
    for (const finding of findings) console.log(`  ${JSON.stringify(finding)}`)
    await page.close()
  }
}
await browser.close()
server.close()
console.log(`family-2c: ${frameCount} frames, ${findingCount} findings`)
if (findingCount > 0) failed = true
process.exit(failed ? 1 : 0)
