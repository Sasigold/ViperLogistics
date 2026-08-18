/**
 * מפרט האירוע.
 *
 * מסך אחד בשני מצבים: צפייה בגרסה הפעילה, והשוואה של שתי גרסאות זו לצד זו.
 * בעברית החדשה יושבת מימין והישנה משמאל — זה כיוון הקריאה, ולכן זה גם הכיוון
 * שבו "מה השתנה" נקרא נכון.
 */
import { useEffect, useMemo, useRef, useState } from 'react'
import {
  Columns2,
  Download,
  ExternalLink,
  FileText,
  ICON,
  Image as ImageIcon,
  Link2,
  Paperclip,
  STROKE,
  Trash2,
  Upload,
} from '../../components/ui/icons'
import {
  Badge,
  Button,
  EmptyState,
  ErrorState,
  Field,
  IconButton,
  Input,
  Modal,
  SegmentedControl,
  Select,
  SkeletonList,
  Spinner,
  StatusPill,
  cx,
  useConfirm,
  useToast,
} from '../../components/ui'
import { useAuth } from '../../state/auth'
import { PERM } from '../../lib/permissions'
import { errorMessage } from '../../lib/errors'
import { fmtDate } from '../../lib/dates'
import { useIsPhone } from '../../lib/useMediaQuery'
import type { EventSpec } from '../../types/domain'
import {
  SPEC_ACCEPT,
  currentSpec,
  formatBytes,
  pickCompareDefaults,
  sortedSpecs,
  specViewerKind,
  validateSpecFile,
  validateSpecUrl,
} from './specs'
import { specDownloadUrl, useEventSpecs, useRemoveSpec, useSpecSignedUrl, useUploadSpec } from './specQueries'

type Mode = 'view' | 'compare'

export function EventSpecsModal({
  eventId,
  eventTitle,
  open,
  onClose,
}: {
  eventId: string
  eventTitle: string
  open: boolean
  onClose: () => void
}) {
  const { has } = useAuth()
  const toast = useToast()
  const { confirm, dialog } = useConfirm()
  const isPhone = useIsPhone()
  const canManage = has(PERM.EVENTS_SPECS_MANAGE)

  const { data: specs = [], isLoading, error, refetch } = useEventSpecs(eventId, open)
  const remove = useRemoveSpec(eventId)

  const live = useMemo(() => sortedSpecs(specs), [specs])
  const active = currentSpec(specs)

  const [mode, setMode] = useState<Mode>('view')
  const [rightId, setRightId] = useState<string | null>(null)
  const [leftId, setLeftId] = useState<string | null>(null)
  const [adding, setAdding] = useState(false)

  // ברירת המחדל של ההשוואה נגזרת מהרשימה, ולכן היא מתעדכנת כשגרסה נוספת או
  // יורדת. הבחירה הידנית של המשתמש נשמרת כל עוד הגרסה שבחר עדיין קיימת.
  useEffect(() => {
    const pair = pickCompareDefaults(live)
    setRightId((prev) => (prev && live.some((s) => s.id === prev) ? prev : (pair?.[0].id ?? null)))
    setLeftId((prev) => (prev && live.some((s) => s.id === prev) ? prev : (pair?.[1].id ?? null)))
  }, [live])

  const right = live.find((s) => s.id === rightId) ?? active ?? null
  const left = live.find((s) => s.id === leftId) ?? null

  async function onRemove(spec: EventSpec) {
    const ok = await confirm(`להסיר את גרסה ${spec.version} של המפרט?`, {
      title: 'הסרת גרסה',
      confirmLabel: 'הסרה',
    })
    if (!ok) return
    try {
      await remove.mutateAsync(spec.id)
      toast.success(`גרסה ${spec.version} הוסרה`)
    } catch (e) {
      toast.error(errorMessage(e))
    }
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      size="full"
      title={
        <span className="flex flex-wrap items-center gap-2">
          <Paperclip size={ICON.lg} strokeWidth={STROKE} />
          מפרט האירוע
          {live.length > 0 && <Badge tone="primary">{live.length}</Badge>}
        </span>
      }
      description={eventTitle}
    >
      <div className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          {live.length > 0 && (
            <SegmentedControl<Mode>
              value={mode}
              onChange={setMode}
              items={[
                { key: 'view', label: 'צפייה', icon: <FileText size={ICON.sm} strokeWidth={STROKE} /> },
                { key: 'compare', label: 'השוואה', icon: <Columns2 size={ICON.sm} strokeWidth={STROKE} /> },
              ]}
            />
          )}
          {canManage && !adding && (
            <Button size="sm" variant="primary" onClick={() => setAdding(true)}>
              <Upload size={ICON.sm} strokeWidth={STROKE} />
              העלאת גרסה חדשה
            </Button>
          )}
        </div>

        {adding && canManage && (
          <AddSpecForm eventId={eventId} onDone={() => setAdding(false)} />
        )}

        {isLoading && <SkeletonList rows={3} />}
        {error && <ErrorState error={error} onRetry={() => void refetch()} />}

        {!isLoading && !error && live.length === 0 && (
          <EmptyState
            art="box"
            title="טרם הועלה מפרט"
            description={
              canManage
                ? 'אפשר להעלות PDF או תמונה, או לקשר למסמך חיצוני. כל העלאה נשמרת כגרסה, והקודמות נשארות להשוואה.'
                : 'כשיועלה מפרט לאירוע הזה הוא יופיע כאן.'
            }
            action={
              canManage && !adding ? (
                <Button variant="primary" onClick={() => setAdding(true)}>
                  <Upload size={ICON.sm} strokeWidth={STROKE} />
                  העלאת מפרט
                </Button>
              ) : undefined
            }
          />
        )}

        {live.length > 0 && mode === 'view' && right && (
          <SpecPane spec={right} versions={live} onPick={setRightId} />
        )}

        {live.length > 0 && mode === 'compare' && right && left && (
          <div className={cx('grid gap-4', isPhone ? 'grid-cols-1' : 'grid-cols-2')}>
            {/* בעברית הקריאה מימין לשמאל, ולכן החדשה נפתחת מימין. התווית נגזרת
                מהגרסאות עצמן ולא מהצד, כדי שהיא תישאר נכונה אחרי שהמשתמש יחליף
                את הבחירה בבורר. */}
            <SpecPane spec={right} versions={live} onPick={setRightId} sideLabel={sideLabel(right, left)} />
            <SpecPane spec={left} versions={live} onPick={setLeftId} sideLabel={sideLabel(left, right)} />
          </div>
        )}

        {live.length > 0 && (
          <VersionHistory
            specs={live}
            activeId={active?.id ?? null}
            canManage={canManage}
            removing={remove.isPending}
            onRemove={onRemove}
          />
        )}
      </div>
      {dialog}
    </Modal>
  )
}

