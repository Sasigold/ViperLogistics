import { useEffect, useState } from 'react'
import { loadSlipPdf } from './payslipQueries'

interface SlipRef {
  batch_id: string
  page_from: number
  page_to: number
}

/**
 * כתובת blob לתלוש, לתצוגה ב-iframe. נטען כשהתלוש משתנה ומשוחרר כשעוזבים
 * אותו — כתובת blob שלא שוחררה מחזיקה את הקובץ בזיכרון עד סגירת הלשונית.
 */
export function useSlipPdfUrl(slip: SlipRef | null | undefined) {
  const key = slip ? `${slip.batch_id}|${slip.page_from}|${slip.page_to}` : null
  const [state, setState] = useState<{ key: string | null; url: string | null; error: unknown }>({
    key: null,
    url: null,
    error: null,
  })

  useEffect(() => {
    if (!key) return
    const [batchId, from, to] = key.split('|')
    let url: string | null = null
    let alive = true
    loadSlipPdf(batchId, Number(from), Number(to))
      .then((blob) => {
        if (!alive) return
        url = URL.createObjectURL(blob)
        setState({ key, url, error: null })
      })
      .catch((error: unknown) => {
        if (alive) setState({ key, url: null, error })
      })
    return () => {
      alive = false
      if (url) URL.revokeObjectURL(url)
    }
  }, [key])

  const current = state.key === key
  return {
    url: current ? state.url : null,
    error: current ? state.error : null,
    loading: !!key && !current,
  }
}
