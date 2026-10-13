import { useState } from 'react'
import { Download, Eye, ICON, Receipt, STROKE } from '../../components/ui/icons'
import { Button, Card, CardBody, EmptyState, ErrorState, PageHeader, SkeletonList, useToast } from '../../components/ui'
import { useAuth } from '../../state/auth'
import { errorMessage } from '../../lib/errors'
import { fmtDate } from '../../lib/dates'
import type { MyPayslip } from '../../types/domain'
import { groupByPeriod, periodLabel, slipFileName } from './payslips'
import { downloadSlip, openSlip, useMyPayslips } from './payslipQueries'

/**
 * התלושים של העובד (0218). כל חודש — התלוש (או התלושים, כשיש תלוש מתקן)
 * ששויך אליו, לצפייה ולהורדה. בלי שום סכום שהמערכת חישבה: התלוש עצמו הוא
 * המסמך.
 */
export default function MyPayslipsPage() {
  const toast = useToast()
  const name = useAuth((s) => s.me?.profile.full_name ?? null)
  const { data = [], isLoading, error, refetch } = useMyPayslips()
  const [busy, setBusy] = useState<string | null>(null)

  const act = async (s: MyPayslip, kind: 'view' | 'download') => {
    setBusy(`${kind}:${s.id}`)
    try {
      if (kind === 'view') await openSlip(s.batch_id, s.page_from, s.page_to)
      else await downloadSlip(s.batch_id, s.page_from, s.page_to, slipFileName(s.period, name))
    } catch (e) {
      toast.error(errorMessage(e))
    } finally {
      setBusy(null)
    }
  }

  const groups = groupByPeriod(data)

  return (
    <div className="space-y-4">
      <PageHeader title="תלושי השכר שלי" subtitle="כל תלוש ששויך אליך — לצפייה ולהורדה" />

      {error && <ErrorState error={error} onRetry={() => void refetch()} />}
      {isLoading && (
        <Card>
          <CardBody>
            <SkeletonList rows={4} />
          </CardBody>
        </Card>
      )}

      {!isLoading && !error && groups.length === 0 && (
        <EmptyState
          art="box"
          title="עוד אין תלושים"
          description="כשהמשרד ישייך אליך תלוש שכר הוא יופיע כאן, ותקבל על כך התראה"
        />
      )}

      {groups.length > 0 && (
        <Card>
          <CardBody>
            <ul className="divide-y divide-line-subtle">
              {groups.flatMap((g) =>
                g.slips.map((s, i) => (
                  <li key={s.id} className="flex flex-wrap items-center gap-3 py-3">
                    <span className="grid size-10 shrink-0 place-items-center rounded-xl bg-primary-subtle text-primary-text">
                      <Receipt size={ICON.lg} strokeWidth={STROKE} />
                    </span>
                    <div className="min-w-32 flex-1">
                      <p className="type-title">
                        {periodLabel(g.period)}
                        {g.slips.length > 1 && ` · תלוש ${i + 1}`}
                      </p>
                      {s.assigned_at && (
                        <p className="type-caption text-ink-tertiary">התקבל {fmtDate(s.assigned_at)}</p>
                      )}
                    </div>
                    <div className="flex gap-1.5">
                      <Button size="sm" loading={busy === `view:${s.id}`} onClick={() => void act(s, 'view')}>
                        <Eye size={ICON.sm} strokeWidth={STROKE} />
                        צפייה
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        loading={busy === `download:${s.id}`}
                        onClick={() => void act(s, 'download')}
                      >
                        <Download size={ICON.sm} strokeWidth={STROKE} />
                        הורדה
                      </Button>
                    </div>
                  </li>
                )),
              )}
            </ul>
          </CardBody>
        </Card>
      )}
    </div>
  )
}