/** אין תווית כששתי החלוניות מציגות את אותה גרסה — אז אין מה להשוות. */
function sideLabel(self: EventSpec, other: EventSpec): string | undefined {
  if (self.version === other.version) return undefined
  return self.version > other.version ? 'חדשה יותר' : 'ישנה יותר'
}

/* ===== חלונית אחת ========================================================= */

function SpecPane({
  spec,
  versions,
  onPick,
  sideLabel,
}: {
  spec: EventSpec
  versions: EventSpec[]
  onPick: (id: string) => void
  sideLabel?: string
}) {
  const toast = useToast()
  const { data: url, isLoading, error } = useSpecSignedUrl(spec)
  const kind = specViewerKind(spec)

  async function download() {
    try {
      const href = await specDownloadUrl(spec)
      if (!href) return
      // לא window.open: הכתובת נוצרת אחרי await, ופתיחת חלון שאינה בתוך מחוות
      // המשתמש נחסמת. הכתובת החתומה כבר נושאת Content-Disposition: attachment,
      // ולכן קליק על עוגן מוריד את הקובץ ואינו מנווט מהעמוד.
      const a = document.createElement('a')
      a.href = href
      a.rel = 'noopener'
      a.target = '_blank'
      document.body.appendChild(a)
      a.click()
      a.remove()
    } catch (e) {
      toast.error(errorMessage(e))
    }
  }

  return (
    <section className="flex min-w-0 flex-col overflow-hidden rounded-xl border border-line-subtle bg-surface">
      <header className="sticky top-0 z-10 flex flex-wrap items-center gap-2 border-b border-line-subtle bg-subtle/60 px-3 py-2">
        {sideLabel && <span className="type-caption text-ink-tertiary">{sideLabel}</span>}
        <Select
          selectSize="sm"
          value={spec.id}
          onChange={(e) => onPick(e.target.value)}
          aria-label="בחירת גרסה"
          className="min-w-40"
        >
          {versions.map((v) => (
            <option key={v.id} value={v.id}>
              גרסה {v.version} · {fmtDate(v.created_at)}
            </option>
          ))}
        </Select>
        <span className="min-w-0 flex-1 truncate type-caption text-ink-tertiary">
          {spec.title?.trim() || (spec.source === 'file' ? spec.file_name : spec.url)}
        </span>
        <IconButton label="הורדה" size="sm" onClick={() => void download()}>
          <Download size={ICON.sm} strokeWidth={STROKE} />
        </IconButton>
        {url && (
          <a
            href={url}
            target="_blank"
            rel="noreferrer noopener"
            title="פתיחה בלשונית חדשה"
            aria-label="פתיחה בלשונית חדשה"
            className="inline-flex h-8 w-8 items-center justify-center rounded-lg text-ink-tertiary hover:bg-subtle hover:text-ink focus-visible:outline-none focus-visible:focus-ring"
          >
            <ExternalLink size={ICON.sm} strokeWidth={STROKE} />
          </a>
        )}
      </header>

      <div className="min-h-[24rem] grow bg-subtle/30" style={{ height: 'min(70vh, 44rem)' }}>
        {isLoading && (
          <div className="flex h-full items-center justify-center">
            <Spinner />
          </div>
        )}
        {error && <ErrorState error={error} />}
        {!isLoading && !error && url && <SpecViewer kind={kind} url={url} spec={spec} onDownload={download} />}
      </div>
    </section>
  )
}

