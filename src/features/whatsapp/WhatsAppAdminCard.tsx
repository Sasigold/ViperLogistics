/**
 * עוזר הוואטסאפ (0236) — המבט של מנהל המערכת, בעמוד האינטגרציות.
 *
 * שלוש שאלות: באילו קבוצות הבוט עונה (ולמה לא, כשיש בהן משתתף לא מוכר), מי
 * מחובר, ומה עבר בו לאחרונה — כולל מה שנכשל. כאן אין סודות: הסוד של ה-webhook
 * והמפתחות של Green API הם סודות של פונקציית הקצה (`docs/WHATSAPP.md`).
 */
import { AlertTriangle, ICON, MessageSquarePlus, STROKE, Trash2, Users } from '../../components/ui/icons'
import {
  Badge,
  Button,
  Card,
  CardBody,
  CardHeader,
  EmptyState,
  ErrorState,
  IconButton,
  SkeletonList,
  fmtRelative,
  useConfirm,
  useToast,
} from '../../components/ui'
import { errorMessage } from '../../lib/errors'
import { useAuth } from '../../state/auth'
import type { WaMessageStatus } from '../../types/domain'
import { waPhone } from './whatsapp'
import {
  useUnbindChat,
  useUnlinkWhatsApp,
  useWhatsAppBot,
  useWhatsAppChats,
  useWhatsAppLinks,
  useWhatsAppMessages,
} from './whatsappQueries'

const STATUS: Record<WaMessageStatus, { label: string; tone: 'neutral' | 'success' | 'warning' | 'error' | 'info' }> = {
  received: { label: 'התקבלה', tone: 'neutral' },
  queued: { label: 'בתור', tone: 'info' },
  processing: { label: 'בעבודה', tone: 'info' },
  answered: { label: 'נענתה', tone: 'success' },
  ignored: { label: 'לא טופלה', tone: 'neutral' },
  failed: { label: 'נכשלה', tone: 'error' },
  sent: { label: 'נשלחה', tone: 'success' },
}

export function WhatsAppAdminCard() {
  const admin = useAuth((s) => !!s.me?.profile.is_admin)
  if (!admin) return null
  return <AdminCard />
}

