import { useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Banknote,
  Calendar,
  Check,
  ChevronDown,
  Copy,
  History,
  ICON,
  LayoutGrid,
  List,
  MoreVertical,
  Paperclip,
  Pencil,
  PencilLine,
  Phone,
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
  Drawer,
  EmptyState,
  IconButton,
  LocationText,
  MenuItem,
  MenuLabel,
  MenuSeparator,
  PageHeader,
  Popover,
  SegmentedControl,
  Select,
  Skeleton,
  StatCard,
  StatusPill,
  Tabs,
  cx,
  fmtMoney,
  relativeDayLabel,
  SkeletonCard,
  ErrorState,
  SkeletonTable,
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
import { EventTaskCard } from './EventTaskCard'
import { formatCustomValue } from './CustomFieldInput'
import { TaskDrawer, useCanOpenTaskCard } from '../tasks/TaskDrawer'
import { EventActivityLog } from './EventActivityLog'
import { EventSpecsModal } from './EventSpecsModal'
import { CustomerSignatureModal } from './CustomerSignatureModal'
import { useEventSpecs } from './specQueries'
import { sumAddons, useEventPriceAddons } from '../pricing/addonQueries'
import { useEventSignatures } from './signatureQueries'
import type { EventPriceAddon, EventRow, PerformedBy, WorkBoardRow } from '../../types/domain'

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
  const [logOpen, setLogOpen] = useState(false)
  const [taskDrawer, setTaskDrawer] = useState<{ open: boolean; taskId: string | null }>({ open: false, taskId: null })
  const [activeTab, setActiveTab] = useState<TaskTab>('all')
  const [viewMode, setViewMode] = useState<TaskViewMode>('cards')

  const { data, isLoading, error, refetch } = useQuery({
    queryKey: ['events', 'one', id],
    queryFn: async () => {
      const [e, contact, sup] = await Promise.all([
        supabase.from('events').select('*, customers(name, color, performed_by_enabled), statuses(name, color)').eq('id', id).single(),
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
      const { data, error } = await supabase
        .from('work_board_view')
        .select('*')
        .eq('event_id', id)
        /* התאריך ואז השעה. בלי השעה, הקמה ופירוק שנופלים על אותו יום חוזרים
           בסדר שרירותי — ובאירוע שבו הפירוק ב-06:00 וההקמה ב-18:00 המסך סיפר
           את היום הפוך. `DataTable` מחזיר את השורות כפי שהן כשאין מיון פעיל,
           ולכן זה לבדו מסדר את הטבלה. */
        .order('task_date')
        .order('onsite_start_time', { nullsFirst: false })
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

  /**
   * תוספות המחיר של האירוע (0113) — הן ואת ההערה שמסבירה כל אחת מהן.
   *
   * שאילתה נפרדת ולא עמודה ב-`work_board_view`: התוספת היא רשימה ולא מספר,
   * וכל הנקודה שלה היא המשפט שנלווה לסכום. ‏RLS על `task_price_addons` היא
   * שמכריעה מי רואה מה, ולכן הלקוח מקבל כאן בדיוק את התוספות של האירוע שלו.
   */
  const { data: priceAddons = [] } = useEventPriceAddons(id ?? null, !!id && has(PERM.PRICING_VIEW))

  const pricing = useMemo(() => {
    const priced = tasks.filter((t) => t.customer_price != null)
    if (!priced.length && !priceAddons.length) return null
    const base = priced.reduce((sum, t) => sum + Number(t.customer_price), 0)
    return {
      rows: priced.map((t) => ({
        id: t.id,
        label: t.title || t.task_type_name,
        price: Number(t.customer_price),
        isManual: !!t.price_is_manual,
        /* התוספות של אותה משימה יושבות מתחתיה, ולא בגוש נפרד: "המתנה בשער"
           היא משפט על ההקמה, ומי שקורא את השורה שלה צריך לראות אותו שם. */
        addons: priceAddons.filter((a) => a.task_id === t.id),
      })),
      /* תוספת על משימה שאין לה מחיר עדיין אינה נעלמת — היא נספרת בסך הכול
         ומקבלת שורה משלה מתחת לרשימה. */
      orphanAddons: priceAddons.filter((a) => !priced.some((t) => t.id === a.task_id)),
      total: base + sumAddons(priceAddons),
      unpriced: tasks.length - priced.length,
    }
  }, [tasks, priceAddons])

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
  // הלקוח אינו רואה את משבצת "צוות משובץ" — מי מבצע בשטח אינו עניינו של הלקוח.
  const isCustomerUser = me?.profile.user_kind === 'customer_user'

  // ‏0120: בורר "בוצע ע"י" מופיע רק אצל לקוח שהאפשרות מופעלת אצלו (ארקו).
  const performedByEnabled = !!data?.event.customers?.performed_by_enabled
  const canSetPerformedBy = !!me?.profile.is_admin || has(PERM.TASKS_EDIT) || isCustomerUser
  const setPerformedBy = useMutation({
    mutationFn: async ({ taskId, value }: { taskId: string; value: PerformedBy }) => {
      const { error } = await supabase.rpc('set_task_performed_by', { p_task_id: taskId, p_value: value })
      if (error) throw error
    },
    onSuccess: () => void refetchTasks(),
    onError: (e) => toast.error(errorMessage(e)),
  })
  /**
   * כרטיס המשימה הוא מסך עריכה, ואותו מפתח ששולט בו בלו״ז שולט בו גם כאן
   * (0079). בלעדיו שורת המשימה נשארת מה שהיא — מידע — ואינה מציעה לחיצה
   * שתיפתח למסך שאין בו מה לשנות.
   */
  /* ‏0108: כרטיס המשימה — פתיחה ויצירה כאחת — הוא של מנהל המערכת. */
  const canOpenTaskCard = useCanOpenTaskCard()
  const canOpenTask = has(PERM.BOARD_OPEN_TASK) && canOpenTaskCard
  /* משימה חדשה נפתחת באותו כרטיס, ולכן היא הולכת אחריו. */
  const canCreateTask = has(PERM.TASKS_CREATE) && canOpenTaskCard
  /** סכומי כסף הם מפתח, ולא "מה שיש בנתונים": בלעדיו הכרטיס אינו קיים */
  const canSeePricing = has(PERM.PRICING_VIEW)
  /**
   * אישור לביצוע (0109) — של מנהל המערכת, ולא של מפתח.
   *
   * ‏`set_event_approved` דוחה כל אחד אחר, וטריגר חוסם כתיבה ישירה לעמודה,
   * ולכן המתג כאן אינו השער אלא רק הדלת: מי שאינו אדמין פשוט לא רואה אותו.
   */
  const isAdmin = !!me?.profile.is_admin
  const approve = useMutation({
    mutationFn: async (on: boolean) => {
      const { error } = await supabase.rpc('set_event_approved', { p_event_id: id, p_on: on })
      if (error) throw error
    },
    onSuccess: (_d, on) => {
      toast.success(on ? 'האירוע אושר לביצוע' : 'האישור בוטל')
      void qc.invalidateQueries({ queryKey: ['events'] })
      void qc.invalidateQueries({ queryKey: ['calendar'] })
      void qc.invalidateQueries({ queryKey: ['event_activity', id] })
    },
    onError: (e) => toast.error(errorMessage(e)),
  })

  /* נגזר מהשאילתה ולא נבנה בתוך ה-JSX: `.map()` שם מייצר מערך חדש בכל
     רינדור, כלומר prop שמתחלף בלי ששום דבר השתנה. יושב מעל ה-early return
     כי hook מתחתיו הוא הפרה של rules-of-hooks. */
  const supplierIds = useMemo(() => (data?.suppliers ?? []).map((s) => s.supplier_id), [data])

  const columns = useMemo<Column<WorkBoardRow>[]>(
    () => [
      {
        key: 'type',
        header: 'משימה',
        width: 180,
        fixed: true,
        wrap: true,
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
      ...(performedByEnabled
        ? ([
            {
              key: 'performed_by',
              header: 'בוצע ע"י',
              width: 130,
              sortValue: (t) => t.performed_by,
              render: (t) => (
                <Select
                  selectSize="sm"
                  aria-label={'בוצע ע"י'}
                  value={t.performed_by}
                  disabled={!canSetPerformedBy || setPerformedBy.isPending}
                  onChange={(e) =>
                    setPerformedBy.mutate({ taskId: t.id, value: e.target.value as PerformedBy })
                  }
                >
                  <option value="viper">וייפר</option>
                  <option value="arko">ארקו</option>
                </Select>
              ),
            },
          ] as Column<WorkBoardRow>[])
        : []),
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
    [pricing, showStaffing, performedByEnabled, canSetPerformedBy, setPerformedBy],
  )

  if (isLoading || !data) {
    // ראה CustomerDetailPage: בלי זה כישלון טעינה נראה כטעינה שלא נגמרת.
    if (error) return <ErrorState error={error} onRetry={() => void refetch()} />
    /* השלד מצייר את הפריסה האמיתית — כותרת, רצועת אריחים, ואז 2/3 משימות
       מול 1/3 סרגל — כדי שהמעבר לנתונים לא יזיז את מה שכבר נקרא. */
    return (
      <div className="space-y-4">
        <SkeletonCard lines={1} />
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="h-24 w-full rounded-xl" />
          ))}
        </div>
        <div className="grid items-start gap-4 lg:grid-cols-3">
          <div className="lg:col-span-2">
            <SkeletonTable rows={5} cols={5} />
          </div>
          <div className="space-y-4">
            <SkeletonCard lines={8} />
            <SkeletonCard lines={4} />
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

  /* The same rule that shapes the form shapes the read view: a field the
     reader's company configured off, or their field permissions hide, should
     not reappear here. `showsEventField` answers both at once. */
  const show = showsEventField

  const addons = show('addons')
    ? [
        event.no_parking && 'אין חניה',
        event.porterage && 'סבלות',
        event.supplier_pickup && 'איסוף מספקים',
      ].filter(Boolean)
    : []

  type InfoRow = [string, React.ReactNode]
  /** ‏`wide` — ערך שנקרא כפסקה ולא כערך קצר, ולכן אינו נדחס לצד התווית. */
  type InfoGroup = { title: string; rows: InfoRow[]; wide?: boolean }

  /**
   * הפרטים כקבוצות ולא כרשימה שטוחה.
   *
   * עד כאן זה היה `<dl>` אחד של עד עשרים שורות במשקל ויזואלי זהה — זהות,
   * מיקום, לוגיסטיקה, איש קשר, הערות ושדות הלקוח בערבוביה, ואי אפשר לסרוק
   * את זה. הקיבוץ אינו מוסיף ואינו מסתיר מידע; הוא רק נותן לעין מקום לנחות.
   *
   * מה שכן ירד: שורת סיכום לכל משימה, שחזרה על מה שכרטיסי המשימות אומרים
   * ממש באותו מסך, וכן מספר האירוע והמיקום — אלה יושבים בכותרת המשנה.
   *
   * כל תנאי ההרשאה (`show`, `canSeeContact`) נשארים כלשונם: זו אותה החלטה
   * על מה מותר לקרוא, רק בסידור אחר.
   */
  const infoGroups: InfoGroup[] = ([
    {
      title: 'זהות',
      rows: [
        [
          'לקוח במערכת',
          customer ? (
            <span key="customer" className="inline-flex items-center gap-1.5">
              <span
                className="size-2.5 shrink-0 rounded-full"
                style={{ background: customer.color ?? undefined }}
              />
              {customer.name}
            </span>
          ) : null,
        ],
        ['שם לקוח האירוע', event.end_client_name],
      ],
    },
    {
      title: 'מיקום',
      rows: [
        /* השדה נבנה רק כשיש כתובת — אלמנט הוא תמיד "לא ריק" מבחינת הפילטר
           למטה, ובלעדי התנאי הזה הייתה נשארת שורת "מיקום" ריקה */
        ...(show('location') && event.location_text
          ? ([['כתובת', <LocationText key="location" value={event.location_text} />]] as InfoRow[])
          : []),
        ...(show('location_notes') ? ([['הערות למיקום', event.location_notes]] as InfoRow[]) : []),
      ],
    },
    {
      title: 'לוגיסטיקה',
      rows: [
        ...(show('volume_m') ? ([['נפח במטר', event.volume_m]] as InfoRow[]) : []),
        ...(show('truck_count') ? ([['כמות משאיות', event.truck_count]] as InfoRow[]) : []),
        ...(addons.length > 0
          ? ([
              [
                'תוספות',
                <span key="addons" className="flex flex-wrap gap-1">
                  {addons.map((a) => (
                    <Badge key={String(a)} tone="info">
                      {a}
                    </Badge>
                  ))}
                </span>,
              ],
            ] as InfoRow[])
          : []),
        ...(suppliers.length > 0
          ? ([
              [
                'ספקים לאיסוף',
                <span key="suppliers" className="flex flex-wrap gap-1">
                  {suppliers.map((s) => (
                    <Badge key={s.supplier_id}>{s.suppliers.name}</Badge>
                  ))}
                </span>,
              ],
            ] as InfoRow[])
          : []),
      ],
    },
    {
      title: 'איש קשר',
      rows: canSeeContact
        ? ([
            ['שם', contact?.contact_name],
            [
              'טלפון',
              contact?.contact_phone ? (
                <a
                  key="phone"
                  href={`tel:${contact.contact_phone}`}
                  dir="ltr"
                  className="inline-flex items-center gap-1.5 rounded-md text-primary-text hover:underline focus-visible:outline-none focus-visible:focus-ring"
                >
                  <Phone size={ICON.xs} strokeWidth={STROKE} />
                  {contact.contact_phone}
                </a>
              ) : null,
            ],
          ] as InfoRow[])
        : [],
    },
    {
      title: 'הערות',
      wide: true,
      rows: show('notes') ? ([['', event.notes]] as InfoRow[]) : [],
    },
    {
      title: 'שדות נוספים',
      wide: true,
      /* the customer's own fields, under the same rule as everything above */
      rows: customFields
        .filter((f) => show(f.field_key))
        .map((f) => [f.label_he, formatCustomValue(f, event.custom_fields?.[f.field_key])] as InfoRow),
    },
  ] as InfoGroup[])
    /* שורה ריקה יורדת, וקבוצה שכל שורותיה ירדו אינה מרונדרת כלל — כותרת
       קבוצה בלי תוכן היא הבטחה שלא מתקיימת. */
    .map((g) => ({ ...g, rows: g.rows.filter(([, v]) => v != null && v !== '') }))
    .filter((g) => g.rows.length > 0)

  return (
    <div className="space-y-5">
      {dialog}

      <PageHeader
        title={
          <span className="flex flex-wrap items-center gap-2.5">
            {event.end_client_name || 'אירוע'}
            <StatusPicker event={event} />
            {/* ‏0109: מה שמנהל המערכת אישר, כל מי שרואה את האירוע קורא —
                ובראשם הלקוח, שזו כל הסיבה שהסימון קיים. */}
            {event.approved_at && (
              <Badge tone="success">
                <Check size={ICON.xs} strokeWidth={STROKE} />
                מאושר לביצוע
              </Badge>
            )}
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
        /**
         * שש פעולות בשורה אחת, שתיים מהן `primary` ומחיקה אדומה ביניהן, הן
         * שורה בלי היררכיה: העין לא יודעת במה להתחיל. כאן יש ראשי אחד —
         * עריכה — משניים לצידו, והנדיר וההרסני יורדים לתפריט גלישה.
         *
         * "אישור לביצוע" נשאר גלוי כשהוא עוד לא ניתן: זו פעולת השער שהלקוח
         * ממתין לה (0109), ולקבור אותה בתפריט זו רגרסיה. אחרי שניתן, התג
         * בכותרת כבר אומר את זה, וביטולו הוא פעולה נדירה — ולכן בתפריט.
         *
         * מתחת ל-sm הטקסטים נעלמים והכפתורים המשניים נשארים אייקונים, כדי
         * שהשורה לא תתפרס על שלוש שורות בטלפון.
         */
        actions={
          <>
            {has(PERM.EVENTS_SPECS_VIEW) && (
              <Button size="sm" onClick={() => setSpecsOpen(true)}>
                <Paperclip size={ICON.sm} strokeWidth={STROKE} />
                <span className="max-sm:sr-only">מפרט</span>
                {specs.length > 0 && <Badge tone="primary">{specs.length}</Badge>}
              </Button>
            )}
            {canViewSignature && (
              <Button size="sm" onClick={() => setSignOpen(true)}>
                <PencilLine size={ICON.sm} strokeWidth={STROKE} />
                <span className="max-sm:sr-only">החתמת לקוח</span>
                {signatures.length > 0 && <Badge tone="success">נחתם</Badge>}
              </Button>
            )}
            {canSeeLog && (
              <Button size="sm" onClick={() => setLogOpen(true)}>
                <History size={ICON.sm} strokeWidth={STROKE} />
                <span className="max-sm:sr-only">יומן פעילות</span>
              </Button>
            )}
            {/* המתג עצמו הוא של מנהל המערכת, וה-RPC דוחה כל אחד אחר (0109). */}
            {isAdmin && !event.approved_at && (
              <Button
                size="sm"
                variant="outlined"
                loading={approve.isPending}
                onClick={() => approve.mutate(true)}
              >
                <Check size={ICON.sm} strokeWidth={STROKE} />
                אישור לביצוע
              </Button>
            )}
            {has(PERM.EVENTS_EDIT) && (
              <Button size="sm" variant="primary" onClick={() => setEditOpen(true)}>
                <Pencil size={ICON.sm} strokeWidth={STROKE} />
                עריכה
              </Button>
            )}
            {/* התפריט קיים רק כשיש בו מה לפתוח — כפתור שנפתח לריק גרוע
                מכפתור שאינו קיים. */}
            {(has(PERM.EVENTS_DUPLICATE) || has(PERM.EVENTS_DELETE) || (isAdmin && event.approved_at)) && (
              <Popover
                align="end"
                trigger={(p) => (
                  <IconButton size="sm" variant="ghost" label="עוד פעולות" {...p}>
                    <MoreVertical size={ICON.md} strokeWidth={STROKE} aria-hidden />
                  </IconButton>
                )}
              >
                {(close) => (
                  <>
                    {has(PERM.EVENTS_DUPLICATE) && (
                      <MenuItem
                        icon={<Copy size={ICON.sm} strokeWidth={STROKE} />}
                        onClick={() => {
                          close()
                          void duplicate()
                        }}
                      >
                        שכפול
                      </MenuItem>
                    )}
                    {isAdmin && event.approved_at && (
                      <MenuItem
                        icon={<Check size={ICON.sm} strokeWidth={STROKE} />}
                        onClick={() => {
                          close()
                          approve.mutate(false)
                        }}
                      >
                        ביטול אישור לביצוע
                      </MenuItem>
                    )}
                    {has(PERM.EVENTS_DELETE) && (
                      <>
                        <MenuSeparator />
                        <MenuItem
                          danger
                          icon={<Trash2 size={ICON.sm} strokeWidth={STROKE} />}
                          onClick={() => {
                            close()
                            void remove()
                          }}
                        >
                          מחיקת אירוע
                        </MenuItem>
                      </>
                    )}
                  </>
                )}
              </Popover>
            )}
          </>
        }
      />

      {/* מבט מהיר: מתי, כמה משימות, כמה אנשים, כמה כסף — ארבע השאלות שכל מי
          שנכנס לדף שואל לפני כל היתר. המונים לפי סוג ירדו ל-hint במקום אריח
          נפרד, כי לשוניות הסינון שלמטה אומרות בדיוק את אותו דבר. */}
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard
          icon={<Calendar size={ICON.xl} strokeWidth={STROKE} />}
          label="מועד האירוע"
          value={fmtDate(event.event_date)}
          hint={relativeDayLabel(event.event_date) ?? fmtDateLong(event.event_date)}
        />
        <StatCard
          icon={<List size={ICON.xl} strokeWidth={STROKE} />}
          label="משימות"
          value={tasks.length}
          tone="#1fa189"
          hint={
            [
              taskStats.setupCount ? `${taskStats.setupCount} הקמה` : null,
              taskStats.teardownCount ? `${taskStats.teardownCount} פירוק` : null,
              taskStats.otherCount ? `${taskStats.otherCount} אחר` : null,
            ]
              .filter(Boolean)
              .join(' · ') || 'אין משימות'
          }
        />
        {!isCustomerUser && (
          <StatCard
            icon={<Users size={ICON.xl} strokeWidth={STROKE} />}
            label="צוות"
            value={taskStats.totalWorkers}
            tone="#f59e0b"
            hint="עובדים משובצים"
          />
        )}
        {/* לא "—" למי שאינו רשאי לראות כסף: משבצת ריקה נקראת כמחיר שלא הוזן,
            וזו אמירה על האירוע ולא על הקורא. */}
        {canSeePricing && (
          <StatCard
            icon={<Banknote size={ICON.xl} strokeWidth={STROKE} />}
            label="תמחור"
            value={pricing ? fmtMoney(pricing.total) : '—'}
            tone="#16a34a"
            hint={
              pricing?.unpriced ? `${pricing.unpriced} משימות ללא מחיר` : 'המחיר שהלקוח משלם'
            }
          />
        )}
      </div>

      {/* המשימות הן הסיבה שנכנסים לדף, ולכן הן שני שלישים; הפרטים והתמחור
          יורדים לסרגל צר, שם פריסת תווית-מעל-ערך קריאה יותר מהצמדה לשוליים
          שנשברה בעמודה של 300px. */}
      <div className="grid items-start gap-4 lg:grid-cols-3">
        <div className="lg:col-span-2">
          <Card>
            {/* ‏`Tabs` ו-`SegmentedControl` מה-kit במקום כפתורים שנבנו כאן
                ידנית: הם נותנים ניווט מקלדת, `aria-selected`, וגלילה צידית
                בטלפון — וגם מתקנים בדרך את `text-ink-primary`, קלאס שאין לו
                טוקן — ולכן הלשונית הפעילה איבדה צבע בשקט.

                המונה שהיה כאן ליד הכותרת ירד: לשונית "הכול" נושאת אותו
                מספר בדיוק, סנטימטרים ממנו. */}
            <div className="flex flex-wrap items-center justify-between gap-3 px-4 pb-2 pt-3.5">
              <h2 className="type-title">משימות האירוע</h2>

              <div className="ms-auto flex items-center gap-2">
                <SegmentedControl
                  value={viewMode}
                  onChange={setViewMode}
                  items={[
                    {
                      key: 'cards',
                      label: <span className="sr-only">תצוגת כרטיסים</span>,
                      icon: <LayoutGrid size={ICON.sm} strokeWidth={STROKE} />,
                    },
                    {
                      key: 'table',
                      label: <span className="sr-only">תצוגת טבלה</span>,
                      icon: <List size={ICON.sm} strokeWidth={STROKE} />,
                    },
                  ]}
                />

                {canCreateTask && (
                  <Button size="sm" variant="primary" onClick={() => setTaskDrawer({ open: true, taskId: null })}>
                    <Plus size={ICON.sm} strokeWidth={STROKE} />
                    משימה חדשה
                  </Button>
                )}
              </div>
            </div>

            {/* לשוניות הסינון הן גם קו ההפרדה של ראש הכרטיס — `Tabs` נושא
                `border-b` משלו, ולכן קו ידני נוסף כאן היה קו כפול. */}
            <Tabs
              size="sm"
              className="px-4"
              value={activeTab}
              onChange={setActiveTab}
              items={[
                { key: 'all', label: 'הכול', badge: tasks.length },
                { key: 'setup', label: 'הקמה', badge: taskStats.setupCount },
                { key: 'teardown', label: 'פירוק', badge: taskStats.teardownCount },
                /* לשונית רביעית רק כשיש משימה שאינה הקמה/פירוק */
                ...(taskStats.otherCount > 0
                  ? [{ key: 'other' as TaskTab, label: 'אחר', badge: taskStats.otherCount }]
                  : []),
              ]}
            />

            {/* הטבלה נוגעת בשולי הכרטיס (`padded={false}`) כמו בכל שאר
                המסכים; הכרטיסים והמצב הריק צריכים את הריפוד. */}
            <CardBody padded={viewMode === 'cards' || filteredTasks.length === 0 || loadingTasks}>
              {loadingTasks ? (
                <SkeletonTable rows={4} cols={4} />
              ) : filteredTasks.length === 0 ? (
                <EmptyState
                  art="table"
                  title="אין משימות להצגה"
                  description={
                    activeTab === 'all'
                      ? 'עדיין לא נוספו משימות לאירוע'
                      : 'אין משימות בסינון הזה — נסו לשונית אחרת'
                  }
                  action={
                    canCreateTask && (
                      <Button size="sm" variant="primary" onClick={() => setTaskDrawer({ open: true, taskId: null })}>
                        <Plus size={ICON.sm} strokeWidth={STROKE} />
                        משימה חדשה
                      </Button>
                    )
                  }
                />
              ) : viewMode === 'cards' ? (
                <div className="grid gap-3 sm:grid-cols-2">
                  {filteredTasks.map((t) => (
                    <EventTaskCard
                      key={t.id}
                      task={t}
                      onOpen={canOpenTask ? () => setTaskDrawer({ open: true, taskId: t.id }) : undefined}
                      showStaffing={showStaffing}
                      performedByEnabled={performedByEnabled}
                      canSetPerformedBy={canSetPerformedBy}
                      performedByPending={setPerformedBy.isPending}
                      onPerformedBy={(value) => setPerformedBy.mutate({ taskId: t.id, value })}
                    />
                  ))}
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

        {/* הסרגל: פרטים ואז כסף. `sticky` כדי שהתמחור יישאר בעין בזמן גלילה
            ברשימת משימות ארוכה, ו-`self-start` כדי שהוא לא יימתח לגובה
            העמודה שלצידו. */}
        <div className="space-y-4 lg:sticky lg:top-4 lg:self-start">
          <Card>
            <CardHeader title="פרטי האירוע" />
            <CardBody>
              <dl className="space-y-3.5">
                {infoGroups.map((g) => (
                  <div
                    key={g.title}
                    className="space-y-2 border-t border-line-subtle pt-3.5 first:border-0 first:pt-0"
                  >
                    <p className="type-overline">{g.title}</p>
                    {g.rows.map(([k, v]) => (
                      <div key={k || g.title} className={g.wide ? '' : 'grid gap-0.5'}>
                        {k && <dt className="type-caption text-ink-tertiary">{k}</dt>}
                        <dd
                          className={cx(
                            'min-w-0 type-body',
                            /* טקסט חופשי נקרא כפסקה; בעמודה צרה, ערך ארוך
                               שנדחק לצד תווית הופך לשתי מילים בשורה. */
                            g.wide ? 'whitespace-pre-wrap' : 'font-medium',
                          )}
                        >
                          {v}
                        </dd>
                      </div>
                    ))}
                  </div>
                ))}
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
                    <div key={r.id} className="py-2 first:pt-0">
                      <div className="flex items-start justify-between gap-3">
                        <dt className="min-w-0 shrink type-caption text-ink-tertiary">
                          {r.label}
                          {r.isManual && <span className="ms-1.5 text-warning-text">ידני</span>}
                        </dt>
                        <dd dir="ltr" className="shrink-0 tabular-nums type-body font-medium">
                          {fmtMoney(r.price)}
                        </dd>
                      </div>
                      {r.addons.map((a) => (
                        <PriceAddonLine key={a.id} addon={a} />
                      ))}
                    </div>
                  ))}
                  {/* תוספת על משימה שעדיין אין לה מחיר. היא נספרת בסך הכול
                      ממילא, ולכן היא חייבת להיראות — אחרת הסכום למטה גדול
                      מסך השורות שמעליו בלי הסבר. */}
                  {pricing.orphanAddons.length > 0 && (
                    <div className="py-2">
                      {pricing.orphanAddons.map((a) => (
                        <PriceAddonLine key={a.id} addon={a} withTask />
                      ))}
                    </div>
                  )}
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
      </div>

      {/* היומן הוא הקשר, לא תוכן ראשי: כעמודה קבועה הוא לקח 42% מהמסך ודחס
          את מה שבגללו נכנסים. במגירה הוא במרחק לחיצה אחת ובגובה מלא. */}
      {canSeeLog && (
        <Drawer open={logOpen} onClose={() => setLogOpen(false)} title="יומן פעילות" width="max-w-lg">
          <EventActivityLog bare eventId={event.id} canNote={isEventLead} />
        </Drawer>
      )}

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
        supplierIds={supplierIds}
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

/**
 * שורת תוספת מחיר בכרטיס התמחור — הסכום, וההערה שמסבירה אותו (0113).
 *
 * זו הסיבה שהתוספת קיימת בכלל: הלקוח רואה למה החשבון גדל, במילים של מי
 * שהיה שם, במקום להתקשר ולשאול. הסכום נוטה ימינה כדי להיקרא כתת-שורה של
 * המשימה שמעליה, ולא כפריט נפרד ברשימה.
 */
function PriceAddonLine({ addon, withTask }: { addon: EventPriceAddon; withTask?: boolean }) {
  const amount = Number(addon.amount)
  return (
    <div className="mt-1 flex items-start justify-between gap-3 ps-3">
      <span className="min-w-0 shrink type-caption text-ink-tertiary">
        {withTask && <span className="font-medium">{addon.task_label} · </span>}
        {addon.note}
      </span>
      <span
        dir="ltr"
        className={cx(
          'shrink-0 tabular-nums type-caption font-medium',
          amount < 0 ? 'text-success-text' : 'text-warning-text',
        )}
      >
        {amount > 0 ? '+' : ''}
        {fmtMoney(amount)}
      </span>
    </div>
  )
}
