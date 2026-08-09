import { Component } from 'react'
import type { ErrorInfo, ReactNode } from 'react'
import { Card } from './Card'
import { EmptyState } from './feedback'
import { Button } from './primitives'

/**
 * גבול שגיאה אחד לאפליקציה.
 *
 * לפני זה לא היה אף אחד: שגיאת render בכל מסך — והמסך הכבד ביותר כאן הוא
 * לוח העבודה — הפילה את כל העץ למסך לבן, בלי הודעה ובלי דרך חזרה. `Suspense`
 * מטפל בטעינת chunk, לא בחריגה בזמן render.
 *
 * הוא לא מנסה לתקן את המצב אלא להחזיר שליטה: ניסיון render חוזר למי שנתקל
 * בתקלה חולפת, וניווט לדף הבית למי שלא.
 */
interface Props {
  children: ReactNode
  /** נקרא בכל קריסה — לשם חיבור דיווח שגיאות חיצוני */
  onError?: (error: Error, info: ErrorInfo) => void
}

interface State {
  error: Error | null
}

export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null }

  static getDerivedStateFromError(error: Error): State {
    return { error }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    this.props.onError?.(error, info)
  }

  render() {
    const { error } = this.state
    if (!error) return this.props.children

    return (
      <div className="flex min-h-full items-center justify-center p-4">
        <Card className="mx-auto w-full max-w-lg">
          <EmptyState
            art="alert"
            title="משהו נשבר במסך הזה"
            description={
              <>
                אפשר לנסות לטעון את המסך מחדש, ואם זה חוזר — לחזור לדף הבית
                ולפנות למנהל המערכת.
                {/* ההודעה הייתה מוסתרת בפרודקשן, ולכן דיווח על תקלה חוזרת הגיע
                    תמיד בלי המשפט האחד שמסביר אותה. אין כאן סוד — זו הודעת
                    שגיאה של הדפדפן — והיא מקופלת כדי שלא תתחרה בהוראה שמעליה. */}
                <details className="mt-3 text-start">
                  <summary className="cursor-pointer type-caption text-ink-tertiary">
                    פרטים טכניים
                  </summary>
                  <span
                    className="mt-1.5 block max-h-40 select-text overflow-auto rounded-md bg-subtle p-2 font-mono type-caption"
                    dir="ltr"
                  >
                    {error.name}: {error.message}
                  </span>
                </details>
              </>
            }
            action={
              <>
                <Button variant="primary" size="sm" onClick={() => this.setState({ error: null })}>
                  נסה שוב
                </Button>
                {/* ניווט מלא ולא client-side: אם ה-router עצמו הוא שנשבר,
                    ניווט דרכו יחזיר אותנו בדיוק לאותו מצב */}
                <Button variant="ghost" size="sm" onClick={() => window.location.assign('/')}>
                  חזרה לדף הבית
                </Button>
              </>
            }
          />
        </Card>
      </div>
    )
  }
}
