import { cx } from '../../components/ui'
import { useAuth } from '../../state/auth'
import { useMissionsBoard } from './missionQueries'

/**
 * התג האדום ליד "חדר המלחמה" בתפריט — כמה מהמשימות שלי באיחור. אותה שאילתה
 * של הלוח ("שלי"), כך שהדף והתג אינם מתווכחים זה עם זה.
 */
export function CommandNavBadge({ compact }: { compact?: boolean }) {
  const meId = useAuth((s) => s.me?.profile.id ?? '')
  const isAdmin = useAuth((s) => !!s.me?.profile.is_admin)
  const { data } = useMissionsBoard(meId, !!meId && isAdmin)
  const n = data?.overdue ?? 0
  if (!n) return null
  return (
    <span
      className={cx(
        'inline-flex shrink-0 items-center justify-center rounded-full bg-error font-bold text-white tabular',
        compact ? 'absolute -top-0.5 end-0.5 min-w-4 px-1 text-[10px] leading-4' : 'ms-auto min-w-5 px-1.5 text-[11px] leading-5',
      )}
      aria-label={`${n} משימות באיחור`}
    >
      {n}
    </span>
  )
}
