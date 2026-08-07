/**
 * טבלת השיבוץ: שורה לעובד, עמודה ליום.
 *
 * זו התצוגה הקלאסית של לוח משמרות, והיא ברירת המחדל כי היא היחידה שעונה על
 * "מי עובד מתי" במבט אחד גם כשיש שישים אנשים. אין כאן וירטואליזציה בכוונה:
 * העמודות הן שלוש או שבע, ומספר השורות חסום ברוסטר.
 *
 * הדבר היחיד שדורש זהירות כאן הוא שהעמודה הדביקה ואזור הימים הם *שני* עצים
 * שחייבים להישאר מיושרים לפיקסל. לכן שניהם עוברים על אותו מערך מוכן מראש,
 * וכל גובה משותף הוא קבוע ולא נגזר מהתוכן.
 */
import { useMemo, useState } from 'react'
import { format, isSameDay } from 'date-fns'
import { he } from 'date-fns/locale'
import { ChevronDown, ICON, STROKE } from '../../components/ui/icons'
import { Badge, cx } from '../../components/ui'
import { toISODate } from '../../lib/dates'
import { fmtDuration } from './shiftFormat'
import { ShiftChip } from './ShiftChip'
import { cellKey } from './shiftBoard'
import type { PlannedShift, ShiftRosterEntry } from '../../types/domain'

const NAME_W = 168
const NAME_W_NARROW = 112
const MIN_COL = 144
const MIN_COL_NARROW = 100
/** גבהים משותפים לשני העצים. כל שינוי כאן חייב להיות בשניהם, ולכן הם קבועים. */
const HEAD_H = 46
const BAND_H = 26
const ROW_MIN_H = 56

interface Row {
  person: ShiftRosterEntry
  /** שם הקבלן, כשהשורה הזאת פותחת גוש חדש */
  band: string | null
}