function SpecViewer({
  kind,
  url,
  spec,
  onDownload,
}: {
  kind: ReturnType<typeof specViewerKind>
  url: string
  spec: EventSpec
  onDownload: () => void
}) {
  if (kind === 'pdf') {
    return (
      <object data={url} type="application/pdf" className="h-full w-full">
        {/* דפדפני מובייל רבים אינם מטמיעים PDF כלל, ואז ה-object נשאר ריק */}
        <iframe src={url} title={spec.file_name ?? 'מפרט'} className="h-full w-full border-0" />
      </object>
    )
  }

  if (kind === 'image') {
    return (
      <div className="h-full overflow-auto p-2">
        <img src={url} alt={spec.file_name ?? 'מפרט'} className="mx-auto max-w-full object-contain" />
      </div>
    )
  }

  if (kind === 'link') {
    return (
      <div className="flex h-full flex-col">
        {/* אתרים רבים חוסמים הטמעה ב-iframe. בלי המוצא הזה החלונית פשוט ריקה,
            והמשתמש חושב שהקישור שבור. */}
        <div className="flex flex-wrap items-center gap-2 border-b border-line-subtle bg-surface px-3 py-2">
          <Link2 size={ICON.sm} strokeWidth={STROKE} className="text-ink-tertiary" />
          <span className="min-w-0 flex-1 truncate type-caption text-ink-tertiary" dir="ltr">
            {spec.url}
          </span>
          <a href={url} target="_blank" rel="noreferrer noopener" className="type-caption font-semibold text-primary">
            פתיחה בלשונית חדשה
          </a>
        </div>
        <iframe src={url} title={spec.url ?? 'מפרט'} className="w-full grow border-0" />
      </div>
    )
  }

  return (
    <EmptyState
      art="box"
      title="אין תצוגה מוטמעת לקובץ הזה"
      description={`${spec.file_name ?? ''} ${formatBytes(spec.size_bytes)}`.trim()}
      action={
        <Button onClick={onDownload}>
          <Download size={ICON.sm} strokeWidth={STROKE} />
          הורדה
        </Button>
      }
    />
  )
}

/* ===== היסטוריית הגרסאות ================================================== */

function VersionHistory({
  specs,
  activeId,
  canManage,
  removing,
  onRemove,
}: {
  specs: EventSpec[]
  activeId: string | null
  canManage: boolean
  removing: boolean
  onRemove: (spec: EventSpec) => void
}) {
  return (
    <section className="rounded-xl border border-line-subtle">
      <h3 className="border-b border-line-subtle px-3 py-2 type-caption font-semibold text-ink-secondary">
        היסטוריית גרסאות
      </h3>
      <ul className="divide-y divide-line-subtle">
        {specs.map((s) => (
          <li key={s.id} className="flex flex-wrap items-center gap-2 px-3 py-2">
            <span className="type-caption tabular font-semibold text-ink">גרסה {s.version}</span>
            {s.id === activeId && <StatusPill color="#16a34a">פעיל</StatusPill>}
            {s.source === 'link' ? (
              <Link2 size={ICON.sm} strokeWidth={STROKE} className="text-ink-tertiary" />
            ) : specViewerKind(s) === 'image' ? (
              <ImageIcon size={ICON.sm} strokeWidth={STROKE} className="text-ink-tertiary" />
            ) : (
              <FileText size={ICON.sm} strokeWidth={STROKE} className="text-ink-tertiary" />
            )}
            <span className="min-w-0 flex-1 truncate type-caption text-ink-secondary">
              {s.title?.trim() || (s.source === 'file' ? s.file_name : s.url)}
            </span>
            <span className="type-caption text-ink-tertiary">{formatBytes(s.size_bytes)}</span>
            <span className="type-caption text-ink-tertiary">{s.uploader_name}</span>
            <span className="type-caption tabular text-ink-tertiary">{fmtDate(s.created_at)}</span>
            {canManage && (
              <IconButton label={`הסרת גרסה ${s.version}`} size="sm" disabled={removing} onClick={() => onRemove(s)}>
                <Trash2 size={ICON.sm} strokeWidth={STROKE} />
              </IconButton>
            )}
          </li>
        ))}
      </ul>
    </section>
  )
}

