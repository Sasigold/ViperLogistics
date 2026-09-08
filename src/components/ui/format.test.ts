/**
 * הפיצול של טקסט חופשי לקישורים.
 *
 * הוא נבדק כאן ולא דרך המסך כי שתי ההכרעות שבו אינן ויזואליות: מה הופך
 * לקישור — רשימת היתר של סכימות, ולא סינון של מה שנראה מסוכן — ומה נשאר
 * טקסט. ערך של שדה מותאם מגיע ממשתמש, ולכן זו הנקודה שבה `javascript:`
 * נעצר.
 */
import { describe, expect, it } from 'vitest'
import { linkifyParts } from './format'

describe('linkifyParts', () => {
  it('ערך שכולו כתובת הוא קישור אחד', () => {
    const url = 'https://erp.eruit.co.il/Order/OrderEvent?eventId=2e7ae1d7'
    expect(linkifyParts(url)).toEqual([{ text: url, href: url }])
  })

  it('כתובת בתוך משפט מפוצלת מהטקסט שסביבה', () => {
    expect(linkifyParts('ראו כאן https://a.co/x לפרטים')).toEqual([
      { text: 'ראו כאן ', href: null },
      { text: 'https://a.co/x', href: 'https://a.co/x' },
      { text: ' לפרטים', href: null },
    ])
  })

  it('נקודה שסוגרת משפט אינה חלק מהכתובת', () => {
    expect(linkifyParts('הקישור: https://a.co/x.')).toEqual([
      { text: 'הקישור: ', href: null },
      { text: 'https://a.co/x', href: 'https://a.co/x' },
      { text: '.', href: null },
    ])
  })

  it('כתובת שנכתבה בלי סכימה מקבלת https', () => {
    expect(linkifyParts('www.eruit.co.il')).toEqual([
      { text: 'www.eruit.co.il', href: 'https://www.eruit.co.il' },
    ])
  })

  it('שתי כתובות באותו טקסט הן שני קישורים', () => {
    const parts = linkifyParts('http://a.co ו-https://b.co')
    expect(parts.filter((p) => p.href)).toHaveLength(2)
  })

  // זו הסיבה שהפיצול הוא רשימת היתר: ערך שדה מגיע ממשתמש, ו-href שנבנה
  // ממנו בלי הגבלה הוא הרצת קוד בלחיצה אחת.
  it('סכימה שאינה http אינה נעשית קישור', () => {
    for (const bad of ['javascript:alert(1)', 'data:text/html,<h1>x', 'file:///etc/passwd']) {
      expect(linkifyParts(bad).every((p) => p.href === null)).toBe(true)
    }
  })

  it('טקסט בלי כתובת נשאר מקטע אחד', () => {
    expect(linkifyParts('אולם הגן, ראשון לציון')).toEqual([
      { text: 'אולם הגן, ראשון לציון', href: null },
    ])
  })

  it('ערך ריק אינו מקטע ריק אלא כלום', () => {
    expect(linkifyParts('')).toEqual([])
    expect(linkifyParts(null)).toEqual([])
    expect(linkifyParts(undefined)).toEqual([])
  })
})
