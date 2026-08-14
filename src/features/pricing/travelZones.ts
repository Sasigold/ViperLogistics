/**
 * החשבון שמאחורי מפת אזורי הנסיעה.
 *
 * זמן הנסיעה של אזור הוא מספר שמישהו מזין, ולא מדידה: אין כאן קריאה לשירות
 * ניווט חיצוני, ולא צריכה להיות אחת — המספר חייב להיות יציב, כי הוא נכנס
 * לאורך המשמרת ולשכר. מה שהקובץ הזה נותן הוא ההקשר שהופך את ההזנה למושכלת:
 * כמה רחוק האזור מהמחסן שיוצאים ממנו, ומה המהירות שהמספר שהוזן מתאר.
 *
 * המרחק הוא קו אווירי, ולכן הוא תמיד קצר מהדרך בפועל. זה מוצהר בכל מקום
 * שבו הוא מוצג, ובכוונה לא מוכפל ב"מקדם כביש" — מקדם כזה הוא ניחוש שנראה
 * כמו מדידה.
 */
import type { PricingZone, Warehouse } from '../../types/domain'

export type LatLng = [number, number]

const R_KM = 6371

/** אותו חישוב של app.haversine_km (0017), כדי שהמסך והשרת ימדדו אותו דבר. */
export function haversineKm(a: LatLng, b: LatLng): number {
  const rad = (d: number) => (d * Math.PI) / 180
  const dLat = rad(b[0] - a[0])
  const dLng = rad(b[1] - a[1])
  const h =
    Math.sin(dLat / 2) ** 2 + Math.cos(rad(a[0])) * Math.cos(rad(b[0])) * Math.sin(dLng / 2) ** 2
  return R_KM * 2 * Math.asin(Math.min(1, Math.sqrt(h)))
}

/**
 * הנקודה שמייצגת את האזור. לעיגול זה המרכז; לפוליגון זה ממוצע הקודקודים —
 * צנטרואיד ולא מרכז שטח, כי ההפרש ביניהם קטן מדיוק המדידה כאן ממילא.
 */
export function zoneCenter(
  zone: Pick<PricingZone, 'shape' | 'points' | 'center_lat' | 'center_lng'>,
): LatLng | null {
  if (zone.shape === 'circle') {
    return zone.center_lat != null && zone.center_lng != null ? [zone.center_lat, zone.center_lng] : null
  }
  const pts = zone.points ?? []
  if (pts.length === 0) return null
  const sum = pts.reduce<[number, number]>((acc, p) => [acc[0] + p[0], acc[1] + p[1]], [0, 0])
  return [sum[0] / pts.length, sum[1] / pts.length]
}

/** המחסן הקרוב ביותר לנקודה, ומרחקו בקו אווירי. מחסן בלי קואורדינטות אינו מועמד. */
export function nearestWarehouse(
  point: LatLng | null,
  warehouses: Warehouse[],
): { warehouse: Warehouse; km: number } | null {
  if (!point) return null
  let best: { warehouse: Warehouse; km: number } | null = null
  for (const w of warehouses) {
    if (w.lat == null || w.lng == null) continue
    const km = haversineKm(point, [w.lat, w.lng])
    if (!best || km < best.km) best = { warehouse: w, km }
  }
  return best
}

/**
 * המהירות שזמן הנסיעה שהוזן מתאר, מול המרחק האווירי. null כשאין מה להשוות.
 * מספר גבוה מדי אומר שהזמן קצר מכדי לכסות את הדרך, ולא שהנהג מהיר.
 */
export function impliedSpeedKmh(km: number | null, hours: number | null | undefined): number | null {
  if (km == null || !hours || hours <= 0 || km <= 0) return null
  return Math.round(km / hours)
}

/** הלוך-חזור: מה שהעובד באמת נוסע ביום עבודה שמתחיל במחסן ומסתיים בו. */
export function roundTripHours(travelHours: number | null | undefined): number {
  return (Number(travelHours) || 0) * 2
}
