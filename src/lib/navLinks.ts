/**
 * קישורי ניווט לאתר העבודה — Waze ו-Google Maps.
 *
 * כשיש קואורדינטות הן הקובעות (הכתובת שהוקלדה יכולה להיות "אולם הגן, ליד
 * הצומת"); בלעדיהן מחפשים לפי הטקסט. בטלפון שני הקישורים פותחים את
 * האפליקציה המותקנת, ובמחשב — את האתר.
 */
export interface NavTarget {
  location_text?: string | null
  location_lat?: number | null
  location_lng?: number | null
}

export function navLinks(t: NavTarget): { waze: string; google: string } | null {
  const hasPoint = t.location_lat != null && t.location_lng != null
  const text = t.location_text?.trim()
  if (hasPoint) {
    const ll = `${t.location_lat},${t.location_lng}`
    return {
      waze: `https://waze.com/ul?ll=${ll}&navigate=yes`,
      google: `https://www.google.com/maps/dir/?api=1&destination=${ll}`,
    }
  }
  if (!text) return null
  const q = encodeURIComponent(text)
  return {
    waze: `https://waze.com/ul?q=${q}&navigate=yes`,
    google: `https://www.google.com/maps/dir/?api=1&destination=${q}`,
  }
}
