import { Button, MenuLabel, MenuSeparator, Popover, Switch, cx } from '../../components/ui'
import { ChevronDown, ICON, RefreshCw, STROKE, SlidersHorizontal } from '../../components/ui/icons'
import { BUCKETS, BUCKET_LABELS, PACKINGS, PACKING_LABELS } from './dashboardTypes'
import { DEFAULT_PACKING, LIMIT_MAX, LIMIT_MIN, packingOf } from './layout'
import type { Bucket, Packing, ViewPrefs } from './dashboardTypes'

/**
 * Everything that is true of the whole screen rather than of one card.
 *
 * Three of these four are here rather than on a card for the same reason:
 * `dashboard_sections` takes one options bag for the whole fan-out, so a
 * per-card time bucket would silently change the card beside it. Putting them
 * on the view makes the shared thing look shared — one control, one answer,
 * and a saved view that remembers it.
 *
 * The fourth, packing, is genuinely a property of the grid. It is the answer
 * to "why is half this card empty" on a month with one event, and it is a
 * choice rather than a fix because the two answers trade against each other:
 * see the argument in `layout.ts`.
 */
export function ViewSettingsMenu({
  view,
  onChange,
  onRefresh,
  refreshing,
  updatedAt,
}: {
  view: ViewPrefs | undefined
  onChange: (patch: Partial<ViewPrefs>) => void
  onRefresh: () => void
  refreshing?: boolean
  /** when the sections last landed — a dashboard that cannot say is a dashboard you distrust */
  updatedAt?: string
}) {
  const packing = packingOf(view)
  const bucket = view?.bucket ?? 'week'
  const limit = view?.limit ?? 12
  const refresh = view?.refresh ?? 0

  return (
    <Popover
      align="end"
      trigger={(p) => (
        <Button size="sm" variant="ghost" {...p}>
          <SlidersHorizontal size={ICON.sm} strokeWidth={STROKE} />
          תצוגה
          <ChevronDown size={ICON.sm} strokeWidth={STROKE} aria-hidden />
        </Button>
      )}
    >
      {() => (
        <div className="min-w-64 space-y-1">
          <MenuLabel>סידור הכרטיסים</MenuLabel>
          <Choices
            value={packing}
            values={PACKINGS}
            label={(p: Packing) => PACKING_LABELS[p]}
            onPick={(p) => onChange({ packing: p === DEFAULT_PACKING ? undefined : p })}
          />
          <p className="px-2.5 pb-1 type-caption text-ink-tertiary">
            {packing === 'compact'
              ? 'כל כרטיס בגובה התוכן שלו, והחורים נסגרים'
              : 'כל הכרטיסים בשורה באותו גובה, והמסגרות מיושרות'}
          </p>

          <MenuSeparator />
          <MenuLabel>חלוקת הזמן בגרפי המגמה</MenuLabel>
          <Choices
            value={bucket}
            values={BUCKETS}
            label={(b: Bucket) => BUCKET_LABELS[b]}
            onPick={(b) => onChange({ bucket: b === 'week' ? undefined : b })}
          />

          <MenuSeparator />
          <Stepper
            label="שורות לכל דירוג"
            hint="כמה שורות השרת מחזיר לכל כרטיס מדורג"
            value={limit}
            min={LIMIT_MIN}
            max={LIMIT_MAX}
            step={1}
            onChange={(n) => onChange({ limit: n === 12 ? undefined : n })}
          />

          <MenuSeparator />
          <span className="flex items-center gap-2.5 px-2.5 py-1.5">
            <span className="min-w-0 flex-1">
              <span className="block text-sm text-ink">רענון אוטומטי</span>
              <span className="block type-caption text-ink-tertiary">
                {refresh > 0 ? `כל ${refresh} דקות` : 'כבוי'}
              </span>
            </span>
            <Switch
              checked={refresh > 0}
              onChange={(v) => onChange({ refresh: v ? 5 : undefined })}
              aria-label="רענון אוטומטי"
            />
          </span>
          {refresh > 0 && (
            <Choices
              value={String(refresh)}
              values={['5', '15', '30', '60'] as const}
              label={(m: string) => `${m} דק׳`}
              onPick={(m) => onChange({ refresh: Number(m) })}
            />
          )}

          <MenuSeparator />
          <button
            type="button"
            onClick={onRefresh}
            className="flex w-full items-center gap-2.5 rounded-lg px-2.5 py-1.5 text-start text-sm text-ink transition-colors hover:bg-hover"
          >
            <RefreshCw
              size={ICON.md}
              strokeWidth={STROKE}
              className={cx('shrink-0 text-ink-tertiary', refreshing && 'animate-spin')}
              aria-hidden
            />
            <span className="min-w-0 flex-1">
              רענון עכשיו
              {updatedAt && <span className="block type-caption text-ink-tertiary">עודכן ב-{updatedAt}</span>}
            </span>
          </button>
        </div>
      )}
    </Popover>
  )
}

/* ===== the two controls ===================================================
   Not `SegmentedControl`: that one fills a toolbar and these sit inside a
   menu panel that is already narrow. Same visual language, laid out to wrap. */

function Choices<T extends string>({
  value,
  values,
  label,
  onPick,
}: {
  value: T
  values: readonly T[]
  label: (v: T) => string
  onPick: (v: T) => void
}) {
  return (
    <span className="flex flex-wrap gap-1 px-2.5 py-1">
      {values.map((v) => (
        <button
          key={v}
          type="button"
          aria-pressed={v === value}
          onClick={() => onPick(v)}
          className={cx(
            'rounded-md px-2 py-1 type-caption font-semibold transition-colors',
            v === value ? 'bg-primary-subtle text-primary-text' : 'text-ink-tertiary hover:bg-hover',
          )}
        >
          {label(v)}
        </button>
      ))}
    </span>
  )
}

function Stepper({
  label,
  hint,
  value,
  min,
  max,
  step,
  onChange,
}: {
  label: string
  hint?: string
  value: number
  min: number
  max: number
  step: number
  onChange: (n: number) => void
}) {
  const set = (n: number) => onChange(Math.max(min, Math.min(max, n)))
  return (
    <span className="flex items-center gap-2.5 px-2.5 py-1.5">
      <span className="min-w-0 flex-1">
        <span className="block truncate text-sm text-ink">{label}</span>
        {hint && <span className="block truncate type-caption text-ink-tertiary">{hint}</span>}
      </span>
      <span className="flex shrink-0 items-center gap-1">
        <button
          type="button"
          aria-label={`${label} — פחות`}
          disabled={value <= min}
          onClick={() => set(value - step)}
          className="size-6 rounded-md text-ink-tertiary hover:bg-hover disabled:pointer-events-none disabled:opacity-40"
        >
          −
        </button>
        <span className="w-7 text-center type-caption tabular font-semibold text-ink">{value}</span>
        <button
          type="button"
          aria-label={`${label} — יותר`}
          disabled={value >= max}
          onClick={() => set(value + step)}
          className="size-6 rounded-md text-ink-tertiary hover:bg-hover disabled:pointer-events-none disabled:opacity-40"
        >
          +
        </button>
      </span>
    </span>
  )
}
