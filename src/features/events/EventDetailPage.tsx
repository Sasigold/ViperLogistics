import { useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Banknote,
  Briefcase,
  Calendar,
  Check,
  ChevronDown,
  Clock,
  Copy,
  HardHat,
  ICON,
  LayoutGrid,
  List,
  Paperclip,
  Pencil,
  PencilLine,
  Plus,
  STROKE,
  Trash2,
  Users,
} from '../../components/ui/icons'
import {
  Badge,
  Button,
  Card,
  CardBody,
  CardHeader,
  DataTable,
  EmptyState,
  LocationText,
  MenuItem,
  MenuLabel,
  PageHeader,
  Popover,
  SkeletonCard,
  ErrorState,
  SkeletonTable,
  StatusPill,
  cx,
  fmtMoney,
  useConfirm,
  useToast,
} from '../../components/ui'
import type { Column } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { useCustomFormFields, useStatuses } from '../../lib/queries'
import { errorMessage } from '../../lib/errors'
import { fmtDate, fmtDateLong, fmtHours, fmtTime } from '../../lib/dates'
import { usePageTitle } from '../../app/breadcrumbs'
import { EventFormModal } from './EventFormModal'
import { formatCustomValue } from './CustomFieldInput'
import { TaskDrawer } from '../tasks/TaskDrawer'
import { EventActivityLog } from './EventActivityLog'
import { EventSpecsModal } from './EventSpecsModal'
import { CustomerSignatureModal } from './CustomerSignatureModal'
import { useEventSpecs } from './specQueries'
import { useEventSignatures } from './signatureQueries'
import type { EventRow, WorkBoardRow } from '../../types/domain'

type TaskTab = 'all' | 'setup' | 'teardown' | 'other'
type TaskViewMode = 'cards' | 'table'

