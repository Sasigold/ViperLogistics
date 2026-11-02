import { useEffect, useState } from 'react'
import { Button, Checkbox, Field, Modal, Radio, Select, useToast } from '../components/ui'
import { supabase } from '../lib/supabase'
import { errorMessage } from '../lib/errors'
import { useHomePref, useVisibleSections } from './useHomePref'
import { HOME_PREF_KEY, START_PATH, destinations } from './homePref'
import type { HomePref } from './homePref'

type LandingMode = 'auto' | 'start' | 'page'

const modeOf = (landing: string): LandingMode =>
  landing === 'auto' ? 'auto' : landing === START_PATH ? 'start' : 'page'

/**
 * "דף הבית שלי": לאן נוחתים בכניסה, ואילו כפתורים מופיעים בדף הפתיחה.
 * נשמר ב-user_metadata, ולכן עובר לכל מכשיר שהמשתמש נכנס ממנו.
 */
export function HomePrefModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const pref = useHomePref()
  const sections = useVisibleSections()
  const toast = useToast()
  const dests = destinations(sections)
  const allTos = dests.map((d) => d.item.to)

  const [mode, setMode] = useState<LandingMode>(modeOf(pref.landing))
  const [target, setTarget] = useState(pref.landing.startsWith('/') && pref.landing !== START_PATH ? pref.landing : '')
  const [tiles, setTiles] = useState<Set<string>>(new Set(pref.tiles ?? allTos))
  const [saving, setSaving] = useState(false)

  // כל פתיחה מתחילה ממה שנשמר
  useEffect(() => {
    if (!open) return
    setMode(modeOf(pref.landing))
    setTarget(pref.landing.startsWith('/') && pref.landing !== START_PATH ? pref.landing : '')
    setTiles(new Set(pref.tiles ?? allTos))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open])

  const hasDashboard = sections.some((s) => s.items.some((i) => i.to === '/'))
  const pageOptions = dests.filter((d) => d.item.to !== '/')

  const toggle = (to: string, on: boolean) =>
    setTiles((prev) => {
      const next = new Set(prev)
      if (on) next.add(to)
      else next.delete(to)
      return next
    })

  async function save() {
    const landing = mode === 'auto' ? 'auto' : mode === 'start' ? START_PATH : target || 'auto'
    // כל הכפתורים מסומנים = אין רשימה, כדי שמסך חדש שייפתח למשתמש יופיע מעצמו
    const all = allTos.every((t) => tiles.has(t))
    const next: HomePref = all ? { landing } : { landing, tiles: allTos.filter((t) => tiles.has(t)) }
    setSaving(true)
    const { error } = await supabase.auth.updateUser({ data: { [HOME_PREF_KEY]: next } })
    setSaving(false)
    if (error) {
      toast.error(errorMessage(error))
      return
    }
    toast.success('דף הבית נשמר')
    onClose()
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="דף הבית שלי"
      description="לאן נכנסים כשפותחים את המערכת, ואילו כפתורים יופיעו בדף הפתיחה. נשמר לכל המכשירים שלך."
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            ביטול
          </Button>
          <Button variant="primary" loading={saving} disabled={mode === 'page' && !target} onClick={() => void save()}>
            שמירה
          </Button>
        </>
      }
    >
      <div className="space-y-5">
        <fieldset className="space-y-2">
          <legend className="mb-1 type-label font-semibold">דף הנחיתה בכניסה</legend>
          <Radio
            name="landing"
            checked={mode === 'start'}
            onChange={() => setMode('start')}
            label="דף הפתיחה"
            description="כפתורים למסכים שבחרת. נטען מיד ואינו טוען נתונים — מומלץ."
          />
          <Radio
            name="landing"
            checked={mode === 'page'}
            onChange={() => setMode('page')}
            label="מסך מסוים"
            description="נכנסים ישר למסך שתבחר."
          />
          {mode === 'page' && (
            <div className="ps-7">
              <Field label="המסך">
                <Select value={target} onChange={(e) => setTarget(e.target.value)}>
                  <option value="">בחר מסך…</option>
                  {pageOptions.map(({ item, section }) => (
                    <option key={item.to} value={item.to}>
                      {item.label}
                      {section.placement === 'top' ? '' : ` · ${section.title}`}
                    </option>
                  ))}
                </Select>
              </Field>
            </div>
          )}
          <Radio
            name="landing"
            checked={mode === 'auto'}
            onChange={() => setMode('auto')}
            label={hasDashboard ? 'הדשבורד (כמו קודם)' : 'ברירת המחדל'}
            description={hasDashboard ? 'טוען את כל הנתונים של הדשבורד בכל כניסה.' : 'המסך הראשון בתפריט שלך.'}
          />
        </fieldset>

        <fieldset>
          <div className="mb-2 flex items-center justify-between gap-2">
            <legend className="type-label font-semibold">הכפתורים בדף הפתיחה</legend>
            <div className="flex gap-1">
              <Button size="sm" variant="ghost" onClick={() => setTiles(new Set(allTos))}>
                הכול
              </Button>
              <Button size="sm" variant="ghost" onClick={() => setTiles(new Set())}>
                ניקוי
              </Button>
            </div>
          </div>
          <div className="space-y-3">
            {sections.map((s) => {
              const items = dests.filter((d) => d.section.id === s.id).map((d) => d.item)
              if (!items.length) return null
              return (
                <div key={s.id}>
                  <p className="mb-1 type-caption font-medium text-ink-tertiary">
                    {s.placement === 'top' ? 'ראשי' : s.title}
                  </p>
                  <div className="grid grid-cols-1 gap-1 sm:grid-cols-2">
                    {items.map((i) => (
                      <Checkbox
                        key={i.to}
                        label={i.label}
                        checked={tiles.has(i.to)}
                        onChange={(v) => toggle(i.to, v)}
                      />
                    ))}
                  </div>
                </div>
              )
            })}
          </div>
        </fieldset>
      </div>
    </Modal>
  )
}
