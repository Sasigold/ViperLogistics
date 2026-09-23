/**
 * פופאפ עריכת האירוע, לבדו — להטמעה ב-iframe במערכת של הלקוח (ארקו).
 *
 * ‏`/embed/event?order=<מספר אירוע>` או `?id=<מזהה>`. מחוץ ל-AppLayout: אין
 * תפריט, אין כותרת — רק המודאל, כי זה כל מה שהמסגרת אצלו אמורה להראות.
 * הכניסה היא הכניסה הרגילה (משתמש הלקוח שלו), וה-RLS היא שמכריעה איזה
 * אירוע הוא רואה: מספר של אירוע של לקוח אחר פשוט אינו נמצא.
 *
 * הדף המארח שומע מה קרה דרך `postMessage` — `viper:event-saved` אחרי שמירה
 * ו-`viper:event-closed` כשהטופס נסגר בלי שמירה — כדי שיוכל לסגור את המסגרת
 * או לרענן את המסך שלו. בהודעה רק מזהה ומספר אירוע, ולכן `*` כיעד.
 */
import { useRef, useState } from 'react'
import { useSearchParams } from 'react-router'
import { useQuery } from '@tanstack/react-query'
import { Button, Card, EmptyState, Spinner } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { errorMessage } from '../../lib/errors'
import { PERM } from '../../lib/permissions'
import { useAuth } from '../../state/auth'
import { EventFormModal } from '../events/EventFormModal'
import type { EventRow } from '../../types/domain'

type EmbedMessage = { type: 'viper:event-saved' | 'viper:event-closed'; event_id: string; order_number: string | null }

function notifyHost(msg: EmbedMessage) {
  /* נפתח ישירות ולא במסגרת — אין למי לספר */
  if (window.parent === window) return
  window.parent.postMessage({ source: 'viper', ...msg }, '*')
}

export default function EmbedEventPage() {
  const { has } = useAuth()
  const [params] = useSearchParams()
  const id = params.get('id')?.trim() || null
  const order = params.get('order')?.trim() || null
  const [open, setOpen] = useState(true)
  /* השמירה סוגרת את הטופס בעצמה; הסגירה שאחריה אינה "נסגר בלי שמירה" */
  const saved = useRef(false)

  const { data, isLoading, error, refetch } = useQuery({
    queryKey: ['events', 'embed', id, order],
    enabled: !!(id || order),
    queryFn: async () => {
      let q = supabase.from('events').select('*, customers(name, color, performed_by_enabled, quote_enabled)')
      q = id ? q.eq('id', id) : q.eq('event_number', order!)
      /* שניים ולא אחד: מספר שחוזר בשני אירועים הוא שאלה, לא בחירה */
      const { data: rows, error: e } = await q.is('deleted_at', null).limit(2)
      if (e) throw e
      if (!rows || rows.length === 0) return null
      if (rows.length > 1) throw new Error(`נמצא יותר מאירוע אחד במספר ${order}`)
      const event = rows[0] as EventRow
      const [contact, sup] = await Promise.all([
        supabase.from('event_contacts').select('contact_name, contact_phone').eq('event_id', event.id).maybeSingle(),
        supabase.from('event_suppliers').select('supplier_id').eq('event_id', event.id),
      ])
      return {
        event,
        contact: contact.data as { contact_name: string | null; contact_phone: string | null } | null,
        supplierIds: (sup.data ?? []).map((s) => s.supplier_id as string),
      }
    },
  })

  const shell = (node: React.ReactNode) => (
    <div className="flex min-h-dvh items-center justify-center bg-canvas p-4">
      <Card className="w-full max-w-md">{node}</Card>
    </div>
  )

  if (!has(PERM.EVENTS_EDIT))
    return shell(<EmptyState art="alert" title="אין הרשאה" description="למשתמש הזה אין הרשאה לערוך אירועים." />)
  if (!id && !order)
    return shell(<EmptyState art="alert" title="חסר מספר אירוע" description="הכתובת צריכה לכלול ?order=<מספר אירוע>" />)
  if (isLoading) return <Spinner full />
  if (error) return shell(<EmptyState art="alert" title="לא הצלחנו לטעון את האירוע" description={errorMessage(error)} />)
  if (!data)
    return shell(
      <EmptyState art="alert" title="האירוע לא נמצא" description={`אין אירוע ${order ?? id} שפתוח לעריכה במשתמש הזה.`} />,
    )

  const { event } = data
  const base = { event_id: event.id, order_number: event.event_number ?? null }

  return (
    <div className="min-h-dvh bg-canvas">
      {!open &&
        shell(
          <EmptyState
            title="הטופס נסגר"
            description={event.event_number ? `אירוע ${event.event_number}` : undefined}
            action={
              <Button variant="primary" size="sm" onClick={() => void refetch().then(() => setOpen(true))}>
                פתיחה מחדש
              </Button>
            }
          />,
        )}
      <EventFormModal
        open={open}
        event={event}
        contact={data.contact}
        supplierIds={data.supplierIds}
        onSaved={() => {
          saved.current = true
          notifyHost({ type: 'viper:event-saved', ...base })
        }}
        onClose={() => {
          setOpen(false)
          if (!saved.current) notifyHost({ type: 'viper:event-closed', ...base })
          saved.current = false
        }}
      />
    </div>
  )
}