export default function EventDetailPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const qc = useQueryClient()
  const toast = useToast()
  const { has, hasAny, me, canViewField, showsEventField } = useAuth()
  const { confirm, dialog } = useConfirm()
  const [editOpen, setEditOpen] = useState(false)
  const [specsOpen, setSpecsOpen] = useState(false)
  const [signOpen, setSignOpen] = useState(false)
  const [taskDrawer, setTaskDrawer] = useState<{ open: boolean; taskId: string | null }>({ open: false, taskId: null })
  const [activeTab, setActiveTab] = useState<TaskTab>('all')
  const [viewMode, setViewMode] = useState<TaskViewMode>('cards')

  const { data, isLoading, error, refetch } = useQuery({
    queryKey: ['events', 'one', id],
    queryFn: async () => {
      const [e, contact, sup] = await Promise.all([
        supabase.from('events').select('*, customers(name, color), statuses(name, color)').eq('id', id).single(),
        supabase.from('event_contacts').select('*').eq('event_id', id).maybeSingle(),
        supabase.from('event_suppliers').select('supplier_id, suppliers(name)').eq('event_id', id),
      ])
      if (e.error) throw e.error
      return {
        event: e.data as EventRow,
        contact: contact.data as { contact_name: string | null; contact_phone: string | null } | null,
        suppliers: (sup.data ?? []) as unknown as { supplier_id: string; suppliers: { name: string } }[],
      }
    },
  })

  const { data: tasks = [], isLoading: loadingTasks, error: tasksError, refetch: refetchTasks } = useQuery({
    queryKey: ['workboard', 'byEvent', id],
    queryFn: async () => {
      const { data, error } = await supabase.from('work_board_view').select('*').eq('event_id', id).order('task_date')
      if (error) throw error
      return data as WorkBoardRow[]
    },
  })

  const { data: customFields } = useCustomFormFields(data?.event.customer_id ?? null)

  // רק בשביל המונה על הכפתור. המסך עצמו נטען כשהמודאל נפתח.
  const { data: specs = [] } = useEventSpecs(id ?? '', !!id && has(PERM.EVENTS_SPECS_VIEW))

  /**
   * ראש צוות ההקמה — לא מפתח במרשם אלא תפקיד על משימת ההקמה של האירוע (0107),
   * נגזר מהמשימות שכבר נשלפו. השרת מכריע את אותו דבר ב-`is_event_setup_team_lead`,
   * וכאן זה רק מה שמחליט אם להציע את כפתור החתימה.
   */
  const isSetupLead =
    !!me?.profile.id && tasks.some((t) => t.task_type_code === 'setup' && t.team_lead_id === me.profile.id)
  // הקהל שעשוי לראות חתימות: מי שיש לו מפתח, ראש צוות ההקמה, או משתמש הלקוח
  // (שרואה רק את האירועים שלו ממילא). RLS היא השער האמיתי — זה רק חוסך שליפה.
  const signAudience =
    hasAny(PERM.EVENTS_SIGN_VIEW, PERM.EVENTS_SIGN_CAPTURE) ||
    isSetupLead ||
    me?.profile.user_kind === 'customer_user'
  const { data: signatures = [] } = useEventSignatures(id ?? '', !!id && signAudience)

  usePageTitle(data?.event.end_client_name ?? null)

  const pricing = useMemo(() => {
    const priced = tasks.filter((t) => t.customer_price != null)
    if (!priced.length) return null
    return {
      rows: priced.map((t) => ({
        id: t.id,
        label: t.title || t.task_type_name,
        price: Number(t.customer_price),
        isManual: !!t.price_is_manual,
      })),
      total: priced.reduce((sum, t) => sum + Number(t.customer_price), 0),
      unpriced: tasks.length - priced.length,
    }
  }, [tasks])

  /* מנהל הקבלן רואה כמה הוא מקבל על האירוע: סכום התשלום על משימותיו, מתוך
     `contractor_price` שה-view כבר הגביל לתמחור שהוא רשאי לראות ולמשימות
     שהואצלו לקבלן שלו (0091). מוצג רק לקבלן — למשרד יש כרטיס תמחור הלקוח. */
  const isContractor = !!me?.profile.contractor_id
  const contractorPay = useMemo(() => {
    if (!isContractor) return null
    const rows = tasks.filter((t) => t.contractor_price != null)
    if (!rows.length) return null
    return {
      rows: rows.map((t) => ({
        id: t.id,
        label: t.title || t.task_type_name,
        price: Number(t.contractor_price),
      })),
      total: rows.reduce((sum, t) => sum + Number(t.contractor_price), 0),
    }
  }, [tasks, isContractor])

  const filteredTasks = useMemo(() => {
    if (activeTab === 'setup') return tasks.filter((t) => t.task_type_code === 'setup')
    if (activeTab === 'teardown') return tasks.filter((t) => t.task_type_code === 'teardown')
    if (activeTab === 'other') return tasks.filter((t) => t.task_type_code !== 'setup' && t.task_type_code !== 'teardown')
    return tasks
  }, [tasks, activeTab])

  const taskStats = useMemo(() => {
    const setupCount = tasks.filter((t) => t.task_type_code === 'setup').length
    const teardownCount = tasks.filter((t) => t.task_type_code === 'teardown').length
    const otherCount = tasks.length - setupCount - teardownCount
    const totalWorkers = tasks.reduce((sum, t) => {
      const count =
        (t.workers?.length || 0) +
        (t.drivers?.length || 0) +
        (t.contractor_worker_list?.length || 0)
      return sum + count
    }, 0)
    return { setupCount, teardownCount, otherCount, totalWorkers }
  }, [tasks])

  /* team / lead / contractor all read joins RLS empties for a reader who is
     not staff. An always-blank column reads as a broken table rather than as
     one that isn't theirs, so the key decides whether it exists. */
  const showStaffing = has(PERM.BOARD_VIEW_STAFFING)
  /**
   * כרטיס המשימה הוא מסך עריכה, ואותו מפתח ששולט בו בלו״ז שולט בו גם כאן
   * (0079). בלעדיו שורת המשימה נשארת מה שהיא — מידע — ואינה מציעה לחיצה
   * שתיפתח למסך שאין בו מה לשנות.
   */
  const canOpenTask = has(PERM.BOARD_OPEN_TASK)
  /** סכומי כסף הם מפתח, ולא "מה שיש בנתונים": בלעדיו הכרטיס אינו קיים */
  const canSeePricing = has(PERM.PRICING_VIEW)

  const columns = useMemo<Column<WorkBoardRow>[]>(
    () => [
      {
        key: 'type',
        header: 'משימה',
        width: 160,
        fixed: true,
        sortValue: (t) => t.title ?? t.task_type_name,
        render: (t) => <span className="font-medium">{t.title || t.task_type_name}</span>,
      },
      {
        key: 'date',
        header: 'תאריך',
        width: 110,
        sortValue: (t) => t.task_date,
        render: (t) => <span className="tabular">{fmtDate(t.task_date)}</span>,
      },
      {
        key: 'window',
        header: 'שעות בשטח',
        width: 130,
        sortValue: (t) => t.onsite_start_time,
        render: (t) => (
          <span className="tabular" dir="ltr">
            {fmtTime(t.onsite_start_time) || '—'}
            {t.onsite_end_time ? `–${fmtTime(t.onsite_end_time)}` : ''}
          </span>
        ),
      },
      {
        key: 'hours',
        header: 'משך',
        width: 80,
        align: 'end',
        sortValue: (t) => t.hours_count,
        render: (t) => <span className="tabular">{fmtHours(t.hours_count) || '—'}</span>,
      },
      ...(showStaffing ? ([{
        key: 'team',
        header: 'צוות',
        width: 150,
        render: (t) => {
          const names = [
            ...(t.workers ?? []).map((w) => w.name),
            ...(t.drivers ?? []).map((d) => d.name),
            ...(t.contractor_worker_list ?? []).map((w) => w.name),
          ]
          /* שמות מלאים ולא ראשי תיבות: מי שקורא את המסך הזה בשטח צריך לדעת
             את מי הוא פוגש, ו-"א.כ." אינו עונה על זה. */
          return names.length ? (
            <span className="flex flex-wrap items-center gap-1">
              {names.map((n) => (
                <span key={n} className="rounded bg-subtle px-1.5 py-px type-caption text-ink-secondary">
                  {n}
                </span>
              ))}
              <span className="type-caption tabular text-ink-tertiary">
                {names.length}/{t.worker_count || '—'}
              </span>
            </span>
          ) : (
            <span className="type-caption text-ink-tertiary">לא שובץ</span>
          )
        },
      }] as Column<WorkBoardRow>[]) : []),
      {
        key: 'method',
        header: 'אופן ביצוע',
        width: 140,
        sortValue: (t) => t.execution_method_name,
        render: (t) => t.execution_method_name || <span className="text-ink-tertiary">—</span>,
      },
      ...(showStaffing ? ([
        {
          key: 'lead',
          header: 'ראש צוות',
          width: 130,
          sortValue: (t) => t.team_lead_name,
          render: (t) => t.team_lead_name || <span className="text-ink-tertiary">—</span>,
        },
        {
          key: 'contractor',
          header: 'קבלן',
          width: 130,
          sortValue: (t) => t.contractor_name,
          render: (t) => t.contractor_name || <span className="text-ink-tertiary">—</span>,
        },
      ] as Column<WorkBoardRow>[]) : []),
      {
        key: 'status',
        header: 'סטטוס',
        width: 130,
        sortValue: (t) => t.status_name,
        render: (t) => <StatusPill color={t.status_color}>{t.status_name}</StatusPill>,
      },
      ...(pricing
        ? ([
            {
              key: 'price',
              header: 'מחיר ללקוח',
              width: 120,
              align: 'end',
              sortValue: (t) => t.customer_price,
              render: (t) =>
                t.customer_price == null ? (
                  <span className="text-ink-tertiary">—</span>
                ) : (
                  <span dir="ltr" className="tabular font-medium">
                    {fmtMoney(t.customer_price)}
                  </span>
                ),
            },
          ] as Column<WorkBoardRow>[])
        : []),
    ],
    [pricing, showStaffing],
  )

  if (isLoading || !data) {
    // ראה CustomerDetailPage: בלי זה כישלון טעינה נראה כטעינה שלא נגמרת.
    if (error) return <ErrorState error={error} onRetry={() => void refetch()} />
    return (
      <div className="space-y-4">
        <SkeletonCard lines={1} />
        <div className="grid gap-4 lg:grid-cols-12">
          <div className="space-y-4 lg:col-span-8">
            <SkeletonCard lines={6} />
            <SkeletonTable rows={5} cols={5} />
          </div>
          <div className="lg:col-span-4">
            <SkeletonCard lines={10} />
          </div>
        </div>
      </div>
    )
  }

  const { event, contact, suppliers } = data

  /**
   * מי הלקוח *במערכת*, כפי שהמנהל רואה אותו — עכשיו גם למי שאינו פותח את
   * מודול הלקוחות.
   *
   * שני מקורות ולא אחד: ההטמעה ‏`customers(...)` בשאילתת האירוע עוברת תחת
   * ‏`customers_select`, שדורשת `customers.view`, ולכן היא ריקה לעובד שטח.
   * ‏`work_board_view` נושא את אותה זהות בדיוק — שם וצבע — למי שרואה את
   * המשימה (0079), ולכן משימה של האירוע היא הנפילה הטבעית: מי שהגיע לכאן
   * בלי המפתח הגיע דרך שיבוץ, כלומר יש לו לפחות אחת.
   */
  const customer = event.customers ??
    (() => {
      const named = tasks.find((t) => t.customer_name)
      return named ? { name: named.customer_name!, color: named.customer_color } : null
    })()

  /**
   * ראש הצוות של האירוע הזה — לא מפתח במרשם אלא תפקיד על השורה: אותו אדם
   * הוא ראש צוות באירוע אחד ועובד מן השורה בבא (0082). הוא נגזר מהמשימות
   * שכבר נשלפו, ולכן אין כאן שאילתה נוספת; השרת מכריע את אותו דבר בעצמו
   * ב-`app.is_event_team_lead`, וכאן זה רק מה שמצויר.
   */
  const isEventLead = !!me?.profile.id && tasks.some((t) => t.team_lead_id === me.profile.id)
  const canSeeLog = has(PERM.EVENTS_ACTIVITY_LOG) || isEventLead
  const canSeeContact = canViewField('event', 'contact_phone') || isEventLead

  /* החתמת לקוח (0107): הכפתור לראש צוות ההקמה, למנהל המערכת, וללקוח — ולא
     לעובד מן השורה ולא לרכז אקראי. `has()` מחזיר true לאדמין על כל מפתח. */
  const isEventCustomerUser =
    me?.profile.user_kind === 'customer_user' && me?.profile.customer_id === event.customer_id
  const canCaptureSignature = has(PERM.EVENTS_SIGN_CAPTURE) || isSetupLead || isEventCustomerUser
  const canViewSignature = canCaptureSignature || has(PERM.EVENTS_SIGN_VIEW)

  const remove = async () => {
    if (
      !(await confirm('למחוק את האירוע וכל המשימות שלו? ניתן לשחזר מסל המיחזור.', {
        title: 'מחיקת אירוע',
        confirmLabel: 'מחיקה',
      }))
    )
      return
    const { error } = await supabase.rpc('soft_delete', { p_table: 'events', p_id: event.id })
    if (error) return toast.error(errorMessage(error))
    toast.success('האירוע נמחק')
    void qc.invalidateQueries({ queryKey: ['events'] })
    navigate('/events')
  }

  const duplicate = async () => {
    const { data: newId, error } = await supabase.rpc('duplicate_event', { p_event_id: event.id })
    if (error) return toast.error(errorMessage(error))
    toast.success('האירוע שוכפל')
    void qc.invalidateQueries({ queryKey: ['events'] })
    navigate(`/events/${newId}`)
  }

  const sectionLine = (code: 'setup' | 'teardown') => {
    const t = tasks.find((x) => x.task_type_code === code)
    if (!t) return null
    return (
      [
        fmtDate(t.task_date),
        fmtTime(t.onsite_start_time),
        t.worker_count ? `${t.worker_count} עובדים` : null,
        t.hours_count != null ? `${fmtHours(t.hours_count)} שעות` : null,
        t.execution_method_name,
      ]
        .filter(Boolean)
        .join(' · ') || null
    )
  }

  /* The same rule that shapes the form shapes the read view: a field the
     reader's company configured off, or their field permissions hide, should
     not reappear here. `showsEventField` answers both at once. */
  const show = showsEventField

  const info: [string, React.ReactNode][] = [
    [
      'לקוח במערכת',
      customer ? (
        <span key="customer" className="inline-flex items-center gap-1.5">
          <span className="size-2.5 rounded-full" style={{ background: customer.color ?? undefined }} />
          {customer.name}
        </span>
      ) : null,
    ],
    ['שם לקוח האירוע', event.end_client_name],
    ...(show('event_number') ? ([['מספר אירוע', event.event_number]] as [string, React.ReactNode][]) : []),
    /* השדה נבנה רק כשיש כתובת — אלמנט הוא תמיד "לא ריק" מבחינת הפילטר למטה,
       ובלעדי התנאי הזה הייתה נשארת שורת "מיקום" ריקה */
    ...(show('location') && event.location_text
      ? ([['מיקום', <LocationText key="location" value={event.location_text} />]] as [
          string,
          React.ReactNode,
        ][])
      : []),
    ...(show('location_notes')
      ? ([['הערות למיקום', event.location_notes]] as [string, React.ReactNode][])
      : []),
    ...(show('volume_m') ? ([['נפח במטר', event.volume_m]] as [string, React.ReactNode][]) : []),
    ...(show('truck_count') ? ([['כמות משאיות', event.truck_count]] as [string, React.ReactNode][]) : []),
    ...(canSeeContact
      ? ([
          ['איש קשר', contact?.contact_name],
          [
            'טלפון איש קשר',
            contact?.contact_phone ? (
              <a key="phone" href={`tel:${contact.contact_phone}`} dir="ltr" className="text-primary-text hover:underline">
                {contact.contact_phone}
              </a>
            ) : null,
          ],
        ] as [string, React.ReactNode][])
      : []),
    ['הקמה', sectionLine('setup')],
    ['פירוק', sectionLine('teardown')],
    ...(show('notes') ? ([['הערות', event.notes]] as [string, React.ReactNode][]) : []),
    /* the customer's own fields, under the same rule as everything above */
    ...(customFields
      .filter((f) => show(f.field_key))
      .map((f) => [f.label_he, formatCustomValue(f, event.custom_fields?.[f.field_key])]) as [
      string,
      React.ReactNode,
    ][]),
  ]

  const addons = show('addons')
    ? [
        event.no_parking && 'אין חניה',
        event.porterage && 'סבלות',
        event.supplier_pickup && 'איסוף מספקים',
      ].filter(Boolean)
    : []

  return (
    <div className="space-y-5">
      {dialog}

      <PageHeader
        title={
          <span className="flex flex-wrap items-center gap-2.5">
            {event.end_client_name || 'אירוע'}
            <StatusPicker event={event} />
          </span>
        }
        subtitle={
          <span className="flex flex-wrap items-center gap-x-3">
            {/* הכותרת היא שם לקוח האירוע — מי שהזמין בפועל — ומתחתיה הלקוח
                *במערכת*, כי שני אירועים באותו שם קצה יכולים להיות של שני
                לקוחות, וזה ההקשר שהעובד בשטח צריך לפני כל היתר. */}
            {customer && (
              <span className="inline-flex items-center gap-1.5 font-medium text-ink-secondary">
                <span
                  className="size-2 shrink-0 rounded-full"
                  style={{ background: customer.color ?? undefined }}
                />
                {customer.name}
              </span>
            )}
            <span>{fmtDateLong(event.event_date)}</span>
            {event.event_number && <span className="tabular">· אירוע #{event.event_number}</span>}
            {event.location_text && (
              <span>
                · <LocationText value={event.location_text} />
              </span>
            )}
          </span>
        }
        actions={
          <>
            {has(PERM.EVENTS_SPECS_VIEW) && (
              <Button size="sm" onClick={() => setSpecsOpen(true)}>
                <Paperclip size={ICON.sm} strokeWidth={STROKE} />
                מפרט
                {specs.length > 0 && <Badge tone="primary">{specs.length}</Badge>}
              </Button>
            )}
            {canViewSignature && (
              <Button size="sm" onClick={() => setSignOpen(true)}>
                <PencilLine size={ICON.sm} strokeWidth={STROKE} />
                החתמת לקוח
                {signatures.length > 0 && <Badge tone="success">נחתם</Badge>}
              </Button>
            )}
            {has(PERM.EVENTS_DUPLICATE) && (
              <Button size="sm" onClick={() => void duplicate()}>
                <Copy size={ICON.sm} strokeWidth={STROKE} />
                שכפול
              </Button>
            )}
            {has(PERM.EVENTS_EDIT) && (
              <Button size="sm" variant="primary" onClick={() => setEditOpen(true)}>
                <Pencil size={ICON.sm} strokeWidth={STROKE} />
                עריכה
              </Button>
            )}
            {has(PERM.EVENTS_DELETE) && (
              <Button size="sm" variant="danger" onClick={() => void remove()}>
                <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                מחיקה
              </Button>
            )}
          </>
        }
      />

      {/* Main 2-column grid layout: Right side = Content & Tasks; Left side = Activity Log full-height sidebar */}
      <div className="grid gap-6 lg:grid-cols-12 items-start">
        {/* Right Main Column (in RTL, lg:col-span-7 xl:col-span-8) */}
        <div className="space-y-6 lg:col-span-7 xl:col-span-8">
          {/* Top Cards Grid: Event Info + Pricing */}
          <div className={`grid gap-4 ${pricing ? 'md:grid-cols-2' : 'grid-cols-1'}`}>
            <Card>
              <CardHeader title="פרטי האירוע" />
              <CardBody>
                <dl className="divide-y divide-line-subtle">
                  {info
                    .filter(([, v]) => v != null && v !== '')
                    .map(([k, v]) => (
                      <div key={k} className="flex items-start justify-between gap-3 py-2 first:pt-0 last:pb-0">
                        <dt className="shrink-0 type-caption text-ink-tertiary">{k}</dt>
                        <dd className="min-w-0 text-end type-body font-medium">{v}</dd>
                      </div>
                    ))}
                  {addons.length > 0 && (
                    <div className="flex items-start justify-between gap-3 py-2">
                      <dt className="shrink-0 type-caption text-ink-tertiary">תוספות</dt>
                      <dd className="flex flex-wrap justify-end gap-1">
                        {addons.map((a) => (
                          <Badge key={String(a)} tone="info">
                            {a}
                          </Badge>
                        ))}
                      </dd>
                    </div>
                  )}
                  {suppliers.length > 0 && (
                    <div className="flex items-start justify-between gap-3 py-2 last:pb-0">
                      <dt className="shrink-0 type-caption text-ink-tertiary">ספקים לאיסוף</dt>
                      <dd className="flex flex-wrap justify-end gap-1">
                        {suppliers.map((s) => (
                          <Badge key={s.supplier_id}>{s.suppliers.name}</Badge>
                        ))}
                      </dd>
                    </div>
                  )}
                </dl>
              </CardBody>
            </Card>

            {pricing && (
              <Card>
                <CardHeader
                  title="תמחור"
                  subtitle="המחיר שהלקוח משלם"
                  icon={<Banknote size={ICON.md} strokeWidth={STROKE} />}
                />
                <CardBody>
                  <dl className="divide-y divide-line-subtle">
                    {pricing.rows.map((r) => (
                      <div key={r.id} className="flex items-start justify-between gap-3 py-2 first:pt-0">
                        <dt className="min-w-0 shrink type-caption text-ink-tertiary">
                          {r.label}
                          {r.isManual && <span className="ms-1.5 text-warning-text">ידני</span>}
                        </dt>
                        <dd dir="ltr" className="shrink-0 tabular-nums type-body font-medium">
                          {fmtMoney(r.price)}
                        </dd>
                      </div>
                    ))}
                    <div className="flex items-baseline justify-between gap-3 pt-2">
                      <dt className="type-body font-semibold">סך הכול</dt>
                      <dd dir="ltr" className="tabular-nums type-title font-semibold text-primary">
                        {fmtMoney(pricing.total)}
                      </dd>
                    </div>
                  </dl>
                  {pricing.unpriced > 0 && (
                    <p className="mt-2 type-caption text-ink-tertiary">
                      {pricing.unpriced} משימות ללא מחיר עדיין
                    </p>
                  )}
                </CardBody>
              </Card>
            )}

            {contractorPay && (
              <Card>
                <CardHeader
                  title="התשלום שלך"
                  subtitle="כמה אתה מקבל על האירוע"
                  icon={<Banknote size={ICON.md} strokeWidth={STROKE} />}
                />
                <CardBody>
                  <dl className="divide-y divide-line-subtle">
                    {contractorPay.rows.map((r) => (
                      <div key={r.id} className="flex items-start justify-between gap-3 py-2 first:pt-0">
                        <dt className="min-w-0 shrink type-caption text-ink-tertiary">{r.label}</dt>
                        <dd dir="ltr" className="shrink-0 tabular-nums type-body font-medium">
                          {fmtMoney(r.price)}
                        </dd>
                      </div>
                    ))}
                    <div className="flex items-baseline justify-between gap-3 pt-2">
                      <dt className="type-body font-semibold">סך הכול</dt>
                      <dd dir="ltr" className="tabular-nums type-title font-semibold text-success-text">
                        {fmtMoney(contractorPay.total)}
                      </dd>
                    </div>
                  </dl>
                </CardBody>
              </Card>
            )}
          </div>

          {/* Redesigned Tasks Section */}
          <div className="space-y-4">
            {/* Tasks Summary KPI Bar */}
            <div className={cx('grid grid-cols-2 gap-3', canSeePricing ? 'sm:grid-cols-4' : 'sm:grid-cols-3')}>
              <div className="rounded-xl border border-line-subtle bg-surface p-3 flex flex-col justify-between shadow-xs">
                <span className="type-caption text-ink-tertiary">סך משימות</span>
                <div className="flex items-baseline gap-2 mt-1">
                  <span className="type-title text-xl font-bold">{tasks.length}</span>
                </div>
              </div>

              <div className="rounded-xl border border-line-subtle bg-surface p-3 flex flex-col justify-between shadow-xs">
                <span className="type-caption text-ink-tertiary">חלוקת משימות</span>
                <div className="flex items-center gap-1.5 mt-1">
                  <Badge tone="info">הקמה {taskStats.setupCount}</Badge>
                  <Badge tone="warning">פירוק {taskStats.teardownCount}</Badge>
                  {taskStats.otherCount > 0 && <Badge>אחר {taskStats.otherCount}</Badge>}
                </div>
              </div>

              <div className="rounded-xl border border-line-subtle bg-surface p-3 flex flex-col justify-between shadow-xs">
                <span className="type-caption text-ink-tertiary">צוות משובץ</span>
                <div className="flex items-center gap-1.5 mt-1">
                  <Users size={ICON.sm} className="text-ink-tertiary" />
                  <span className="type-title text-lg font-bold">{taskStats.totalWorkers}</span>
                  <span className="type-caption text-ink-tertiary">עובדים</span>
                </div>
              </div>

              {/* לא "—" למי שאינו רשאי לראות כסף: משבצת ריקה נקראת כמחיר
                  שלא הוזן, וזו אמירה על האירוע ולא על הקורא. */}
              {canSeePricing && (
                <div className="rounded-xl border border-line-subtle bg-surface p-3 flex flex-col justify-between shadow-xs">
                  <span className="type-caption text-ink-tertiary">סך תמחור</span>
                  <div className="flex items-center gap-1.5 mt-1" dir="ltr">
                    <span className="type-title text-lg font-bold text-success-text">
                      {pricing ? fmtMoney(pricing.total) : '—'}
                    </span>
                  </div>
                </div>
              )}
            </div>

            {/* Tasks Container Card */}
            <Card>
              {/* Header & Controls Toolbar */}
              <div className="p-4 border-b border-line-subtle flex flex-wrap items-center justify-between gap-3">
                <div className="flex items-center gap-3">
                  <h2 className="type-title font-semibold flex items-center gap-2">
                    <span>משימות האירוע</span>
                    <Badge tone="neutral" className="tabular">{filteredTasks.length}</Badge>
                  </h2>

                  {/* Filter Tabs */}
                  <div className="flex items-center rounded-lg bg-subtle p-1 border border-line-subtle text-xs">
                    <button
                      type="button"
                      onClick={() => setActiveTab('all')}
                      className={`px-2.5 py-1 rounded-md font-medium transition-all ${
                        activeTab === 'all'
                          ? 'bg-surface text-ink-primary shadow-xs'
                          : 'text-ink-tertiary hover:text-ink-primary'
                      }`}
                    >
                      הכול
                    </button>
                    <button
                      type="button"
                      onClick={() => setActiveTab('setup')}
                      className={`px-2.5 py-1 rounded-md font-medium transition-all ${
                        activeTab === 'setup'
                          ? 'bg-surface text-ink-primary shadow-xs'
                          : 'text-ink-tertiary hover:text-ink-primary'
                      }`}
                    >
                      הקמה ({taskStats.setupCount})
                    </button>
                    <button
                      type="button"
                      onClick={() => setActiveTab('teardown')}
                      className={`px-2.5 py-1 rounded-md font-medium transition-all ${
                        activeTab === 'teardown'
                          ? 'bg-surface text-ink-primary shadow-xs'
                          : 'text-ink-tertiary hover:text-ink-primary'
                      }`}
                    >
                      פירוק ({taskStats.teardownCount})
                    </button>
                    {taskStats.otherCount > 0 && (
                      <button
                        type="button"
                        onClick={() => setActiveTab('other')}
                        className={`px-2.5 py-1 rounded-md font-medium transition-all ${
                          activeTab === 'other'
                            ? 'bg-surface text-ink-primary shadow-xs'
                            : 'text-ink-tertiary hover:text-ink-primary'
                        }`}
                      >
                        אחר ({taskStats.otherCount})
                      </button>
                    )}
                  </div>
                </div>

                <div className="flex items-center gap-2 ms-auto">
                  {/* View Switcher */}
                  <div className="flex items-center rounded-lg bg-subtle p-1 border border-line-subtle">
                    <button
                      type="button"
                      onClick={() => setViewMode('cards')}
                      title="תצוגת כרטיסים"
                      className={`p-1.5 rounded-md transition-all ${
                        viewMode === 'cards'
                          ? 'bg-surface text-primary shadow-xs'
                          : 'text-ink-tertiary hover:text-ink-primary'
                      }`}
                    >
                      <LayoutGrid size={ICON.sm} strokeWidth={STROKE} />
                    </button>
                    <button
                      type="button"
                      onClick={() => setViewMode('table')}
                      title="תצוגת טבלה"
                      className={`p-1.5 rounded-md transition-all ${
                        viewMode === 'table'
                          ? 'bg-surface text-primary shadow-xs'
                          : 'text-ink-tertiary hover:text-ink-primary'
                      }`}
                    >
                      <List size={ICON.sm} strokeWidth={STROKE} />
                    </button>
                  </div>

                  {has(PERM.TASKS_CREATE) && (
                    <Button size="sm" variant="primary" onClick={() => setTaskDrawer({ open: true, taskId: null })}>
                      <Plus size={ICON.sm} strokeWidth={STROKE} />
                      משימה חדשה
                    </Button>
                  )}
                </div>
              </div>

              {/* Tasks Body Content */}
              <CardBody className="p-4">
                {loadingTasks ? (
                  <SkeletonTable rows={4} cols={4} />
                ) : filteredTasks.length === 0 ? (
                  <EmptyState
                    art="table"
                    title="אין משימות להצגה"
                    description="נסה לשנות את הסינון או להוסיף משימה חדשה"
                    action={
                      has(PERM.TASKS_CREATE) && (
                        <Button size="sm" variant="primary" onClick={() => setTaskDrawer({ open: true, taskId: null })}>
                          <Plus size={ICON.sm} />
                          משימה חדשה
                        </Button>
                      )
                    }
                  />
                ) : viewMode === 'cards' ? (
                  /* Cards / Visual Grid View */
                  <div className="grid gap-3 sm:grid-cols-2">
                    {filteredTasks.map((t) => {
                      const names = [
                        ...(t.workers ?? []).map((w) => w.name),
                        ...(t.drivers ?? []).map((d) => d.name),
                        ...(t.contractor_worker_list ?? []).map((w) => w.name),
                      ]
                      return (
                        <div
                          key={t.id}
                          onClick={canOpenTask ? () => setTaskDrawer({ open: true, taskId: t.id }) : undefined}
                          className={cx(
                            'group relative flex flex-col justify-between rounded-xl border border-line-subtle bg-surface p-4 transition-all duration-200',
                            canOpenTask && 'cursor-pointer hover:border-primary/50 hover:shadow-md',
                          )}
                        >
                          <div className="space-y-3">
                            {/* Card Top Row: Task Type / Code Badge + Status */}
                            <div className="flex items-center justify-between gap-2">
                              <div className="flex items-center gap-1.5">
                                {t.task_type_code === 'setup' ? (
                                  <Badge tone="info">הקמה</Badge>
                                ) : t.task_type_code === 'teardown' ? (
                                  <Badge tone="warning">פירוק</Badge>
                                ) : (
                                  <Badge tone="neutral">משימה</Badge>
                                )}
                                <StatusPill color={t.status_color}>{t.status_name}</StatusPill>
                              </div>
                              {t.customer_price != null && (
                                <span dir="ltr" className="type-caption font-bold text-success-text tabular">
                                  {fmtMoney(t.customer_price)}
                                </span>
                              )}
                            </div>

                            {/* Task Title */}
                            <div>
                              <h3 className="type-title font-semibold text-ink-primary group-hover:text-primary transition-colors">
                                {t.title || t.task_type_name}
                              </h3>
                            </div>

                            {/* Date & Time Badges */}
                            <div className="flex flex-wrap items-center gap-2 type-caption text-ink-secondary">
                              <span className="inline-flex items-center gap-1 bg-subtle px-2 py-1 rounded-md border border-line-subtle tabular">
                                <Calendar size={ICON.xs} className="text-ink-tertiary" />
                                {fmtDate(t.task_date)}
                              </span>
                              <span className="inline-flex items-center gap-1 bg-subtle px-2 py-1 rounded-md border border-line-subtle tabular" dir="ltr">
                                <Clock size={ICON.xs} className="text-ink-tertiary" />
                                {fmtTime(t.onsite_start_time) || '—'}
                                {t.onsite_end_time ? `–${fmtTime(t.onsite_end_time)}` : ''}
                              </span>
                              {t.hours_count != null && (
                                <span className="type-caption tabular text-ink-tertiary">
                                  ({fmtHours(t.hours_count)} שעות)
                                </span>
                              )}
                            </div>

                            {/* Team Lead & Contractor info if available */}
                            {(t.team_lead_name || t.contractor_name || t.execution_method_name) && (
                              <div className="flex flex-wrap items-center gap-1.5 type-caption pt-1 border-t border-line-subtle/60">
                                {t.team_lead_name && (
                                  <span className="inline-flex items-center gap-1 text-ink-secondary">
                                    <HardHat size={ICON.xs} className="text-warning-text" />
                                    <span>ר"צ: {t.team_lead_name}</span>
                                  </span>
                                )}
                                {t.contractor_name && (
                                  <span className="inline-flex items-center gap-1 text-ink-secondary">
                                    <Briefcase size={ICON.xs} className="text-info-text" />
                                    <span>{t.contractor_name}</span>
                                  </span>
                                )}
                                {t.execution_method_name && !t.contractor_name && (
                                  <span className="text-ink-tertiary">({t.execution_method_name})</span>
                                )}
                              </div>
                            )}
                          </div>

                          {/* Card Footer: Team Assigned Avatars */}
                          <div className="mt-4 pt-2.5 border-t border-line-subtle flex items-center justify-between">
                            {names.length > 0 ? (
                              <div className="flex flex-wrap items-center gap-1">
                                {names.map((n) => (
                                  <span
                                    key={n}
                                    className="rounded bg-subtle px-1.5 py-px type-caption text-ink-secondary"
                                  >
                                    {n}
                                  </span>
                                ))}
                                <span className="type-caption tabular text-ink-tertiary">
                                  {names.length}/{t.worker_count || '—'} עובדים
                                </span>
                              </div>
                            ) : showStaffing ? (
                              <span className="type-caption text-ink-tertiary">לא שובצו עובדים</span>
                            ) : (
                              <span />
                            )}
                            {canOpenTask && (
                              <span className="type-caption text-primary opacity-0 group-hover:opacity-100 transition-opacity font-medium">
                                פרטים ←
                              </span>
                            )}
                          </div>
                        </div>
                      )
                    })}
                  </div>
                ) : (
                  /* Table View */
                  <DataTable
                    rows={filteredTasks}
                    columns={columns}
                    getRowId={(t) => t.id}
                    loading={loadingTasks}
                    error={tasksError}
                    onRetry={() => void refetchTasks()}
                    dense
                    storageKey="event-tasks"
                    onRowClick={canOpenTask ? (t) => setTaskDrawer({ open: true, taskId: t.id }) : undefined}
                    defaultSort={{ key: 'date', dir: 'asc' }}
                  />
                )}
              </CardBody>
            </Card>
          </div>
        </div>

        {/* Left Sidebar Column - Full Height Activity Log (in RTL, lg:col-span-5 xl:col-span-4) */}
        {canSeeLog && (
          <div className="lg:col-span-5 xl:col-span-4 lg:sticky lg:top-4 h-[calc(100vh-2rem)] flex flex-col">
            <EventActivityLog eventId={event.id} canNote={isEventLead} className="h-full shadow-xs" />
          </div>
        )}
      </div>

      <EventFormModal
        open={editOpen}
        onClose={() => {
          setEditOpen(false)
          void qc.invalidateQueries({ queryKey: ['events', 'one', id] })
          void qc.invalidateQueries({ queryKey: ['workboard', 'byEvent', id] })
          void qc.invalidateQueries({ queryKey: ['event_activity', id] })
        }}
        event={event}
        contact={contact}
        supplierIds={suppliers.map((s) => s.supplier_id)}
      />
      <EventSpecsModal
        eventId={event.id}
        eventTitle={event.end_client_name ?? fmtDateLong(event.event_date)}
        open={specsOpen}
        onClose={() => setSpecsOpen(false)}
      />
      {canViewSignature && (
        <CustomerSignatureModal
          eventId={event.id}
          eventTitle={event.end_client_name ?? fmtDateLong(event.event_date)}
          open={signOpen}
          onClose={() => setSignOpen(false)}
          canCapture={canCaptureSignature}
        />
      )}
      <TaskDrawer
        open={taskDrawer.open}
        onClose={() => {
          setTaskDrawer({ open: false, taskId: null })
          void qc.invalidateQueries({ queryKey: ['workboard', 'byEvent', id] })
        }}
        taskId={taskDrawer.taskId}
        initial={{ event_id: event.id, customer_id: event.customer_id, task_date: event.event_date }}
      />
    </div>
  )
}

