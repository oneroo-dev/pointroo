// The bridge contract (T3): the Swift side (WebBridge.swift) and the page side (types.ts) must name the same methods
// and the same events. The test reads both files as plain text, so a name added on one side only fails here.
import { describe, expect, it } from 'vitest'

import swiftSource from '../../Sources/PointAndYap/WebBridge.swift?raw'
import typesSource from './types.ts?raw'

/** Names that are real on one side only. Each one needs a reason. Empty today. */
const swiftOnlyMethods: Record<string, string> = {}
const typesOnlyMethods: Record<string, string> = {}
const swiftOnlyEvents: Record<string, string> = {}
const typesOnlyEvents: Record<string, string> = {}

/** The text between a start marker and the first end marker after it. Fails loudly when the markers are not found. */
function section(source: string, startPattern: RegExp, endPattern: RegExp, label: string): string {
  const start = startPattern.exec(source)
  if (!start) throw new Error(`Could not find the start of ${label}`)
  const rest = source.slice(start.index + start[0].length)
  const end = endPattern.exec(rest)
  if (!end) throw new Error(`Could not find the end of ${label}`)
  return rest.slice(0, end.index)
}

function collect(text: string, pattern: RegExp): string[] {
  const names: string[] = []
  for (const match of text.matchAll(pattern)) {
    const name = match[1]
    if (name) names.push(name)
  }
  return names
}

/** The method table: lines like `"items.list": { bridge, params in ... },` between `static let methods` and the closing `]`. */
function swiftMethods(): string[] {
  const table = section(swiftSource, /static let methods:\s*\[String:\s*Handler\]\s*=\s*\[/, /^\s*\]/m, 'the Swift method table')
  return collect(table, /^\s*"([A-Za-z]+(?:\.[A-Za-z]+)+)"\s*:\s*\{/gm)
}

/** The events list in the doc comment: lines like `///   items.changed   {count}` between the "Events" line and "Error codes". */
function swiftEvents(): string[] {
  const list = section(swiftSource, /^\/\/\/ Events the app sends[^\n]*\n/m, /^\/\/\/ Error codes:/m, 'the events list in the doc comment')
  return collect(list, /^\/\/\/\s+([a-z]+(?:\.[a-z]+)+)\s+\{/gm)
}

/** The keys of an interface in types.ts: quoted names at the first indent level, like `  'items.list': {...}`. */
function typeKeys(interfaceName: string): string[] {
  const body = section(typesSource, new RegExp(`export interface ${interfaceName} \\{\\n`), /^\}/m, `interface ${interfaceName}`)
  return collect(body, /^ {2}'([A-Za-z]+(?:\.[A-Za-z]+)+)'\s*:/gm)
}

function duplicates(names: string[]): string[] {
  return names.filter((name, index) => names.indexOf(name) !== index)
}

/** Names in `from` that are not in `other` and not on the allow list. */
function missingFrom(from: string[], other: string[], allowed: Record<string, string>): string[] {
  return from.filter((name) => !other.includes(name) && !(name in allowed)).sort()
}

describe('reading the two sides', () => {
  it('it_finds_methods_and_events_on_both_sides', () => {
    expect(swiftMethods().length).toBeGreaterThan(20)
    expect(typeKeys('BridgeMethods').length).toBeGreaterThan(20)
    expect(swiftEvents().length).toBeGreaterThan(5)
    expect(typeKeys('BridgeEvents').length).toBeGreaterThan(5)
  })

  it('it_has_no_duplicate_names_on_either_side', () => {
    expect(duplicates(swiftMethods())).toEqual([])
    expect(duplicates(typeKeys('BridgeMethods'))).toEqual([])
    expect(duplicates(swiftEvents())).toEqual([])
    expect(duplicates(typeKeys('BridgeEvents'))).toEqual([])
  })

  it('it_gives_every_allow_list_entry_a_reason', () => {
    for (const list of [swiftOnlyMethods, typesOnlyMethods, swiftOnlyEvents, typesOnlyEvents]) {
      for (const [name, reason] of Object.entries(list)) {
        expect(reason.trim(), `the allow list entry ${name} needs a reason`).not.toBe('')
      }
    }
  })
})

describe('the methods', () => {
  it('it_serves_every_method_the_page_may_call', () => {
    const missing = missingFrom(typeKeys('BridgeMethods'), swiftMethods(), typesOnlyMethods)
    expect(missing, `In types.ts BridgeMethods but not in the WebBridge.swift method table: ${missing.join(', ')}`).toEqual([])
  })

  it('it_types_every_method_the_app_serves', () => {
    const missing = missingFrom(swiftMethods(), typeKeys('BridgeMethods'), swiftOnlyMethods)
    expect(missing, `In the WebBridge.swift method table but not in types.ts BridgeMethods: ${missing.join(', ')}`).toEqual([])
  })
})

describe('the events', () => {
  it('it_documents_every_event_the_page_listens_for', () => {
    const missing = missingFrom(typeKeys('BridgeEvents'), swiftEvents(), typesOnlyEvents)
    expect(missing, `In types.ts BridgeEvents but not in the WebBridge.swift doc comment events list: ${missing.join(', ')}`).toEqual([])
  })

  it('it_types_every_event_the_app_sends', () => {
    const missing = missingFrom(swiftEvents(), typeKeys('BridgeEvents'), swiftOnlyEvents)
    expect(missing, `In the WebBridge.swift doc comment events list but not in types.ts BridgeEvents: ${missing.join(', ')}`).toEqual([])
  })
})
