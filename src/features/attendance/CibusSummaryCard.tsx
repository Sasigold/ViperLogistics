import { useState } from 'react'
import { AlertTriangle, Check, ChevronLeft, ICON, Receipt, STROKE } from '../../components/ui/icons'
import { Badge, Card, Select, cx, useToast } from '../../components/ui'
import { useStaff } from '../../lib/queries'
import { errorMessage } from '../../lib/errors'
import { fmtDateTime } from '../../lib/dates'
import { cibusCount, cibusDate, cibusTime, fmtCibusAmount } from './cibus'
import { useCibusLink } from './cibusQueries'
import type { CibusReport, CibusTransaction } from '../../types/domain'

/**
 * צימוד עובד סיבוס לעובד במערכת. נשמר בשרת ונזכר בייבוא הבא, וחל מיד על
 * כל המשיכות שלו — גם אלה שכבר יובאו.
 */
export function CibusLinkRow({ linkKey, name, hint }: { linkKey: string; name: string; hint?: string }) {
  const toast = useToast()
  const { data: staff = [] } = useStaff()
  const link = useCibusLink()
  const [value, setValue] = useState('')

  return (
    <div className="flex flex-wrap items-center gap-2 rounded-lg border border-line-subtle px-3 py-2">
      <div className="min-w-32 flex-1">
        <p className="type-body font-semibold">{name}</p>
        {hint && <p className="type-caption text-ink-tertiary">{hint}</p>}
      </div>
      <div className="w-52">
        <Select
          selectSize="sm"
          value={value}
          disabled={link.isPending}
          onChange={(e) => {
            const id = e.target.value
            setValue(id)
            if (!id) return
            link.mutate(
              { linkKey, profileId: id },
              {
                onSuccess: () => toast.success(`${name} צומד`),
                onError: (err) => {
                  setValue('')
                  toast.error(errorMessage(err))
                },
              },
            )
          }}
        >
          <option value="">בחירת עובד…</option>
          {staff.map((p) => (
            <option key={p.id} value={p.id}>
              {p.full_name}
            </option>
          ))}
        </Select>
      </div>
      {link.isSuccess && value && <Check size={ICON.md} strokeWidth={STROKE} className="text-success" aria-label="צומד" />}
    </div>
  )
}

function TxnList({ list }: { list: CibusTransaction[] }) {
  return (
    <ul className="divide-y divide-line-subtle rounded-lg border border-line-subtle">
      {list.map((t) => (
        <li key={t.id} className="flex items-center gap-3 px-3 py-1.5 type-caption">
          <span className="tabular text-ink-secondary" dir="ltr">
            {cibusDate(t.occurred_at)} {cibusTime(t.occurred_at)}
          </span>
          <span className="min-w-0 flex-1 truncate" title={t.merchant ?? undefined}>
            {t.merchant ?? '—'}
          </span>
          {t.deal_type && <span className="hidden text-ink-tertiary sm:inline">{t.deal_type}</span>}
          <span className="tabular font-semibold">{fmtCibusAmount(t.amount)}</span>
        </li>
      ))}
    </ul>
  )
}

/**
 * סיכום הסיבוס של החודש, מתחת לרשימת המשמרות: כמה נמשך, כמה מזה בתוך
 * משמרות, ובעיקר — המשיכות שבהן לא היה דיווח נוכחות, לפי עובד. כל המספרים
 * מגיעים מ-`cibus_report`.
 */
