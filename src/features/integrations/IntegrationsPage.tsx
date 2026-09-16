/**
 * אינטגרציות — החיבור ל-ViperFlow (0176‏–0177).
 *
 * המסך עונה על שלוש שאלות, וזה גם הסדר שלהן: האם החיבור חי, מה נכנס דרכו,
 * ומה נכנס ולא הוחל. השלישית היא היחידה שדורשת פעולה, ולכן היא מקבלת מסנן
 * משלה וכפתור על כל שורה.
 *
 * **מה שאין כאן, ובכוונה:** שדה לסוד. מפתח החתימה של ה-Webhook ומפתח ה-API
 * של ViperFlow הם סודות של פונקציות הקצה (‏`VIPERFLOW_WEBHOOK_SECRET`,
 * ‏`VIPERFLOW_API_KEY`) ואינם עוברים דרך המסד — ראו `docs/VIPERFLOW.md`.
 * טופס שמקבל סוד הוא טופס ששולח אותו למקום שבו הוא נקרא, וזה בדיוק מה
 * ש-0176 §1 אומרת לא לעשות.
 */
import { useState } from 'react'
import {
  AlertTriangle,
  CircleCheck,
  ICON,
  Plug,
  RefreshCw,
  RotateCcw,
  STROKE,
} from '../../components/ui/icons'
import {
  Badge,
  Button,
  Card,
  CardBody,
  CardHeader,
  Checkbox,
  EmptyState,
  ErrorState,
  Field,
  Input,
  PageHeader,
  Select,
  SegmentedControl,
  SkeletonList,
  StatCard,
  StatusPill,
  cx,
  fmtRelative,
  useToast,
} from '../../components/ui'
import { RequirePermission } from '../auth/guards'
import { PERM } from '../../lib/permissions'
import { useAuth } from '../../state/auth'
import { useCustomers } from '../../lib/queries'
import { fmtDateTime } from '../../lib/dates'
import { errorMessage } from '../../lib/errors'
import {
  useReplayDelivery,
  useSetViperflowConnection,
  useViperflowDeliveries,
  useViperflowStatus,
  useViperflowSync,
} from './viperflowQueries'
import type { ViperflowConnectionStatus } from '../../types/domain'

const STATUS_TONE: Record<string, { label: string; color: string }> = {
  processed: { label: 'הוחל', color: '#16a34a' },
  ignored: { label: 'לא רלוונטי', color: '#94a3b8' },
  failed: { label: 'נכשל', color: '#ef4444' },
  received: { label: 'התקבל', color: '#f59e0b' },
}

export default function IntegrationsPage() {
  const has = useAuth((s) => s.has)
  const canManage = has(PERM.INTEGRATIONS_MANAGE)

  const { data: connections = [], isLoading, error, refetch } = useViperflowStatus()
  const [feed, setFeed] = useState<'all' | 'failed'>('all')
  const { data: deliveries = [], isLoading: loadingFeed } = useViperflowDeliveries(feed === 'failed')

  const sync = useViperflowSync()
  const toast = useToast()

  async function runSync(connectionId: string) {
    try {
      const summary = await sync.mutateAsync(connectionId)
      toast.success(
        `נסרקו ${summary.scanned} הזמנות · הוחלו ${summary.applied} · ללא שינוי ${summary.duplicate}` +
          (summary.failed > 0 ? ` · נכשלו ${summary.failed}` : ''),
      )
    } catch (e) {
      toast.error(errorMessage(e))
    }
  }

  return (
    <RequirePermission perm={PERM.INTEGRATIONS_VIEW}>
      <div className="space-y-4">
        <PageHeader
          title="אינטגרציות"
          subtitle="אירועים, משימות ורשימת ריהוט שמגיעים מ-ViperFlow"
        />

        {isLoading && <SkeletonList rows={2} />}
        {error && <ErrorState error={error} onRetry={() => void refetch()} />}

        {!isLoading && !error && connections.length === 0 && (
          <EmptyState
            art="box"
            title="אין חיבור ל-ViperFlow"
            description={
              canManage
                ? 'חיבור קושר לקוח אחד אצלנו לחשבון ViperFlow אחד. כל הזמנה שנפתחת שם תיפתח כאן כאירוע, עם ההקמה והפירוק שלו.'
                : 'כשיוגדר חיבור הוא יופיע כאן.'
            }
          />
        )}

        {connections.map((connection) => (
          <ConnectionCard
            key={connection.id}
            connection={connection}
            canManage={canManage}
            syncing={sync.isPending}
            onSync={() => void runSync(connection.id)}
          />
        ))}

        {canManage && <ConnectionForm existing={connections} />}

        <Card>
          <CardHeader
            title="מה נכנס"
            icon={<Plug size={ICON.md} strokeWidth={STROKE} />}
            actions={
              <SegmentedControl<'all' | 'failed'>
                value={feed}
                onChange={setFeed}
                items={[
                  { key: 'all', label: 'הכול' },
                  { key: 'failed', label: 'נכשלו' },
                ]}
              />
            }
          />
          <CardBody>
            {loadingFeed && <SkeletonList rows={4} />}
            {!loadingFeed && deliveries.length === 0 && (
              <EmptyState
                art="box"
                title={feed === 'failed' ? 'אין משלוחים שנכשלו' : 'עוד לא נכנס דבר'}
                description={
                  feed === 'failed'
                    ? 'כל מה שהגיע הוחל או סומן כלא רלוונטי.'
                    : 'משלוח נכנס כשמישהו פותח או משנה הזמנה ב-ViperFlow.'
                }
              />
            )}
            {deliveries.length > 0 && (
              <ul className="divide-y divide-line-subtle">
                {deliveries.map((delivery) => (
                  <DeliveryRow
                    key={delivery.id}
                    delivery={delivery}
                    canManage={canManage}
                  />
                ))}
              </ul>
            )}
          </CardBody>
        </Card>
      </div>
    </RequirePermission>
  )
}

