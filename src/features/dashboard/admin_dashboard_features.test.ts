import { describe, expect, it } from 'vitest'
import { SECTIONS } from './sections'
import { BUILT_IN_DEFAULT, WIDGETS, WIDGETS_BY_ID } from './registry'
import { normalizeLayout, resolveLayout } from './layout'

describe('Admin Dashboard updates', () => {
  /* הכנסות לשיא עיצובים, שולם, עוד לא שולם ועמלה לקיסר — כרטיס אחד. ה-id
     של האריח הישן נשאר כדי שהכרטיס ייכנס למקום שלו בפריסות שמורות, והגודל
     הראשון הוא פאנל ולא אריח: אריח נשאר בגובהו ליד פאנל ומשאיר שטח ריק. */
  it('merges client share, event payments and the Keisar commission into one panel', () => {
    expect(SECTIONS).toContain('finance.client_share')
    expect(SECTIONS).toContain('finance.keisar_commission')
    const widget = WIDGETS_BY_ID.get('finance.client_share')
    expect(widget).toBeDefined()
    expect(widget?.group).toBe('finance')
    expect(widget?.defaultOn).toBe(true)
    expect(widget?.sections).toEqual(['finance.client_share', 'finance.keisar_commission'])
    expect(widget?.sizes[0]).toBe('lg')
    expect(widget?.sizes).not.toContain('sm')
    for (const retired of [
      'finance.keisar_commission',
      'finance.event_payments_paid',
      'finance.event_payments_unpaid',
    ]) {
      expect(WIDGETS_BY_ID.has(retired), retired).toBe(false)
    }
  })

  it('moves a saved small tile into the merged panel at the same slot', () => {
    const saved = normalizeLayout({
      v: 1,
      items: [
        { id: 'finance.income_mix', size: 'md' },
        { id: 'finance.client_share', size: 'sm' },
        { id: 'finance.event_payments_unpaid', size: 'sm' },
        { id: 'finance.keisar_commission', size: 'sm' },
        { id: 'finance.event_payments_paid', size: 'sm' },
        { id: 'hr.active_and_recent_shifts', size: 'md' },
      ],
      hidden: [],
      seen: WIDGETS.map((w) => w.id),
    })
    const out = resolveLayout(WIDGETS, saved, BUILT_IN_DEFAULT)
    expect(out.map((i) => `${i.id}:${i.size}`)).toEqual([
      'finance.income_mix:md',
      'finance.client_share:lg',
      'hr.active_and_recent_shifts:md',
    ])
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
