import type { ExportSheet } from '../dashboard/exportDashboard'

/**
 * גיליון אחד → CSV. בלי ספרייה: הצורה קטנה מספיק, וספריית CSV הייתה עוד chunk.
 *
 * שני פרטים שאינם קישוט:
 *
 *   • **BOM.** בלעדיו Excel פותח CSV עברי ב-windows-1255 ומציג ג׳יבריש. ה-BOM
 *     הוא הדרך היחידה לומר לו UTF-8 בלי מסך ייבוא.
 *   • **CRLF.** RFC 4180 דורש, ו-Excel בוחר בו מפריד שורות בכל הפלטפורמות.
 */

const BOM = '﻿'

/** RFC 4180: מרכאות סביב שדה שמכיל פסיק, מרכאה או שורה חדשה; מרכאה פנימית מוכפלת */
export function csvField(v: string | number): string {
  const s = String(v)
  return /[",\r\n]/.test(s) ? `"${s.replaceAll('"', '""')}"` : s
}

export function sheetToCsv(sheet: ExportSheet): string {
  const lines = [sheet.columns, ...sheet.rows].map((row) => row.map(csvField).join(','))
  return BOM + lines.join('\r\n') + '\r\n'
}

export function csvBlob(sheet: ExportSheet): Blob {
  return new Blob([sheetToCsv(sheet)], { type: 'text/csv;charset=utf-8' })
}