/* ===== חיבור אחד ========================================================== */

function ConnectionCard({
  connection,
  canManage,
  syncing,
  onSync,
}: {
  connection: ViperflowConnectionStatus
  canManage: boolean
  syncing: boolean
  onSync: () => void
}) {
  /* "חי" אינו `is_active` לבדו: חיבור דלוק שלא נכנס דרכו דבר יומיים הוא
     בדיוק המצב שמסך כזה קיים כדי להראות. */
  const quiet =
    connection.is_active &&
    (!connection.last_event_at ||
      Date.now() - new Date(connection.last_event_at).getTime() > 48 * 60 * 60 * 1000)

  return (
    <Card>
      <CardHeader
        title={
          <span className="flex flex-wrap items-center gap-2">
            {connection.label}
            {connection.is_active ? (
              <StatusPill color="#16a34a">פעיל</StatusPill>
            ) : (
              <StatusPill color="#94a3b8">כבוי</StatusPill>
            )}
            <Badge tone="neutral">{connection.customer_name}</Badge>
          </span>
        }
        icon={
          connection.failed_open > 0 ? (
            <AlertTriangle size={ICON.md} strokeWidth={STROKE} className="text-danger" />
          ) : (
            <CircleCheck size={ICON.md} strokeWidth={STROKE} />
          )
        }
        actions={
          canManage ? (
            <Button size="sm" loading={syncing} onClick={onSync}>
              <RefreshCw size={ICON.sm} strokeWidth={STROKE} />
              סנכרון עכשיו
            </Button>
          ) : undefined
        }
      />
      <CardBody className="space-y-3">
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <StatCard label="אירועים מקושרים" value={connection.linked_events} />
          <StatCard label="נכנסו ביממה" value={connection.received_24h} />
          <StatCard label="ממתינים לטיפול" value={connection.failed_open} />
          <StatCard
            label="אירוע אחרון"
            value={connection.last_event_at ? fmtRelative(connection.last_event_at) : '—'}
          />
        </div>

        {quiet && (
          <p className="rounded-lg bg-subtle px-3 py-2 type-caption text-ink-secondary">
            לא נכנס דבר ביומיים האחרונים. ייתכן שפשוט לא נפתחו הזמנות — ואם כן נפתחו, כדאי
            לבדוק במסך המפתחים של ViperFlow שנקודת הקצה לא כובתה, וללחוץ "סנכרון עכשיו".
          </p>
        )}

        {connection.notes && (
          <p className="type-caption text-ink-secondary">{connection.notes}</p>
        )}
      </CardBody>
    </Card>
  )
}

/* ===== חיבור חדש ========================================================== */