function AdminCard() {
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const { data: bot } = useWhatsAppBot()
  const chats = useWhatsAppChats()
  const links = useWhatsAppLinks()
  const messages = useWhatsAppMessages()
  const unbind = useUnbindChat()
  const unlink = useUnlinkWhatsApp()

  async function offChat(chatId: string, name: string | null) {
    if (!(await confirm(`הבוט יפסיק לענות בקבוצה ${name ?? ''}. אפשר להפעיל שוב מתוך הקבוצה ("הפעל כאן").`, {
      title: 'לנתק את הקבוצה?',
      confirmLabel: 'ניתוק',
    }))) return
    unbind.mutate(chatId, { onError: (e) => toast.error(errorMessage(e)) })
  }

  async function offLink(id: string, name: string) {
    if (!(await confirm(`הבוט יפסיק לענות ל${name} בוואטסאפ.`, { title: 'לנתק את המספר?', confirmLabel: 'ניתוק' }))) return
    unlink.mutate(id, { onError: (e) => toast.error(errorMessage(e)) })
  }

  const active = (chats.data ?? []).filter((c) => c.active)

  return (
    <Card>
      <CardHeader
        title="וואטסאפ"
        subtitle={
          bot?.wid
            ? `העוזר עונה דרך המספר ${waPhone(bot.wid)} · כל אחד בהרשאות שלו, וכל שינוי אחרי "כן"`
            : 'העוזר עוד לא קיבל אף הודעה (ראו docs/WHATSAPP.md להתקנה)'
        }
        icon={<MessageSquarePlus size={ICON.md} strokeWidth={STROKE} />}
      />
      <CardBody className="space-y-5">
        <section className="space-y-2">
          <h3 className="type-subtitle">קבוצות</h3>
          {chats.isLoading && <SkeletonList rows={1} />}
          {chats.error && <ErrorState error={chats.error} onRetry={() => void chats.refetch()} />}
          {!chats.isLoading && !chats.error && active.length === 0 && (
            <p className="type-caption text-ink-tertiary">
              אין קבוצה מחוברת. מנהל מערכת מחובר כותב בקבוצה "הפעל כאן", והבוט מתחיל לענות בה.
            </p>
          )}
          {active.length > 0 && (
            <ul className="divide-y divide-line-subtle rounded-lg border border-line-subtle">
              {active.map((c) => (
                <li key={c.chat_id} className="flex items-center gap-2 px-3 py-2.5">
                  <Users size={ICON.sm} strokeWidth={STROKE} aria-hidden className="shrink-0 text-ink-tertiary" />
                  <div className="min-w-0 flex-1">
                    <p className="truncate type-body">{c.name ?? 'קבוצה'}</p>
                    <p className="type-caption text-ink-tertiary">
                      חוברה {fmtRelative(c.bound_at)}
                      {c.bound_by_profile?.full_name ? ` · בידי ${c.bound_by_profile.full_name}` : ''}
                    </p>
                  </div>
                  {c.participants_ok ? (
                    <Badge tone="success">עונה</Badge>
                  ) : (
                    <Badge tone="warning">
                      <AlertTriangle size={ICON.xs} strokeWidth={STROKE} aria-hidden /> משתתף לא מקושר
                    </Badge>
                  )}
                  <Button size="sm" variant="ghost" onClick={() => void offChat(c.chat_id, c.name)}>
                    ניתוק
                  </Button>
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="space-y-2">
          <h3 className="type-subtitle">מי מחובר</h3>
          {links.isLoading && <SkeletonList rows={2} />}
          {links.error && <ErrorState error={links.error} onRetry={() => void links.refetch()} />}
          {!links.isLoading && !links.error && (links.data ?? []).length === 0 && (
            <p className="type-caption text-ink-tertiary">
              אף אחד עוד לא חיבר וואטסאפ. כל משתמש עם ההרשאה "עוזר וואטסאפ" מתחבר בעמוד "התראות".
            </p>
          )}
          {(links.data ?? []).length > 0 && (
            <ul className="divide-y divide-line-subtle rounded-lg border border-line-subtle">
              {(links.data ?? []).map((l) => (
                <li key={l.id} className="flex items-center gap-2 px-3 py-2.5">
                  <div className="min-w-0 flex-1">
                    <p className="truncate type-body">{l.profiles?.full_name ?? '—'}</p>
                    <p className="type-caption text-ink-tertiary">
                      <span dir="ltr">{waPhone(l.wa_id)}</span> · מאז {fmtRelative(l.linked_at)}
                    </p>
                  </div>
                  <IconButton label="ניתוק המספר" size="sm" onClick={() => void offLink(l.id, l.profiles?.full_name ?? '')}>
                    <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                  </IconButton>
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="space-y-2">
          <h3 className="type-subtitle">הודעות אחרונות</h3>
          {messages.isLoading && <SkeletonList rows={3} />}
          {messages.error && <ErrorState error={messages.error} onRetry={() => void messages.refetch()} />}
          {!messages.isLoading && !messages.error && (messages.data ?? []).length === 0 && (
            <EmptyState art="box" title="עוד לא עברו הודעות" description="כל הודעה לבוט ומהבוט תופיע כאן, עם מה שקרה בה." />
          )}
          {(messages.data ?? []).length > 0 && (
            <ul className="divide-y divide-line-subtle rounded-lg border border-line-subtle">
              {(messages.data ?? []).map((m) => (
                <li key={m.id} className="space-y-0.5 px-3 py-2">
                  <div className="flex items-center gap-2">
                    <span className="type-caption text-ink-tertiary">
                      {m.direction === 'in' ? `← ${m.profiles?.full_name ?? 'לא מקושר'}` : '→ הבוט'} · {fmtRelative(m.created_at)}
                    </span>
                    <Badge tone={STATUS[m.status]?.tone ?? 'neutral'}>{STATUS[m.status]?.label ?? m.status}</Badge>
                  </div>
                  {m.body && <p className="line-clamp-3 whitespace-pre-line type-body">{m.body}</p>}
                  {m.error && <p className="type-caption text-error-text">{m.error}</p>}
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="space-y-1 rounded-lg bg-subtle/60 px-3 py-2.5 type-caption text-ink-secondary">
          <p className="font-semibold">הפקודות</p>
          <p>"קוד 123456" — בצ'אט פרטי עם הבוט, מחבר את המספר שלך (את הקוד מקבלים בעמוד "התראות").</p>
          <p>"הפעל כאן" / "כבה כאן" — בקבוצה, בידי מנהל מערכת מחובר. הבוט עונה בקבוצה רק כשכל המשתתפים בה מקושרים.</p>
          <p>"כן" / "לא" — אישור או ביטול של שינוי שהבוט הציג (בתוקף 15 דקות).</p>
        </section>
      </CardBody>
      {dialog}
    </Card>
  )
}
