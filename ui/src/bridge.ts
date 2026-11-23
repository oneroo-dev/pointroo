// The line to the app. `call` sends one request and waits for the reply; `on` listens for what the app tells the page.
// In the real window the app is Swift (window.webkit.messageHandlers.pointroo). In a normal browser there is no
// window.webkit, so the fake bridge answers from sample data and `npm run dev` works.
import { BridgeError } from './bridgeError'
import { createFakeBridge } from './fakeBridge'
import type { BridgeEventName, BridgeEvents, BridgeMethod, BridgeMethods } from './types'

export { BridgeError }

interface ReplyPayload {
  result?: unknown
  error?: { code: string; message: string }
}

export interface Bridge {
  call<Name extends BridgeMethod>(method: Name, params?: BridgeMethods[Name]['params']): Promise<BridgeMethods[Name]['result']>
  on<Name extends BridgeEventName>(name: Name, handler: (data: BridgeEvents[Name]) => void): () => void
}

type Handler = (data: unknown) => void

interface WebKitHandler {
  postMessage(message: unknown): void
}

declare global {
  interface Window {
    webkit?: { messageHandlers?: { pointroo?: WebKitHandler } }
    pointroo?: {
      reply(id: number | string, payload: ReplyPayload): void
      emit(name: string, data: unknown): void
    }
  }
}

function createNativeBridge(handler: WebKitHandler): Bridge {
  let nextId = 1
  const waiting = new Map<number | string, { resolve: (value: unknown) => void; reject: (error: BridgeError) => void }>()
  const listeners = new Map<string, Set<Handler>>()

  window.pointroo = {
    reply(id, payload) {
      const entry = waiting.get(id)
      if (entry === undefined) return
      waiting.delete(id)
      if (payload.error !== undefined) entry.reject(new BridgeError(payload.error.code, payload.error.message))
      else entry.resolve(payload.result)
    },
    emit(name, data) {
      listeners.get(name)?.forEach((listener) => listener(data))
    },
  }

  return {
    call(method, params) {
      const id = nextId
      nextId += 1
      return new Promise((resolve, reject) => {
        waiting.set(id, { resolve: (value) => resolve(value as never), reject })
        try {
          handler.postMessage({ id, method, params: params ?? {} })
        } catch (error) {
          waiting.delete(id)
          reject(new BridgeError('not_available', error instanceof Error ? error.message : 'Could not reach the app.'))
        }
      })
    },
    on(name, listener) {
      const set = listeners.get(name) ?? new Set<Handler>()
      set.add(listener as Handler)
      listeners.set(name, set)
      return () => {
        set.delete(listener as Handler)
      }
    },
  }
}

function pickBridge(): Bridge {
  const handler = window.webkit?.messageHandlers?.pointroo
  return handler === undefined ? createFakeBridge() : createNativeBridge(handler)
}

export const bridge: Bridge = pickBridge()

/** True when the page runs in a plain browser with sample data. */
export const isFake: boolean = window.webkit?.messageHandlers?.pointroo === undefined

export function errorText(error: unknown): string {
  if (error instanceof BridgeError) {
    if (error.code === 'not_available' || error.code === 'unknown_method') return 'Not available yet.'
    return error.message
  }
  return error instanceof Error ? error.message : 'Something went wrong.'
}
