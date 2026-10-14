import { describe, expect, it } from 'vitest'
import { ilikeAny } from './search'

describe('ilikeAny', () => {
  it('quotes each value so commas and brackets are plain text', () => {
    expect(ilikeAny(['a', 'b'], 'הרצל, תל אביב (2)')).toBe('a.ilike."%הרצל, תל אביב (2)%",b.ilike."%הרצל, תל אביב (2)%"')
  })
  it('drops double quotes and backslashes', () => {
    expect(ilikeAny(['a'], 'x"y\\z')).toBe('a.ilike."%x y z%"')
  })
  it('returns null for blank input', () => {
    expect(ilikeAny(['a'], '   ')).toBeNull()
    expect(ilikeAny(['a'], '"')).toBeNull()
  })
})
