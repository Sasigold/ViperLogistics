/**
 * מפת אזורי הנסיעה.
 *
 * Leaflet ולא react-leaflet: המפה כאן היא רכיב אחד עם מחזור חיים אימפרטיבי
 * ברור — צייר, ערוך, נקה — ועטיפה מוצהרת הייתה מוסיפה שכבה בלי להרוויח דבר.
 * הציור נכתב ידנית ולא דרך leaflet-draw, כי כל מה שנדרש הוא "לחיצה מוסיפה
 * קודקוד" ו"לחיצה מציבה מרכז", ותוסף שלם עבור זה הוא חבילה שצריך לתחזק.
 *
 * הקואורדינטות נשמרות [lat, lng] — הסדר של Leaflet, של events.location_lat
 * ושל app.point_in_polygon במיגרציה 0017. אין המרה בשום נקודה.
 */
import { useEffect, useRef } from 'react'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import type { PricingZone } from '../../types/domain'

/** מרכז הארץ, כשאין עדיין שום אזור להתמקד בו. */
const FALLBACK_CENTER: [number, number] = [31.9, 35.0]
const FALLBACK_ZOOM = 8

export type DraftShape =
  | { shape: 'polygon'; points: [number, number][] }
  | { shape: 'circle'; center: [number, number] | null; radius_km: number }

export function ZoneMap({
  zones,
  selectedId,
  draft,
  onDraftChange,
  onSelect,
  className,
}: {
  zones: PricingZone[]
  selectedId: string | null
  /** כשהוא קיים המפה במצב ציור, ולחיצה עליה משנה את הטיוטה */
  draft: DraftShape | null
  onDraftChange: (d: DraftShape) => void
  onSelect: (id: string) => void
  className?: string
}) {
  const holder = useRef<HTMLDivElement>(null)
  const map = useRef<L.Map | null>(null)
  const layers = useRef<L.LayerGroup | null>(null)
  const draftLayer = useRef<L.LayerGroup | null>(null)

  // ה-callbacks נקראים מתוך מאזין שנרשם פעם אחת, ולכן הם עוברים דרך ref —
  // אחרת כל רינדור היה דורש רישום מחדש של המאזין.
  const cb = useRef({ draft, onDraftChange, onSelect })
  cb.current = { draft, onDraftChange, onSelect }

  useEffect(() => {
    if (!holder.current || map.current) return
    const m = L.map(holder.current, { center: FALLBACK_CENTER, zoom: FALLBACK_ZOOM, zoomControl: true })
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© OpenStreetMap',
      maxZoom: 18,
    }).addTo(m)
    layers.current = L.layerGroup().addTo(m)
    draftLayer.current = L.layerGroup().addTo(m)

    m.on('click', (e: L.LeafletMouseEvent) => {
      const d = cb.current.draft
      if (!d) return
      const point: [number, number] = [e.latlng.lat, e.latlng.lng]
      if (d.shape === 'polygon') cb.current.onDraftChange({ ...d, points: [...d.points, point] })
      else cb.current.onDraftChange({ ...d, center: point })
    })

    map.current = m
    // Leaflet מודד את המכל בזמן היצירה. כשהמפה נולדת בתוך טאב שרק עכשיו
    // נפתח, המידה הזו יוצאת אפס והאריחים לא נטענים עד שמזיזים משהו.
    setTimeout(() => m.invalidateSize(), 0)

    return () => {
      m.remove()
      map.current = null
    }
  }, [])

  // ── האזורים השמורים ──────────────────────────────────────────────────
  useEffect(() => {
    const g = layers.current
    if (!g || !map.current) return
    g.clearLayers()

    const bounds = L.latLngBounds([])
    for (const z of zones) {
      const selected = z.id === selectedId
      const style: L.PathOptions = {
        color: z.color,
        weight: selected ? 3 : 1.5,
        opacity: z.is_active ? 1 : 0.45,
        fillOpacity: selected ? 0.28 : 0.12,
        dashArray: z.customer_id ? undefined : '5 5', // אזור גלובלי מקווקו
      }
      let layer: L.Path | null = null
      if (z.shape === 'polygon' && z.points && z.points.length >= 3) {
        layer = L.polygon(z.points, style)
      } else if (z.shape === 'circle' && z.center_lat != null && z.center_lng != null && z.radius_km) {
        layer = L.circle([z.center_lat, z.center_lng], { ...style, radius: z.radius_km * 1000 })
      }
      if (!layer) continue
      layer.bindTooltip(`${z.name} · ${z.travel_hours} ש׳`, { direction: 'top' })
      layer.on('click', (e) => {
        // בלי זה הלחיצה מגיעה גם למפה ומוסיפה קודקוד בזמן ציור
        L.DomEvent.stopPropagation(e)
        cb.current.onSelect(z.id)
      })
      layer.addTo(g)
      const b = 'getBounds' in layer ? (layer as L.Polygon).getBounds() : null
      if (b) bounds.extend(b)
    }

    if (bounds.isValid()) map.current.fitBounds(bounds, { padding: [24, 24], maxZoom: 12 })
  }, [zones, selectedId])

  // ── הטיוטה שמציירים כרגע ─────────────────────────────────────────────
  useEffect(() => {
    const g = draftLayer.current
    if (!g) return
    g.clearLayers()
    if (!draft) return

    const style: L.PathOptions = { color: '#3563f0', weight: 2, dashArray: '6 4', fillOpacity: 0.15 }
    if (draft.shape === 'polygon') {
      if (draft.points.length >= 3) L.polygon(draft.points, style).addTo(g)
      else if (draft.points.length === 2) L.polyline(draft.points, style).addTo(g)
      // הקודקודים עצמם, כדי שיהיה ברור מה נלחץ וכמה נקודות יש
      draft.points.forEach((p, i) =>
        L.circleMarker(p, { radius: 4, color: '#3563f0', fillColor: '#fff', fillOpacity: 1 })
          .bindTooltip(String(i + 1), { permanent: false })
          .addTo(g),
      )
    } else if (draft.center) {
      L.circle(draft.center, { ...style, radius: draft.radius_km * 1000 }).addTo(g)
      L.circleMarker(draft.center, { radius: 4, color: '#3563f0', fillColor: '#fff', fillOpacity: 1 }).addTo(g)
    }
  }, [draft])

  return <div ref={holder} className={className} style={{ minHeight: 380 }} role="application" aria-label="מפת אזורי נסיעה" />
}
