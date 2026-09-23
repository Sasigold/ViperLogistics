import { describe, expect, it } from 'vitest'
import { performerLabel } from './grouping'

const arco = { id: 'c1', name: 'ארקו', performed_by_enabled: true }
const row = (performed_by: 'viper' | 'arko', customer_id = 'c1') => ({
  customer_id,
  customer_name: 'ארקו',
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