export function ShiftRosterGrid({
  rows,
  empty,
  days,
  byCell,
  totals,
  narrow,
  onOpen,
}: {
  rows: ShiftRosterEntry[]
  empty: ShiftRosterEntry[]
  days: Date[]
  byCell: Map<string, PlannedShift[]>
  totals: Map<string, { hours: number; count: number }>
  /** מסך צר: העמודות והשמות מצטמצמים, והלוח נגלל אופקית */
  narrow: boolean
  onOpen: (shift: PlannedShift, employeeName: string) => void
}) {
  const [openEmpty, setOpenEmpty] = useState(false)
  const nameW = narrow ? NAME_W_NARROW : NAME_W
  const minCol = narrow ? MIN_COL_NARROW : MIN_COL
  const today = new Date()

  // הרוסטר מגיע ממוין מהשרת (עובדי החברה, ואז כל קבלן כגוש), ולכן פתיחת גוש
  // היא פשוט "שם הקבלן השתנה" — מעבר אחד, ובלי לקבץ מחדש כאן.
  const list = useMemo<Row[]>(
    () =>
      rows.map((person, i) => {
        const group = person.contractor_name ?? null
        const prev = i > 0 ? (rows[i - 1].contractor_name ?? null) : null
        return { person, band: group && group !== prev ? group : null }
      }),
    [rows],
  )

  return (
    <div className="surface overflow-hidden">
      <div className="overflow-auto">
        <div className="flex min-w-max">
          {/* עמודת העובדים. insetInlineStart ולא left — אחרת ב-RTL היא נדבקת
              לצד שממנו גוללים ולא לצד שאליו מסתכלים. */}
          <div
            className="sticky z-30 shrink-0 border-e border-line bg-surface"
            style={{ insetInlineStart: 0, width: nameW }}
          >
            <div className="sticky top-0 z-10 border-b border-line bg-subtle" style={{ height: HEAD_H }} />
            {list.map(({ person, band }) => (
              <div key={person.id}>
                {band && (
                  <div
                    className="flex items-center truncate border-b border-line bg-[var(--vl-board-band)] px-2 type-overline"
                    style={{ height: BAND_H }}
                  >
                    {band}
                  </div>
                )}
                <EmployeeCell person={person} total={totals.get(person.id)} />
              </div>
            ))}
          </div>

          {/* אזור הימים */}
          <div
            className="grid flex-1"
            style={{ gridTemplateColumns: `repeat(${days.length}, minmax(${minCol}px, 1fr))` }}
          >
            {days.map((d) => (
              <DayHeader key={d.toISOString()} date={d} isToday={isSameDay(d, today)} />
            ))}
            {list.map(({ person, band }) => (
              <RowCells
                key={person.id}
                person={person}
                days={days}
                byCell={byCell}
                band={!!band}
                colCount={days.length}
                onOpen={onOpen}
              />
            ))}
          </div>
        </div>
      </div>

      {empty.length > 0 && (
        <div className="border-t border-line">
          <button
            onClick={() => setOpenEmpty((v) => !v)}
            aria-expanded={openEmpty}
            className="flex w-full items-center gap-2 px-3 py-2 type-caption text-ink-tertiary transition-colors hover:bg-hover"
          >
            <ChevronDown
              size={ICON.sm}
              strokeWidth={STROKE}
              className={cx('transition-transform', !openEmpty && 'rotate-90 rtl:-rotate-90')}
            />
            {empty.length} עובדים ללא משמרות בטווח
          </button>
          {/* רשימת צ׳יפים ולא שורות ריקות בטבלה: שורה ריקה לכל אדם הייתה
              משלשת את גובה הלוח בלי להוסיף מידע. */}
          {openEmpty && (
            <div className="flex flex-wrap gap-1.5 px-3 pb-3">
              {empty.map((e) => (
                <span
                  key={e.id}
                  className="inline-flex items-center gap-1 rounded-full border border-line bg-subtle px-2 py-0.5 type-caption"
                >
                  {e.full_name}
                  {e.contractor_name && <span className="opacity-60">· {e.contractor_name}</span>}
                  {!e.is_active && <span className="text-warning-text">· לא פעיל</span>}
                </span>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  )
}

function EmployeeCell({ person, total }: { person: ShiftRosterEntry; total?: { hours: number; count: number } }) {
  return (
    <div
      className="flex flex-col justify-center gap-0.5 border-b border-line-subtle px-2 py-1.5"
      style={{ minHeight: ROW_MIN_H }}
    >
      <span className="truncate type-body font-medium">{person.full_name}</span>
      <span className="flex items-center gap-1 truncate type-caption text-ink-tertiary">
        {total && (
          <span className="tabular">
            {total.count} · {fmtDuration(total.hours)} ש׳
          </span>
        )}
        {!person.is_active && (
          <Badge tone="warning" className="shrink-0">
            לא פעיל
          </Badge>
        )}
      </span>
    </div>
  )
}

function DayHeader({ date, isToday }: { date: Date; isToday: boolean }) {
  return (
    <div
      className={cx(
        'sticky top-0 z-20 flex flex-col items-center justify-center border-b border-s border-line',
        isToday ? 'bg-[var(--vl-board-today)]' : 'bg-subtle',
      )}
      style={{ height: HEAD_H }}
    >
      <span className="type-caption font-semibold">{format(date, 'EEEE', { locale: he })}</span>
      <span className="type-caption tabular text-ink-tertiary">{format(date, 'dd/MM')}</span>
    </div>
  )
}

function RowCells({
  person,
  days,
  byCell,
  band,
  colCount,
  onOpen,
}: {
  person: ShiftRosterEntry
  days: Date[]
  byCell: Map<string, PlannedShift[]>
  band: boolean
  colCount: number
  onOpen: (shift: PlannedShift, employeeName: string) => void
}) {
  return (
    <>
      {/* התאום של פס הקבלן שבעמודה הדביקה. ריק, אבל בדיוק באותו גובה. */}
      {band && (
        <div
          className="border-b border-line bg-[var(--vl-board-band)]"
          style={{ gridColumn: `span ${colCount}`, height: BAND_H }}
        />
      )}
      {days.map((d) => {
        const shifts = byCell.get(cellKey(person.id, toISODate(d))) ?? []
        return (
          <div
            key={d.toISOString()}
            className="flex flex-col gap-1 border-b border-s border-line-subtle p-1"
            style={{ minHeight: ROW_MIN_H }}
          >
            {shifts.map((s) => (
              <ShiftChip key={`${s.work_date}-${s.seq}`} shift={s} onClick={() => onOpen(s, person.full_name)} />
            ))}
          </div>
        )
      })}
    </>
  )
}
