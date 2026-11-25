import { describe, expect, it } from 'vitest'
import { VIPER_COLOR, performerColor, performerLabel } from './grouping'

const arco = { id: 'c1', name: 'ארקו', performed_by_enabled: true }
const row = (performed_by: 'viper' | 'arko', customer_id = 'c1') => ({
  customer_id,
  customer_name: 'ארקו',
  customer_color: '#2f8340',
  performed_by,
})

describe('performerLabel', () => {
  it('names the customer on a task it performs itself', () => {
    expect(performerLabel(row('arko'), arco)).toBe('ארקו')
  })
  it('names viper on a task viper performs', () => {
    expect(performerLabel(row('viper'), arco)).toBe('וייפר')
  })
  it('leaves the header alone for anyone who is not a self-performing customer', () => {
    expect(performerLabel(row('arko'), null)).toBeNull()
    expect(performerLabel(row('arko'), { ...arco, performed_by_enabled: false })).toBeNull()
  })
  it('leaves another customer’s task alone', () => {
    expect(performerLabel(row('viper', 'c2'), arco)).toBeNull()
  })
})

describe('performerColor', () => {
  it('keeps the customer’s own colour on a task it performs itself', () => {
    expect(performerColor(row('arko'), arco)).toBe('#2f8340')
  })
  it('paints viper’s tasks in a hue of their own', () => {
    expect(performerColor(row('viper'), arco)).toBe(VIPER_COLOR)
    expect(VIPER_COLOR).not.toBe('#2f8340')
  })
  it('leaves the header’s colour alone for anyone who is not a self-performing customer', () => {
    expect(performerColor(row('viper'), null)).toBeNull()
    expect(performerColor(row('viper'), { ...arco, performed_by_enabled: false })).toBeNull()
  })
  it('leaves another customer’s task alone', () => {
    expect(performerColor(row('viper', 'c2'), arco)).toBeNull()
  })
  it('falls through to the default fill when the customer has no colour', () => {
    expect(performerColor({ ...row('arko'), customer_color: null }, arco)).toBeNull()
  })
})
