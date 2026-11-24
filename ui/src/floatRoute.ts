// Which floating panel this page is. The app puts the name in window.pointrooRoute before the page loads ("pill", "picker" or
// "notice"); a browser can use the address instead (#/float/pill). Anything else is the main window.
export type FloatRoute = 'pill' | 'picker' | 'notice'

const routes: readonly FloatRoute[] = ['pill', 'picker', 'notice']
const hashPrefix = '#/float/'

function asRoute(text: string): FloatRoute | undefined {
  return routes.find((route) => route === text)
}

export function floatRouteFrom(injected: unknown, hash: string): FloatRoute | undefined {
  if (typeof injected === 'string') {
    const route = asRoute(injected)
    if (route !== undefined) return route
  }
  return hash.startsWith(hashPrefix) ? asRoute(hash.slice(hashPrefix.length)) : undefined
}
