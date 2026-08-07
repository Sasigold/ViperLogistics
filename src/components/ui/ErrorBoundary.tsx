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
                התקלה נרשמה. אפשר לנסות לטעון את המסך מחדש, ואם זה חוזר — לחזור
                לדף הבית ולפנות למנהל המערכת.
                {import.meta.env.DEV && (
                  <span className="mt-3 block max-h-40 overflow-auto rounded-md bg-subtle p-2 text-start font-mono type-caption" dir="ltr">
                    {error.message}
                  </span>
                )}
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