function ConnectionForm({ existing }: { existing: ViperflowConnectionStatus[] }) {
  const { data: customers = [] } = useCustomers()
  const save = useSetViperflowConnection()
  const toast = useToast()

  const [customerId, setCustomerId] = useState('')
  const [label, setLabel] = useState('')
  const [isActive, setIsActive] = useState(true)
  const [open, setOpen] = useState(false)

  /* לקוח שכבר יש לו חיבור פעיל אינו ברשימה: `viperflow_connections_customer_uq`
     ידחה את השורה ממילא, ובורר שמציע אפשרות שתיכשל אינו בורר. */
  const taken = new Set(existing.filter((c) => c.is_active).map((c) => c.customer_id))
  const available = customers.filter((c) => !taken.has(c.id))

  async function submit() {
    try {
      await save.mutateAsync({ customerId, label: label.trim(), isActive })
      toast.success('החיבור נשמר')
      setOpen(false)
      setCustomerId('')
      setLabel('')
    } catch (e) {
      toast.error(errorMessage(e))
    }
  }

  if (!open) {
    return (
      <Button onClick={() => setOpen(true)} disabled={available.length === 0}>
        <Plug size={ICON.sm} strokeWidth={STROKE} />
        חיבור חדש
      </Button>
    )
  }

  return (
    <Card>
      <CardHeader title="חיבור חדש" icon={<Plug size={ICON.md} strokeWidth={STROKE} />} />
      <CardBody className="space-y-3">
        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="הלקוח שההזמנות נכנסות אליו" required>
            <Select value={customerId} onChange={(e) => setCustomerId(e.target.value)}>
              <option value="">בחירה…</option>
              {available.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="שם החיבור" required>
            <Input
              value={label}
              onChange={(e) => setLabel(e.target.value)}
              placeholder="שיא עיצובים — ViperFlow"
            />
          </Field>
        </div>

        <Checkbox
          checked={isActive}
          onChange={setIsActive}
          label="פעיל — משלוחים שייכנסו יתורגמו לאירועים"
        />

        <p className="type-caption text-ink-tertiary">
          החיבור הוא חצי מהעבודה. את החצי השני עושים במסך המפתחים של ViperFlow: נקודת קצה
          שמצביעה על <code className="tabular">/functions/v1/viperflow-webhook</code>, והסוד שהיא
          מנפיקה נשמר כסוד של פונקציית הקצה — לא כאן.
        </p>

        <div className="flex justify-end gap-2">
          <Button onClick={() => setOpen(false)} disabled={save.isPending}>
            ביטול
          </Button>
          <Button
            variant="primary"
            loading={save.isPending}
            disabled={!customerId || label.trim() === ''}
            onClick={() => void submit()}
          >
            שמירה
          </Button>
        </div>
      </CardBody>
    </Card>
  )
}

/* ===== שורת משלוח ========================================================= */

function DeliveryRow({
  delivery,
  canManage,
}: {
  delivery: import('../../types/domain').ViperflowDelivery
  canManage: boolean
}) {
  const replay = useReplayDelivery()
  const toast = useToast()
  const tone = STATUS_TONE[delivery.status] ?? STATUS_TONE.received

  async function run() {
    try {
      const result = await replay.mutateAsync(delivery.id)
      if (result?.status === 'processed') toast.success('המשלוח הוחל')
      else toast.error(result?.reason ?? 'המשלוח לא הוחל')
    } catch (e) {
      toast.error(errorMessage(e))
    }
  }

  return (
    <li className={cx('flex flex-wrap items-center gap-2 py-2', delivery.status === 'failed' && 'bg-danger/5')}>
      <StatusPill color={tone.color}>{tone.label}</StatusPill>
      <span className="type-caption font-semibold text-ink">{delivery.event_type}</span>
      <span className="min-w-0 flex-1 truncate type-caption text-ink-secondary">
        {delivery.reason}
      </span>
      <span className="type-caption tabular text-ink-tertiary">
        {fmtDateTime(delivery.received_at)}
      </span>
      {canManage && delivery.status === 'failed' && (
        <Button size="sm" loading={replay.isPending} onClick={() => void run()}>
          <RotateCcw size={ICON.sm} strokeWidth={STROKE} />
          הרצה מחדש
        </Button>
      )}
    </li>
  )
}
