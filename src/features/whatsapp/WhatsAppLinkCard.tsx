/**
 * "הוואטסאפ שלי" (0236) — חיבור המספר שלי לעוזר הוואטסאפ.
 *
 * הקישור נעשה בקוד חד-פעמי ולא בהקלדת מספר: המשתמש שולח את הקוד לבוט בצ'אט
 * פרטי, ופונקציית הקצה מקשרת את מי ששלח. כך אין מספר להקליד או לאמת, וזה
 * עובד גם אצל מי שוואטסאפ כבר מזהה במזהה החדש (@lid). הקוד בתוקף עשר דקות
 * ונשרף אם נשלח בקבוצה — שם כולם רואים אותו.
 */
import { useEffect, useState } from 'react'
import { Check, Copy, ExternalLink, ICON, MessageSquarePlus, STROKE, Trash2 } from '../../components/ui/icons'
import { Button, Card, CardBody, CardHeader, Skeleton, fmtRelative, useConfirm, useToast } from '../../components/ui'
import { PERM } from '../../lib/permissions'
import { errorMessage } from '../../lib/errors'
import { useAuth } from '../../state/auth'
import type { WaLinkCode } from '../../types/domain'
import { linkMessage, secondsLeft, waMeLink, waPhone } from './whatsapp'
import { useCreateLinkCode, useMyWhatsAppLink, useUnlinkWhatsApp, useWhatsAppBot } from './whatsappQueries'

export function WhatsAppLinkCard() {
  const allowed = useAuth((s) => s.has(PERM.ASSISTANT_WHATSAPP))
  if (!allowed) return null
  return <LinkCard />
}

function LinkCard() {
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const [code, setCode] = useState<WaLinkCode | null>(null)
  const [now, setNow] = useState(() => Date.now())
  const left = code ? secondsLeft(code.expires_at, now) : 0
  const showing = !!code && left > 0

  const { data: link, isLoading } = useMyWhatsAppLink(showing)
  const { data: bot } = useWhatsAppBot()
  const create = useCreateLinkCode()
  const unlink = useUnlinkWhatsApp()

  useEffect(() => {
    if (!showing) return
    const t = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(t)
  }, [showing])

  // התחבר בזמן שהקוד מוצג — הקוד כבר לא נחוץ
  useEffect(() => {
    if (link && code && Date.parse(link.linked_at) >= Date.parse(code.expires_at) - 10 * 60_000) {
      setCode(null)
      toast.success('הוואטסאפ שלך מחובר')
    }
  }, [link, code, toast])

  const botWid = code?.bot?.wid || bot?.wid || null
  const open = code ? waMeLink(botWid, linkMessage(code.code)) : null

  async function newCode() {
    try {
      setCode(await create.mutateAsync())
      setNow(Date.now())
    } catch (e) {
      toast.error(errorMessage(e))
    }
  }

  async function disconnect() {
    if (!link) return
    const ok = await confirm('הבוט יפסיק לענות לך בוואטסאפ, בפרטי ובקבוצות. אפשר להתחבר שוב בכל רגע.', {
      title: 'לנתק את הוואטסאפ?',
      confirmLabel: 'ניתוק',
    })
    if (!ok) return
    unlink.mutate(link.id, {
      onSuccess: () => toast.success('הוואטסאפ נותק'),
      onError: (e) => toast.error(errorMessage(e)),
    })
  }

  return (
    <Card className="max-w-3xl">
      <CardHeader
        title="וואטסאפ"
        subtitle="לשאול את המערכת ולבקש שינויים מתוך וואטסאפ — בהרשאות שלך, וכל שינוי מחכה לאישור שלך"
        icon={<MessageSquarePlus size={ICON.md} strokeWidth={STROKE} />}
      />
      <CardBody className="space-y-3">
        {isLoading ? (
          <Skeleton className="h-10 w-full" />
        ) : link ? (
          <div className="flex flex-wrap items-center gap-2">
            <Check size={ICON.md} strokeWidth={STROKE} className="text-success-text" aria-hidden />
            <p className="min-w-0 flex-1 type-body">
              מחובר: <span dir="ltr">{waPhone(link.wa_id)}</span>
              <span className="type-caption text-ink-tertiary"> · מאז {fmtRelative(link.linked_at)}</span>
            </p>
            <Button size="sm" variant="ghost" onClick={() => void disconnect()} disabled={unlink.isPending}>
              <Trash2 size={ICON.sm} strokeWidth={STROKE} aria-hidden />
              ניתוק
            </Button>
          </div>
        ) : (
          <p className="type-body text-ink-secondary">הוואטסאפ שלך עוד לא מחובר.</p>
        )}

        {showing ? (
          <div className="space-y-2 rounded-lg bg-subtle/60 px-3 py-3">
            <p className="type-body">שלח לבוט, <strong>בצ'אט פרטי</strong> (לא בקבוצה):</p>
            <p className="font-mono tabular-nums type-title" dir="ltr">
              {linkMessage(code!.code)}
            </p>
            <div className="flex flex-wrap items-center gap-2">
              {open && (
                <Button size="sm" variant="primary" onClick={() => window.open(open, '_blank', 'noopener')}>
                  <ExternalLink size={ICON.sm} strokeWidth={STROKE} aria-hidden />
                  פתח בוואטסאפ
                </Button>
              )}
              <Button
                size="sm"
                variant="ghost"
                onClick={() =>
                  void navigator.clipboard
                    ?.writeText(linkMessage(code!.code))
                    .then(() => toast.success('הועתק'))
                    .catch(() => {})
                }
              >
                <Copy size={ICON.sm} strokeWidth={STROKE} aria-hidden />
                העתקה
              </Button>
              <span className="type-caption text-ink-tertiary">
                בתוקף עוד {Math.floor(left / 60)}:{String(left % 60).padStart(2, '0')}
              </span>
            </div>
            {!open && (
              <p className="type-caption text-ink-tertiary">
                המספר של הבוט יופיע כאן אחרי ההודעה הראשונה שהוא מקבל. בינתיים — שלח את הקוד בצ'אט פרטי למספר
                של הבוט (זה המספר שנמצא בקבוצת הוואטסאפ).
              </p>
            )}
          </div>
        ) : (
          <Button size="sm" variant={link ? 'ghost' : 'primary'} onClick={() => void newCode()} disabled={create.isPending}>
            {link ? 'חיבור מספר אחר' : 'חבר את הוואטסאפ שלי'}
          </Button>
        )}

        <p className="type-caption text-ink-tertiary">
          אחרי החיבור אפשר לכתוב לבוט בפרטי, או בקבוצה שמנהל המערכת חיבר ("הפעל כאן"). למשל: "מה יש מחר?", "כמה
          הכנסות החודש?", "תזיז את ההקמה של כהן לשלישי ב-10:00".
        </p>
      </CardBody>
      {dialog}
    </Card>
  )
}
