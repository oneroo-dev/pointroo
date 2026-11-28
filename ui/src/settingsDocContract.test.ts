// The settings doc contract (T9): every key in WebBridge.allowedSettings is named in the "Settings keys" doc comment, every key
// named there is allowed, and every key is in the page's SettingKey type. Reads the Swift and TS files as plain text.
import { describe, expect, it } from 'vitest'

import webBridgeSource from '../../Sources/PointAndYap/WebBridge.swift?raw'
import typesSource from './types.ts?raw'

function allowedKeys(): string[] {
  const start = webBridgeSource.indexOf('static let allowedSettings')
  if (start < 0) throw new Error('Could not find allowedSettings in WebBridge.swift')
  const end = webBridgeSource.indexOf('\n    ]', start)
  const body = webBridgeSource.slice(start, end)
  return [...body.matchAll(/^\s*\("([A-Za-z]+)",/gm)].map((match) => match[1] ?? '')
}

/** The doc comment from "Settings keys:" up to the class line. */
function docComment(): string {
  const start = webBridgeSource.indexOf('/// Settings keys:')
  const end = webBridgeSource.indexOf('final class WebBridge', start)
  if (start < 0 || end < 0) throw new Error('Could not find the Settings keys doc comment in WebBridge.swift')
  return webBridgeSource.slice(start, end)
}

/** Names the doc comment gives as keys: a camelCase word followed by a comma, a colon-free list end, a bracket or a paren. */
function documentedKeys(keys: string[]): string[] {
  const text = docComment()
  return keys.filter((key) => new RegExp(`\\b${key}\\b`).test(text))
}

function typeKeys(): string[] {
  const start = typesSource.indexOf('export type SettingKey')
  const end = typesSource.indexOf('export type SettingValue', start)
  if (start < 0 || end < 0) throw new Error('Could not find SettingKey in types.ts')
  const body = typesSource.slice(start, end)
  const literals = [...body.matchAll(/'([A-Za-z]+)'/g)].map((match) => match[1] ?? '')
  const choiceKeys = (/AutoStartChoiceKey\s*=\s*([^\n]*)/.exec(typesSource)?.[1] ?? '').match(/'([A-Za-z]+)'/g) ?? []
  const spread = body.includes('AutoStartChoiceKey') ? choiceKeys.map((item) => item.replaceAll("'", '')) : []
  return [...literals, ...spread]
}

describe('settings doc contract', () => {
  const keys = allowedKeys()

  it('it_finds_the_allowed_settings', () => {
    expect(keys.length).toBeGreaterThan(10)
  })

  it('it_names_every_allowed_key_in_the_settings_keys_doc_comment', () => {
    expect(documentedKeys(keys).sort()).toEqual([...keys].sort())
  })

  it('it_allows_every_key_the_doc_comment_lists_in_its_first_lines', () => {
    const text = docComment()
    const flagList = /Settings keys:\s*([^(]*)\(all bool/.exec(text)?.[1] ?? ''
    const flags = flagList.split(',').map((word) => word.trim()).filter((word) => word !== '')
    const autoStart = [...text.matchAll(/\b(autoStart[A-Za-z]+)\b/g)].map((match) => match[1] ?? '')
    const listed = [...flags, 'locale', ...autoStart]
    expect(flags.length).toBeGreaterThan(5)
    for (const word of listed) expect(keys, `${word} is in the doc comment`).toContain(word)
  })

  it('it_has_every_allowed_key_in_the_setting_key_type', () => {
    const known = typeKeys()
    for (const key of keys) expect(known, `${key} in SettingKey`).toContain(key)
    for (const key of known) expect(keys, `${key} in allowedSettings`).toContain(key)
  })
})