/* ===== הוספת גרסה ========================================================= */

function AddSpecForm({ eventId, onDone }: { eventId: string; onDone: () => void }) {
  const toast = useToast()
  const upload = useUploadSpec(eventId)
  const fileRef = useRef<HTMLInputElement>(null)
  const [tab, setTab] = useState<'file' | 'link'>('file')
  const [file, setFile] = useState<File | null>(null)
  const [url, setUrl] = useState('')
  const [title, setTitle] = useState('')
  const [problem, setProblem] = useState<string | null>(null)

  function pick(f: File | null) {
    setProblem(f ? validateSpecFile(f) : null)
    setFile(f)
  }

  async function submit() {
    const issue = tab === 'file' ? (file ? validateSpecFile(file) : 'צריך לבחור קובץ') : validateSpecUrl(url)
    if (issue) return setProblem(issue)
    try {
      await upload.mutateAsync(tab === 'file' ? { file: file!, title } : { url, title })
      toast.success('המפרט נוסף כגרסה חדשה')
      onDone()
    } catch (e) {
      toast.error(errorMessage(e))
    }
  }

  return (
    <div className="space-y-3 rounded-xl border border-line-subtle bg-subtle/40 p-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <SegmentedControl<'file' | 'link'>
          value={tab}
          onChange={(k) => {
            setTab(k)
            setProblem(null)
          }}
          items={[
            { key: 'file', label: 'קובץ', icon: <Upload size={ICON.sm} strokeWidth={STROKE} /> },
            { key: 'link', label: 'קישור', icon: <Link2 size={ICON.sm} strokeWidth={STROKE} /> },
          ]}
        />
        {/* המספר עצמו נקבע בשרת תחת נעילה, ולכן הוא אינו מובטח כאן */}
        <span className="type-caption text-ink-tertiary">תישמר כגרסה חדשה</span>
      </div>

      {tab === 'file' ? (
        <Field label="קובץ" hint="PDF או תמונה, עד 25MB" error={problem ?? undefined}>
          <div className="flex flex-wrap items-center gap-2">
            <Button onClick={() => fileRef.current?.click()}>
              <Upload size={ICON.sm} strokeWidth={STROKE} />
              בחירת קובץ
            </Button>
            <span className="min-w-0 flex-1 truncate type-caption text-ink-secondary">
              {file ? `${file.name} · ${formatBytes(file.size)}` : 'לא נבחר קובץ'}
            </span>
            <input
              ref={fileRef}
              type="file"
              accept={SPEC_ACCEPT}
              className="hidden"
              onChange={(e) => {
                pick(e.target.files?.[0] ?? null)
                // בלי האיפוס, בחירה חוזרת של אותו קובץ אינה מפעילה change
                if (fileRef.current) fileRef.current.value = ''
              }}
            />
          </div>
        </Field>
      ) : (
        <Field label="קישור למסמך" error={problem ?? undefined}>
          <Input
            value={url}
            dir="ltr"
            placeholder="https://..."
            onChange={(e) => {
              setUrl(e.target.value)
              setProblem(null)
            }}
          />
        </Field>
      )}

      <Field label="כותרת" hint="לא חובה — למשל ״אחרי הסיור באולם״">
        <Input value={title} onChange={(e) => setTitle(e.target.value)} />
      </Field>

      <div className="flex justify-end gap-2">
        <Button onClick={onDone} disabled={upload.isPending}>
          ביטול
        </Button>
        <Button variant="primary" loading={upload.isPending} onClick={() => void submit()}>
          שמירה
        </Button>
      </div>
    </div>
  )
}
