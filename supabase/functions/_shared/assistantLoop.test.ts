import { describe, expect, it } from 'vitest'
import { runLoop } from './assistantLoop'
import type { ModelReply, Msg } from './assistantLoop'

const text = (t: string): ModelReply => ({ content: [{ type: 'text', text: t }], stop_reason: 'end_turn', usage: { input_tokens: 10, output_tokens: 2 } })
const uses = (...calls: [string, string, unknown][]): ModelReply => ({
  content: [
    { type: 'thinking', thinking: '', signature: 'sig' },
    ...calls.map(([id, name, input]) => ({ type: 'tool_use', id, name, input })),
  ],
  stop_reason: 'tool_use',
  usage: { input_tokens: 100, output_tokens: 20, cache_read_input_tokens: 80 },
})

function script(replies: ModelReply[]) {
  const seen: Msg[][] = []
  return {
    seen,
    call: async (messages: Msg[]) => {
      seen.push(structuredClone(messages))
      const r = replies.shift()
      if (!r) throw new Error('no more replies')
      return r
    },
  }
}

const base = { now: () => 0, deadline: 1, maxRounds: 8 }

describe('runLoop', () => {
  it('answers without tools', async () => {
    const s = script([text('שלום')])
    const r = await runLoop([{ role: 'user', content: 'היי' }], { ...base, call: s.call, runTool: async () => ({ content: '' }) })
    expect(r).toMatchObject({ text: 'שלום', stop: 'end', rounds: 1, pending: [] })
  })

  it('runs every tool of a round in order and sends all results in one message', async () => {
    const s = script([
      uses(['t1', 'find_events', { query: 'כהן' }], ['t2', 'schedule', { period: 'tomorrow' }]),
      text('מצאתי'),
    ])
    const order: string[] = []
    const r = await runLoop([{ role: 'user', content: 'x' }], {
      ...base,
      call: s.call,
      runTool: async (name) => {
        order.push(name)
        return { content: `{"tool":"${name}"}` }
      },
    })
    expect(order).toEqual(['find_events', 'schedule'])
    expect(r.tools).toEqual(['find_events', 'schedule'])
    const second = s.seen[1]
    // התשובה של המודל חזרה אליו כמו שהיא, כולל בלוק החשיבה
    expect(second[1]).toEqual({ role: 'assistant', content: uses(['t1', 'find_events', { query: 'כהן' }], ['t2', 'schedule', { period: 'tomorrow' }]).content })
    expect(second[2]).toEqual({
      role: 'user',
      content: [
        { type: 'tool_result', tool_use_id: 't1', content: '{"tool":"find_events"}' },
        { type: 'tool_result', tool_use_id: 't2', content: '{"tool":"schedule"}' },
      ],
    })
    expect(r.usage).toEqual({ input: 110, output: 22, cacheRead: 80, cacheWrite: 0 })
  })

  it('turns a thrown tool into is_error and keeps going', async () => {
    const s = script([uses(['t1', 'event_details', {}]), text('לא מצאתי')])
    const r = await runLoop([{ role: 'user', content: 'x' }], {
      ...base,
      call: s.call,
      runTool: async () => {
        throw new Error('event_id is required')
      },
    })
    expect(s.seen[1][2]).toEqual({
      role: 'user',
      content: [{ type: 'tool_result', tool_use_id: 't1', content: 'event_id is required', is_error: true }],
    })
    expect(r.text).toBe('לא מצאתי')
  })

  it('collects prepared changes and shows each tool what came before it', async () => {
    const s = script([
      uses(['a', 'reschedule_task', { task_id: '1' }], ['b', 'reschedule_task', { task_id: '2' }]),
      uses(['c', 'add_event_note', {}]),
      text(''),
    ])
    const sawBefore: number[] = []
    const r = await runLoop<{ op: string }>([{ role: 'user', content: 'x' }], {
      ...base,
      call: s.call,
      runTool: async (name, _input, before) => {
        sawBefore.push(before.length)
        if (name === 'add_event_note') return { content: 'bad', isError: true, pending: [{ op: 'ignored' }] }
        return { content: 'ok', pending: [{ op: name }] }
      },
    })
    expect(sawBefore).toEqual([0, 1, 2])
    expect(r.pending).toEqual([{ op: 'reschedule_task' }, { op: 'reschedule_task' }])
    expect(r.stop).toBe('end')
  })

  it('stops at the round limit and at the deadline', async () => {
    const forever = () => uses(['x', 'schedule', {}])
    const s = script([forever(), forever(), forever()])
    const r = await runLoop([{ role: 'user', content: 'x' }], { ...base, maxRounds: 2, call: s.call, runTool: async () => ({ content: '' }) })
    expect(r.stop).toBe('max_rounds')
    expect(r.rounds).toBe(2)

    let t = 0
    const s2 = script([forever(), forever()])
    const r2 = await runLoop([{ role: 'user', content: 'x' }], {
      now: () => t,
      deadline: 5,
      maxRounds: 8,
      call: async (m) => {
        t += 10
        return s2.call(m)
      },
      runTool: async () => ({ content: '' }),
    })
    expect(r2.stop).toBe('deadline')
    expect(r2.rounds).toBe(1)
  })

  it('reports a refusal and a cut-off answer', async () => {
    const s = script([{ content: [], stop_reason: 'refusal' }])
    expect((await runLoop([{ role: 'user', content: 'x' }], { ...base, call: s.call, runTool: async () => ({ content: '' }) })).stop)
      .toBe('refusal')
    const s2 = script([{ content: [{ type: 'text', text: 'חלקי' }], stop_reason: 'max_tokens' }])
    const r2 = await runLoop([{ role: 'user', content: 'x' }], { ...base, call: s2.call, runTool: async () => ({ content: '' }) })
    expect(r2).toMatchObject({ stop: 'max_tokens', text: 'חלקי' })
  })
})