/* ===== StatusPicker =======================================================
   The status pill next to the title, which is also how the status is changed.
   Moving an event along its lifecycle is the one edit that happens over and
   over — opening the whole form for it, stepping through it and saving is
   four interactions for a value with four options.

   The write goes through `update_event` and not straight at the table: the
   RPC is the only path that runs the customer's form config, and it takes the
   keys it is given, so a one-key patch moves nothing else on the event. The
   `events.change_status` column trigger still has the last word — this only
   decides whether to offer the control.                                     */

function StatusPicker({ event }: { event: EventRow }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { has } = useAuth()
  const { data: statuses = [] } = useStatuses('event')
  const canChange = has(PERM.EVENTS_CHANGE_STATUS)

  const current = event.statuses
  const pill = <StatusPill color={current?.color}>{current?.name ?? 'ללא סטטוס'}</StatusPill>

  const change = useMutation({
    mutationFn: async (statusId: string) => {
      const { error } = await supabase.rpc('update_event', {
        p_event_id: event.id,
        payload: { status_id: statusId },
      })
      if (error) throw error
    },
    onSuccess: (_d, statusId) => {
      const next = statuses.find((s) => s.id === statusId)
      toast.success(next ? `הסטטוס שונה ל"${next.name}"` : 'הסטטוס עודכן', {
        undo: event.status_id
          ? () => change.mutate(event.status_id!)
          : undefined,
      })
      void qc.invalidateQueries({ queryKey: ['events'] })
      void qc.invalidateQueries({ queryKey: ['calendar'] })
      void qc.invalidateQueries({ queryKey: ['event_activity', event.id] })
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  // nothing to pick from, or no key for it: the pill stays a pill
  if (!canChange || statuses.length === 0) return current ? pill : null

  return (
    <Popover
      align="start"
      trigger={({ toggle, ...aria }) => (
        <button
          type="button"
          onClick={toggle}
          {...aria}
          disabled={change.isPending}
          title="שינוי סטטוס"
          className={cx(
            'inline-flex items-center gap-1 rounded-md transition-opacity',
            'hover:opacity-80 focus-visible:outline-none focus-visible:focus-ring',
            change.isPending && 'opacity-60',
          )}
        >
          {pill}
          <ChevronDown size={ICON.sm} strokeWidth={STROKE} className="text-ink-tertiary" aria-hidden />
        </button>
      )}
    >
      {(close) => (
        <>
          <MenuLabel>סטטוס האירוע</MenuLabel>
          {statuses.map((s) => (
            <MenuItem
              key={s.id}
              icon={<span className="size-2.5 rounded-full" style={{ background: s.color }} />}
              shortcut={s.id === event.status_id ? <Check size={ICON.sm} /> : undefined}
              onClick={() => {
                if (s.id !== event.status_id) change.mutate(s.id)
                close()
              }}
            >
              {s.name}
            </MenuItem>
          ))}
        </>
      )}
    </Popover>
  )
}
