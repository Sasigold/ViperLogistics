import { describe, expect, it } from 'vitest'
import { linkMessage, secondsLeft, waMeLink, waPhone } from './whatsapp'

describe('waPhone', () => {
  it('writes an Israeli number the local way', () => {
    expect(waPhone('972501234567@c.us')).toBe('0501234567')
    expect(waPhone('97231234567@c.us')).toBe('031234567')
  })

  it('keeps others recognisable', () => {
    expect(waPhone('14155550100@c.us')).toBe('+14155550100')
    expect(waPhone('123456789012345@lid')).toBe('123456789012345@lid')
    expect(waPhone(null)).toBe('')
  })
})

describe('waMeLink', () => {
  it('opens a private chat with the code ready to send', () => {
    expect(waMeLink('972500000999@c.us', linkMessage('123456'))).toBe(
      'https://wa.me/972500000999?text=%D7%A7%D7%95%D7%93%20123456',
    )
  })

  it('is null while the bot number is unknown', () => {
    expect(waMeLink(undefined, 'x')).toBeNull()
    expect(waMeLink('120363000000000099@g.us', 'x')).toBeNull()
  })
})

describe('secondsLeft', () => {
  it('counts down and stops at zero', () => {
    const now = Date.parse('2026-10-25T09:00:00Z')
    expect(secondsLeft('2026-10-25T09:10:00Z', now)).toBe(600)
    expect(secondsLeft('2026-10-25T08:59:00Z', now)).toBe(0)
  })
})
