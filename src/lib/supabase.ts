import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string

if (!url || !anonKey) {
  console.warn('חסרים משתני סביבה VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY')
}

export const supabase = createClient(url, anonKey)

export async function invokeFunction<T>(name: string, body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke(name, { body })
  if (error) {
    // supabase-js wraps non-2xx as FunctionsHttpError with the response attached
    const ctx = (error as { context?: Response }).context
    if (ctx) {
      const parsed = await ctx.json().catch(() => null)
      if (parsed?.error) throw new Error(parsed.error)
    }
    throw error
  }
  if ((data as { error?: string })?.error) throw new Error((data as { error: string }).error)
  return data as T
}
