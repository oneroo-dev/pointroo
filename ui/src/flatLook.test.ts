import { describe, expect, it } from 'vitest'
import indexHtml from '../index.html?raw'

describe('flat look', () => {
  it('it_keeps_the_desktop_app_on_the_flat_look', () => {
    const htmlTag = /<html\b[^>]*>/i.exec(indexHtml)?.[0] ?? ''

    expect(htmlTag).toMatch(/\sdata-look="flat"/)
  })
})
