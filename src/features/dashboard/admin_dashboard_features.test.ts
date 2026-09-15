import { describe, expect, it } from 'vitest'
import { SECTIONS } from './sections'
import { WIDGETS_BY_ID } from './registry'

describe('Admin Dashboard updates', () => {
  it('registers finance.keisar_commission in SECTIONS and WIDGETS', () => {
    expect(SECTIONS).toContain('finance.keisar_commission')
    const widget = WIDGETS_BY_ID.get('finance.keisar_commission')
    expect(widget).toBeDefined()
    expect(widget?.title).toBe('עמלה לקיסר')
    expect(widget?.group).toBe('finance')
    expect(widget?.sizes).toContain('sm')
    expect(widget?.sections).toEqual(['finance.keisar_commission'])
    expect(widget?.defaultOn).toBe(true)
  })

  it('registers finance.client_share with updated Sia Designs title', () => {
    expect(SECTIONS).toContain('finance.client_share')
    const widget = WIDGETS_BY_ID.get('finance.client_share')
    expect(widget).toBeDefined()
    expect(widget?.title).toBe('הכנסות לשיא עיצובים')
    expect(widget?.group).toBe('finance')
    expect(widget?.sizes).toContain('sm')
    expect(widget?.sections).toEqual(['finance.client_share'])
  })

  it('registers income.mix in SECTIONS for the revenue breakdown chart', () => {
    expect(SECTIONS).toContain('income.mix')
    const widget = WIDGETS_BY_ID.get('finance.income_mix')
    expect(widget).toBeDefined()
    expect(widget?.sections).toEqual(['income.mix'])
  })

  it('calculates 24-hour timeline position correctly', () => {
    const span = 24
    const pos = (time: string) => {
      const [h, m] = time.split(':').map(Number)
      return (((h || 0) + (m || 0) / 60) / span) * 100
    }

    expect(pos('00:00')).toBe(0)
    expect(pos('06:00')).toBe(25)
    expect(pos('12:00')).toBe(50)
    expect(pos('18:00')).toBe(75)
    expect(pos('24:00')).toBe(100)
    expect(pos('12:30')).toBeCloseTo(52.083, 2)
  })
})
