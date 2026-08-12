import { Button, IconButton, Input, Select } from '../../../components/ui'
import { ArrowDown, ArrowUp, ICON, Plus, STROKE, Trash2 } from '../../../components/ui/icons'
import { LIST_OPS, MAX_FILTERS, OP_LABELS, VALUELESS_OPS } from './widgetSpec'
import type { Catalog, Filter, FilterOp } from './widgetSpec'

/* ===== filters ===========================================================
   Flat and ANDed, capped. `RowShell`'s shape from PricingTab: a title slot,
   up/down, delete.

   Moved out of WidgetBuilderDrawer untouched so the reports screen and the
   widget builder edit filters through the same rows — one implementation,
   two consumers.                                                            */

export function FilterRows({
  fields,
  filters,
  onChange,
}: {
  fields: Catalog['fields']
  filters: Filter[]
  onChange: (next: Filter[]) => void
}) {
  const move = (from: number, to: number) => {
    if (to < 0 || to >= filters.length) return
    const out = [...filters]
    const [m] = out.splice(from, 1)
    out.splice(to, 0, m)
    onChange(out)
  }

  const add = () => {
    const f = fields[0]
    if (!f) return
    onChange([...filters, { id: `f${Date.now()}`, field: f.key, op: f.allowed_ops[0], value: '' }])
  }

  return (
    <div className="space-y-2">
      <div className="flex items-center gap-2">
        <span className="type-body font-semibold text-ink">סינון</span>
        <span className="type-caption text-ink-tertiary">כל התנאים חייבים להתקיים</span>
        <span className="flex-1" />
        <Button size="sm" variant="ghost" onClick={add} disabled={filters.length >= MAX_FILTERS || fields.length === 0}>
          <Plus size={ICON.sm} strokeWidth={STROKE} />
          תנאי
        </Button>
      </div>

      {filters.length === 0 ? (
        <p className="type-caption text-ink-tertiary">אין סינון — נספרות כל השורות בטווח</p>
      ) : (
        <ul className="space-y-2">
          {filters.map((f, i) => (
            <FilterRow
              key={f.id}
              filter={f}
              fields={fields}
              index={i}
              count={filters.length}
              onMove={(to) => move(i, to)}
              onRemove={() => onChange(filters.filter((x) => x.id !== f.id))}
              onChange={(next) => onChange(filters.map((x) => (x.id === f.id ? next : x)))}
            />
          ))}
        </ul>
      )}
    </div>
  )
}

function FilterRow({
  filter,
  fields,
  index,
  count,
  onMove,
  onRemove,
  onChange,
}: {
  filter: Filter
  fields: Catalog['fields']
  index: number
  count: number
  onMove: (to: number) => void
  onRemove: () => void
  onChange: (next: Filter) => void
}) {
  const def = fields.find((f) => f.key === filter.field)
  const known = !!def && def.allowed_ops.includes(filter.op)

  const setField = (key: string) => {
    const next = fields.find((f) => f.key === key)
    onChange({ ...filter, field: key, op: next?.allowed_ops[0] ?? 'eq', value: '' })
  }

  return (
    <li className="rounded-xl border border-line-subtle bg-subtle/30 p-3">
      <div className="mb-2 flex items-center gap-2">
        <span className="min-w-0 flex-1 type-caption text-ink-tertiary">תנאי {index + 1}</span>
        <IconButton label="העברה למעלה" size="sm" disabled={index === 0} onClick={() => onMove(index - 1)}>
          <ArrowUp size={ICON.sm} />
        </IconButton>
        <IconButton label="העברה למטה" size="sm" disabled={index === count - 1} onClick={() => onMove(index + 1)}>
          <ArrowDown size={ICON.sm} />
        </IconButton>
        <IconButton label="מחיקה" size="sm" variant="ghost" onClick={onRemove}>
          <Trash2 size={ICON.sm} className="text-error" />
        </IconButton>
      </div>

      {/* CondEditor's rule, at the level of a filter row: a shape this build
          does not understand is shown read-only and round-trips untouched
          rather than being rewritten into something the author never asked
          for. */}
      {!known ? (
        <p className="type-caption text-ink-tertiary">
          תנאי מותאם — נשמר כפי שהוא ({filter.field} {filter.op})
        </p>
      ) : (
        <div className="grid gap-2 sm:grid-cols-3">
          <Select value={filter.field} onChange={(e) => setField(e.target.value)}>
            {fields.map((f) => (
              <option key={f.key} value={f.key}>
                {f.label_he}
              </option>
            ))}
          </Select>
          <Select value={filter.op} onChange={(e) => onChange({ ...filter, op: e.target.value as FilterOp, value: '' })}>
            {def.allowed_ops.map((op) => (
              <option key={op} value={op}>
                {OP_LABELS[op]}
              </option>
            ))}
          </Select>
          <FilterValue filter={filter} onChange={onChange} numeric={def.kind === 'num'} isDate={def.kind === 'time'} />
        </div>
      )}
    </li>
  )
}

function FilterValue({
  filter,
  onChange,
  numeric,
  isDate,
}: {
  filter: Filter
  onChange: (next: Filter) => void
  numeric: boolean
  isDate: boolean
}) {
  if (VALUELESS_OPS.includes(filter.op)) {
    return <span className="self-center type-caption text-ink-tertiary">ללא ערך</span>
  }

  const type = isDate ? 'date' : numeric ? 'number' : 'text'
  const coerce = (v: string) => (numeric ? Number(v) : v)

  if (filter.op === 'between') {
    const pair = Array.isArray(filter.value) ? filter.value : ['', '']
    return (
      <div className="flex items-center gap-1.5">
        <Input
          type={type}
          value={String(pair[0] ?? '')}
          onChange={(e) => onChange({ ...filter, value: [coerce(e.target.value), pair[1] ?? ''] })}
        />
        <Input
          type={type}
          value={String(pair[1] ?? '')}
          onChange={(e) => onChange({ ...filter, value: [pair[0] ?? '', coerce(e.target.value)] })}
        />
      </div>
    )
  }

  if (LIST_OPS.includes(filter.op)) {
    const list = Array.isArray(filter.value) ? filter.value : []
    return (
      <Input
        placeholder="ערכים מופרדים בפסיק"
        value={list.join(', ')}
        onChange={(e) =>
          onChange({
            ...filter,
            value: e.target.value
              .split(',')
              .map((s) => s.trim())
              .filter(Boolean)
              .map((s) => (numeric ? Number(s) : s)),
          })
        }
      />
    )
  }

  return (
    <Input
      type={type}
      value={Array.isArray(filter.value) ? '' : String(filter.value ?? '')}
      onChange={(e) => onChange({ ...filter, value: coerce(e.target.value) })}
    />
  )
}
