import { MenuItem, MenuLabel, MenuSeparator, Switch, cx } from '../../components/ui'
import {
  AreaChart,
  BarChart3,
  Check,
  ICON,
  LineChart,
  List,
  PieChart,
  Rows3,
  STROKE,
  Table,
} from '../../components/ui/icons'
import { FORM_LABELS, widgetForm } from './dashboardTypes'
import type { OptionSpec, WidgetDef, WidgetForm, WidgetOpts } from './dashboardTypes'

/**
 * One placement's display settings, drawn from data.
 *
 * Two kinds of thing end up in the same menu and it is worth saying why. The
 * *form* is offered by the frame for every widget that declared more than one
 * in `forms`, and needs no per-widget code at all. The rest come from the
 * widget's own `options`, which is a list of `OptionSpec` — so a widget adds a
 * setting by describing it, not by inventing a settings UI that looks slightly
 * different from every other widget's.
 *
 * Everything here is client-side and free: changing a form or a top-N re-draws
 * the rows already in hand. The one option the server reads — the time bucket —
 * is deliberately *not* here but on the view, because `dashboard_sections`
 * takes one options bag for the whole page and a per-card bucket would quietly
 * change the card next to it.
 */

const FORM_ICONS: Record<WidgetForm, typeof BarChart3> = {
  bar: BarChart3,
  row: Rows3,
  line: LineChart,
  area: AreaChart,
  donut: PieChart,
  table: Table,
  list: List,
}

export interface WidgetOptionsProps {
  def: WidgetDef
  opts: WidgetOpts
  onOpt: (key: string, value: string | number | boolean | undefined) => void
}

/** true when there is anything at all to draw — the caller hides the trigger otherwise */
export function hasWidgetOptions(def: WidgetDef): boolean {
  return (def.forms?.length ?? 0) > 1 || (def.options?.length ?? 0) > 0
}

export function WidgetOptions({ def, opts, onOpt }: WidgetOptionsProps) {
  const form = widgetForm(def, opts)

  return (
    <>
      {def.forms && def.forms.length > 1 && (
        <>
          <MenuLabel>צורת תצוגה</MenuLabel>
          {def.forms.map((f) => {
            const I = FORM_ICONS[f]
            const active = f === form
            return (
              <MenuItem
                key={f}
                icon={<I size={ICON.md} strokeWidth={STROKE} aria-hidden />}
                /* the default form is stored as "no opinion", so a widget whose
                   natural form changes later follows it instead of being pinned
                   to whatever it happened to be the day somebody clicked */
                onClick={() => onOpt('form', f === def.forms?.[0] ? undefined : f)}
                shortcut={active ? <Check size={ICON.sm} strokeWidth={STROKE} aria-hidden /> : undefined}
              >
                {FORM_LABELS[f]}
              </MenuItem>
            )
          })}
        </>
      )}

      {def.options?.length ? (
        <>
          {def.forms && def.forms.length > 1 && <MenuSeparator />}
          <MenuLabel>הגדרות</MenuLabel>
          {def.options.map((spec) => (
            <OptionRow key={spec.key} spec={spec} value={opts[spec.key]} onOpt={onOpt} />
          ))}
        </>
      ) : null}
    </>
  )
}

/* ===== one setting ========================================================
   Three shapes, and each is the control the product already uses for that
   shape elsewhere: a switch for a boolean, a segmented row of choices for an
   enum small enough to show, and a stepper for a number. None of them closes
   the menu — changing a top-N and then a sort order is one visit, not two.  */

function OptionRow({
  spec,
  value,
  onOpt,
}: {
  spec: OptionSpec
  value: string | number | boolean | undefined
  onOpt: WidgetOptionsProps['onOpt']
}) {
  if (spec.kind === 'bool') {
    const fallback = spec.defaultOn ?? false
    const on = typeof value === 'boolean' ? value : fallback
    return (
      <span className="flex items-center gap-2.5 rounded-lg px-2.5 py-1.5">
        <span className="min-w-0 flex-1">
          <span className="block truncate text-sm text-ink">{spec.label}</span>
          {spec.hint && <span className="block truncate type-caption text-ink-tertiary">{spec.hint}</span>}
        </span>
        {/* The state that equals the default is stored as no opinion, and the
            other one is stored as itself — which is the only way a
            default-on switch can ever be turned off. */}
        <Switch
          checked={on}
          onChange={(v) => onOpt(spec.key, v === fallback ? undefined : v)}
          aria-label={spec.label}
        />
      </span>
    )
  }

  if (spec.kind === 'enum') {
    const current = typeof value === 'string' ? value : spec.choices[0]?.value
    return (
      <span className="block px-2.5 py-1.5">
        <span className="mb-1 block type-caption text-ink-tertiary">{spec.label}</span>
        <span className="flex flex-wrap gap-1">
          {spec.choices.map((c) => (
            <button
              key={c.value}
              type="button"
              aria-pressed={c.value === current}
              onClick={() => onOpt(spec.key, c.value === spec.choices[0]?.value ? undefined : c.value)}
              className={cx(
                'rounded-md px-2 py-1 type-caption font-semibold transition-colors',
                c.value === current ? 'bg-primary-subtle text-primary-text' : 'text-ink-tertiary hover:bg-hover',
              )}
            >
              {c.label}
            </button>
          ))}
        </span>
      </span>
    )
  }

  /* Three states, not two: a number in range, and — where the spec says the
     absence of one means something ("all rows") — the unset state itself.
     Conflating "unset" with "the minimum" made the minimum unreachable and made
     the menu report 3 while the card drew twelve. */
  const step = spec.step ?? 1
  const hasUnset = spec.unsetLabel !== undefined
  const current = typeof value === 'number' ? value : hasUnset ? null : spec.min
  const atFloor = current === null || current <= spec.min

  const down = () => {
    if (current === null) return
    if (current <= spec.min) return onOpt(spec.key, hasUnset ? undefined : spec.min)
    onOpt(spec.key, Math.max(spec.min, current - step))
  }
  const up = () => {
    if (current === null) return onOpt(spec.key, spec.min)
    onOpt(spec.key, Math.min(spec.max, current + step))
  }

  return (
    <span className="flex items-center gap-2.5 rounded-lg px-2.5 py-1.5">
      <span className="min-w-0 flex-1">
        <span className="block truncate text-sm text-ink">{spec.label}</span>
        {spec.hint && <span className="block truncate type-caption text-ink-tertiary">{spec.hint}</span>}
      </span>
      <span className="flex shrink-0 items-center gap-1">
        <button
          type="button"
          aria-label={`${spec.label} — פחות`}
          disabled={current === null || (atFloor && !hasUnset)}
          onClick={down}
          className="size-6 rounded-md text-ink-tertiary hover:bg-hover disabled:pointer-events-none disabled:opacity-40"
        >
          −
        </button>
        <span className="min-w-10 text-center type-caption tabular font-semibold text-ink">
          {current === null ? spec.unsetLabel : current}
        </span>
        <button
          type="button"
          aria-label={`${spec.label} — יותר`}
          disabled={current !== null && current >= spec.max}
          onClick={up}
          className="size-6 rounded-md text-ink-tertiary hover:bg-hover disabled:pointer-events-none disabled:opacity-40"
        >
          +
        </button>
      </span>
    </span>
  )
}
