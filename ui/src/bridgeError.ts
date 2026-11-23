import type { BridgeErrorCode } from './types'

/** An error the app answered with: a code (see BridgeErrorCode) and a message. */
export class BridgeError extends Error {
  readonly code: BridgeErrorCode | string

  constructor(code: BridgeErrorCode | string, message: string) {
    super(message)
    this.name = 'BridgeError'
    this.code = code
  }
}
