// לולאת הכלים של עוזר הוואטסאפ (0236), טהורה: הקריאה למודל ומריץ הכלים
// מוזרקים, כך ש-vitest מריץ אותה מול תשובות מתוסרטות ובלי רשת.
//
// הכללים של ה-API שהיא מחזיקה:
//   • התשובה של המודל חוזרת אליו כמו שהיא (`content` שלם, כולל בלוקי חשיבה).
//   • כל תוצאות הכלים של סבב נשלחות בהודעה אחת; כלי שנכשל — `is_error`.
//   • הכלים רצים בזה אחר זה, לא במקביל: כלי כתיבה מריץ ניסיון על כל מה
//     שהוכן לפניו באותו סבב, ולכן הסדר חייב להיות קבוע.

export interface TextBlock {
  type: 'text'
  text: string
}

export interface ToolUseBlock {
  type: 'tool_use'
  id: string
  name: string
  input: unknown
}

export type Block = TextBlock | ToolUseBlock | { type: string; [k: string]: unknown }

export interface ModelReply {
  content: Block[]
  stop_reason: string | null
  usage?: {
    input_tokens?: number | null
    output_tokens?: number | null
    cache_read_input_tokens?: number | null
    cache_creation_input_tokens?: number | null
  }
  model?: string
}

export interface Msg {
  role: 'user' | 'assistant'
  content: string | unknown[]
}

export interface ToolOutcome<P> {
  /** מה שחוזר למודל (JSON או טקסט) */
  content: string
  isError?: boolean
  /** פעולות שהוכנו ומחכות לאישור */
  pending?: P[]
}

export interface LoopDeps<P> {
  call(messages: Msg[]): Promise<ModelReply>
  runTool(name: string, input: unknown, pendingSoFar: readonly P[]): Promise<ToolOutcome<P>>
  now(): number
  /** רגע (ms) שאחריו לא פותחים סבב נוסף */
  deadline: number
  maxRounds: number
}

export type LoopStop = 'end' | 'max_rounds' | 'deadline' | 'refusal' | 'max_tokens'

export interface LoopResult<P> {
  text: string
  pending: P[]
  rounds: number
  stop: LoopStop
  tools: string[]
  model: string | null
  usage: { input: number; output: number; cacheRead: number; cacheWrite: number }
}

const textOf = (content: Block[]) =>
  content
    .filter((b): b is TextBlock => b.type === 'text' && typeof (b as TextBlock).text === 'string')
    .map((b) => b.text)
    .join('\n')
    .trim()

export async function runLoop<P>(initial: Msg[], deps: LoopDeps<P>): Promise<LoopResult<P>> {
  const messages: Msg[] = [...initial]
  const pending: P[] = []
  const tools: string[] = []
  const usage = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }
  let model: string | null = null
  let rounds = 0

  const done = (stop: LoopStop, text: string): LoopResult<P> => ({ text, pending, rounds, stop, tools, model, usage })

  while (rounds < deps.maxRounds) {
    if (deps.now() > deps.deadline) return done('deadline', '')
    rounds++
    const reply = await deps.call(messages)
    model = reply.model ?? model
    usage.input += reply.usage?.input_tokens ?? 0
    usage.output += reply.usage?.output_tokens ?? 0
    usage.cacheRead += reply.usage?.cache_read_input_tokens ?? 0
    usage.cacheWrite += reply.usage?.cache_creation_input_tokens ?? 0

    if (reply.stop_reason === 'refusal') return done('refusal', textOf(reply.content))

    messages.push({ role: 'assistant', content: reply.content })

    if (reply.stop_reason === 'pause_turn') continue

    const uses = reply.content.filter((b): b is ToolUseBlock => b.type === 'tool_use')
    if (reply.stop_reason !== 'tool_use' || uses.length === 0) {
      return done(reply.stop_reason === 'max_tokens' ? 'max_tokens' : 'end', textOf(reply.content))
    }

    const results: unknown[] = []
    for (const u of uses) {
      tools.push(u.name)
      let out: ToolOutcome<P>
      try {
        out = await deps.runTool(u.name, u.input, pending)
      } catch (e) {
        out = { content: e instanceof Error && e.message ? e.message : 'the tool failed', isError: true }
      }
      if (out.pending?.length && !out.isError) pending.push(...out.pending)
      results.push({
        type: 'tool_result',
        tool_use_id: u.id,
        content: out.content,
        ...(out.isError ? { is_error: true } : {}),
      })
    }
    messages.push({ role: 'user', content: results })
  }
  return done('max_rounds', '')
}
