import { useState } from 'react'
import type { CSSProperties } from 'react'
import { Link } from 'react-router'
import { ChevronLeft, ICON, STROKE, SlidersHorizontal } from '../components/ui/icons'
import { Button, Card, EmptyState, PageHeader } from '../components/ui'
import { useAuth } from '../state/auth'
import { HomePrefModal } from './HomePrefModal'
import { useHomePref, useVisibleSections } from './useHomePref'
import { launcherTiles } from './homePref'
import type { NavTone } from './nav'

/* אותו גוון של הקבוצה כמו בתפריט, כדי שהכפתור ייראה כמו הרשומה שלו */
const toneStyle = (tone: NavTone | undefined): CSSProperties =>
  tone === undefined
    ? { color: 'var(--color-primary-text)', backgroundColor: 'var(--color-primary-subtle)' }
    : {
        color: `var(--vl-ev-${tone})`,
        backgroundColor: `color-mix(in srgb, var(--vl-ev-${tone}) 13%, transparent)`,
      }

function greeting(hour: number) {
  if (hour < 5) return 'לילה טוב'
  if (hour < 12) return 'בוקר טוב'
  if (hour < 17) return 'צהריים טובים'
  if (hour < 21) return 'ערב טוב'
  return 'לילה טוב'
}

/**
 * דף הפתיחה: כפתורים גדולים למסכים שהמשתמש בחר — ושום שאילתה. זו כל הנקודה:
 * הדשבורד מריץ עשרות שאילתות בכל כניסה, וכאן הכניסה עולה רק את
 * `get_my_permissions` שכבר נטען ממילא. ראו homePref.ts.
 */
export default function StartPage() {
  const me = useAuth((s) => s.me)
  const pref = useHomePref()
  const sections = useVisibleSections()
  const groups = launcherTiles(pref, sections)
  const [editing, setEditing] = useState(false)

  const now = new Date() // תצוגה בלבד — לא לוגיקה עסקית
  const firstName = me?.profile.full_name?.split(' ')[0] ?? ''
  const today = now.toLocaleDateString('he-IL', { weekday: 'long', day: 'numeric', month: 'long' })

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <PageHeader
        title={`${greeting(now.getHours())}${firstName ? `, ${firstName}` : ''}`}
        subtitle={`${today} · לאן ממשיכים?`}
        actions={
          <Button variant="ghost" size="sm" onClick={() => setEditing(true)}>
            <SlidersHorizontal size={ICON.sm} strokeWidth={STROKE} />
            התאמה אישית
          </Button>
        }
      />

      {groups.length === 0 ? (
        <Card>
          <EmptyState
            art="search"
            title="אין כפתורים בדף הפתיחה"
            description="בחר אילו מסכים יופיעו כאן."
            action={
              <Button variant="primary" onClick={() => setEditing(true)}>
                בחירת מסכים
              </Button>
            }
          />
        </Card>
      ) : (
        groups.map(({ section, items }) => (
          <section key={section.id} aria-labelledby={`start-${section.id}`}>
            <h2 id={`start-${section.id}`} className="mb-2.5 type-label font-semibold text-ink-tertiary">
              {section.title}
            </h2>
            <ul className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
              {items.map((item) => {
                const Icon = item.icon
                return (
                  <li key={item.to}>
                    <Link
                      to={item.to}
                      className="group flex h-full min-h-28 flex-col justify-between gap-3 rounded-2xl border border-line-subtle bg-surface p-4 shadow-sm transition hover:-translate-y-0.5 hover:border-line hover:shadow-md focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary active:translate-y-0"
                    >
                      <span
                        className="grid size-11 place-items-center rounded-xl"
                        style={toneStyle(section.tone)}
                        aria-hidden
                      >
                        <Icon size={22} strokeWidth={STROKE} />
                      </span>
                      <span className="flex items-center justify-between gap-2">
                        <span className="type-body font-semibold leading-tight">{item.label}</span>
                        <ChevronLeft
                          size={ICON.sm}
                          className="shrink-0 text-ink-tertiary opacity-0 transition group-hover:opacity-100"
                          aria-hidden
                        />
                      </span>
                    </Link>
                  </li>
                )
              })}
            </ul>
          </section>
        ))
      )}

      <HomePrefModal open={editing} onClose={() => setEditing(false)} />
    </div>
  )
}
