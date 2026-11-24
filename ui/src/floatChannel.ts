// What a floating panel tells the app besides bridge calls: how big its content is (0 by 0 = nothing to show, the app hides the
// panel) and "open this item in the main window". The app listens on a second message handler, pointrooFloat. In a browser
// there is no handler and nothing happens.
export type FloatMessage = { kind: 'size'; width: number; height: number } | { kind: 'open'; itemId: string }

interface MessageHandler {
  postMessage(message: unknown): void
}

export function postFloatMessage(message: FloatMessage): void {
  const handlers = (window as unknown as { webkit?: { messageHandlers?: Record<string, MessageHandler | undefined> } }).webkit?.messageHandlers
  handlers?.pointrooFloat?.postMessage(message)
}

/** The route name the app injected before the page loaded, if any. */
export function injectedRoute(): unknown {
  return (window as unknown as { pointrooRoute?: unknown }).pointrooRoute
}
