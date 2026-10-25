// סבב אחד מול Claude (0236): ההנחיה והכלים הקבועים במטמון, ההקשר המשתנה
// (עכשיו, מי, מה ממתין) בתוך ההודעה — כך שהקידומת זהה מהודעה להודעה.

import Anthropic from 'npm:@anthropic-ai/sdk@0.129.0'
import { apiTool, ASSISTANT_MODEL, MAX_ROUNDS, SYSTEM_PROMPT, toolsFor } from '../_shared/assistant.ts'
import { runLoop } from '../_shared/assistantLoop.ts'
import type { LoopResult, ModelReply, Msg } from '../_shared/assistantLoop.ts'
import { runTool } from './tools.ts'
import type { PendingOp, ToolCtx } from './tools.ts'

export interface TurnInput {
  ctx: ToolCtx
  caps: Record<string, boolean>
  history: Msg[]
  /** ההקשר (contextBlock) והטקסט של המשתמש */
  context: string
  userText: string
  /** רגע (ms) שאחריו לא פותחים סבב נוסף */
  deadline: number
}

const EFFORTS = ['low', 'medium', 'high'] as const
type Effort = (typeof EFFORTS)[number]

export async function runTurn(input: TurnInput): Promise<LoopResult<PendingOp>> {
  const model = Deno.env.get('ASSISTANT_MODEL') || ASSISTANT_MODEL
  const envEffort = Deno.env.get('ASSISTANT_EFFORT') as Effort | undefined
  const effort: Effort = envEffort && EFFORTS.includes(envEffort) ? envEffort : 'medium'
  // בלי streaming, עם גבול זמן לכל קריאה: תשובה בוואטסאפ קצרה, וקריאה תקועה
  // צריכה להיכשל בתוך זמן הפונקציה ולא אחריו.
  const client = new Anthropic({ apiKey: input.ctx.anthropicKey, maxRetries: 1, timeout: 45_000 })

  const defs = toolsFor(input.caps, input.ctx.isAdmin)
  input.ctx.offered = new Set(defs.map((d) => d.name))
  const tools = defs.map(apiTool)

  const messages: Msg[] = [...input.history, { role: 'user', content: `${input.context}\n\n${input.userText}` }]

  return await runLoop<PendingOp>(messages, {
    call: async (m) => {
      const reply = await client.beta.messages.create({
        model,
        max_tokens: 8000,
        // סירוב של מסווג בטיחות אינו צפוי כאן, אבל אם קורה — השרת מנסה שוב
        // על מודל חלופי באותה קריאה (כמו invoice-read).
        betas: ['server-side-fallback-2026-07-01'],
        fallbacks: 'default',
        output_config: { effort },
        system: [{ type: 'text', text: SYSTEM_PROMPT, cache_control: { type: 'ephemeral' } }],
        tools,
        messages: m as Anthropic.Beta.BetaMessageParam[],
      })
      return reply as unknown as ModelReply
    },
    runTool: (name, args, before) => runTool(input.ctx, name, args, before),
    now: () => Date.now(),
    deadline: input.deadline,
    maxRounds: MAX_ROUNDS,
  })
}

/** שורה בעברית למשתמש; השגיאה המלאה ליומן של הפונקציה */
export function aiError(e: unknown): string {
  if (e instanceof Anthropic.AuthenticationError) return 'מפתח ה-API של Anthropic אינו תקין'
  if (e instanceof Anthropic.RateLimitError) return 'יש עומס על שירות ה-AI — נסה שוב בעוד דקה'
  if (e instanceof Anthropic.APIConnectionError) return 'אין חיבור לשירות ה-AI — נסה שוב בעוד רגע'
  if (e instanceof Anthropic.APIError) return `שגיאה בשירות ה-AI (${e.status ?? '?'})`
  return 'משהו השתבש'
}