export function CibusSummaryCard({ report }: { report: CibusReport }) {
  const [open, setOpen] = useState<string | null>(null)
  const t = report.totals
  const withUnmatched = report.employees.filter((e) => e.unmatched_count > 0)

  return (
    <Card className="space-y-4 p-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="flex items-center gap-3">
          <span className="flex size-10 shrink-0 items-center justify-center rounded-full bg-accent-50 text-accent-700 dark:bg-accent-950/50 dark:text-accent-300" aria-hidden>
            <Receipt size={ICON.xl} strokeWidth={STROKE} />
          </span>
          <div>
            <p className="type-title">סיבוס החודש</p>
            <p className="flex flex-wrap gap-x-2 type-caption text-ink-secondary">
              <span className="tabular">
                {cibusCount(t.count)} · {fmtCibusAmount(t.amount)}
              </span>
              <span className="text-ink-tertiary" aria-hidden>|</span>
              <span className="tabular text-success-text">
                {t.matched_count} בזמן משמרת · {fmtCibusAmount(t.matched_amount)}
              </span>
              {t.unmatched_count > 0 && (
                <>
                  <span className="text-ink-tertiary" aria-hidden>|</span>
                  <span className="tabular font-semibold text-error-text">
                    {t.unmatched_count} בלי נוכחות · {fmtCibusAmount(t.unmatched_amount)}
                  </span>
                </>
              )}
              {/* ‏0211: מי שלא זוהה לא נבדק מול נוכחות, ולכן אינו חריגה */}
              {t.unlinked_count > 0 && (
                <>
                  <span className="text-ink-tertiary" aria-hidden>|</span>
                  <span className="tabular text-warning-text">
                    {t.unlinked_count} לא זוהו · {fmtCibusAmount(t.unlinked_amount)}
                  </span>
                </>
              )}
            </p>
          </div>
        </div>
        {report.last_import_at && (
          <p className="type-caption text-ink-tertiary">ייבוא אחרון: {fmtDateTime(report.last_import_at)}</p>
        )}
      </div>

      <p className="type-caption text-ink-tertiary">
        משיכה נחשבת "בזמן משמרת" כשהיא בין הכניסה ליציאה, או עד שעה לפני הכניסה או אחרי היציאה. משמרת שנדחתה
        אינה נוכחות.
      </p>

      {withUnmatched.length > 0 && (
        <section className="space-y-2">
          <h4 className="flex items-center gap-2 type-heading">
            <AlertTriangle size={ICON.sm} strokeWidth={STROKE} className="text-error" />
            משיכות ללא דיווח נוכחות
          </h4>
          {withUnmatched.map((e) => {
            const list = report.transactions.filter((x) => x.profile_id === e.profile_id && !x.entry_id)
            const isOpen = open === e.profile_id
            return (
              <div key={e.profile_id} className="space-y-1.5">
                <button
                  type="button"
                  onClick={() => setOpen(isOpen ? null : e.profile_id)}
                  className="flex w-full items-center gap-2 rounded-lg bg-subtle px-3 py-2 text-start hover:bg-subtle/70"
                  aria-expanded={isOpen}
                >
                  <ChevronLeft
                    size={ICON.sm}
                    strokeWidth={STROKE}
                    className={cx('shrink-0 text-ink-tertiary transition-transform', isOpen && '-rotate-90')}
                  />
                  <span className="min-w-0 flex-1 truncate type-body font-semibold">{e.full_name}</span>
                  <Badge tone="error">{cibusCount(e.unmatched_count)}</Badge>
                  <span className="tabular type-body font-semibold">{fmtCibusAmount(e.unmatched_amount)}</span>
                </button>
                {isOpen && <TxnList list={list} />}
              </div>
            )
          })}
        </section>
      )}

      {report.unlinked.length > 0 && (
        <section className="space-y-2">
          <h4 className="type-heading">עובדי סיבוס שלא זוהו</h4>
          <p className="type-caption text-ink-tertiary">
            אי אפשר להצליב את המשיכות שלהם מול נוכחות עד שבוחרים מי הם במערכת.
          </p>
          {report.unlinked.map((u) => (
            <CibusLinkRow
              key={u.link_key}
              linkKey={u.link_key}
              name={u.employee_name}
              hint={`${cibusCount(u.count)} · ${fmtCibusAmount(u.amount)}`}
            />
          ))}
        </section>
      )}
    </Card>
  )
}
