/**
 * בחירת מיקום למחסן: חיפוש כתובת, או לחיצה/גרירה על מפה — שתי דרכים
 * לאותה תוצאה, קואורדינטות.
 *
 * Leaflet ישיר ולא react-leaflet, באותו דפוס של ZoneMap.tsx: רכיב אחד עם
 * מחזור חיים אימפרטיבי ברור (סמן יחיד, לא ציור צורה), בלי עטיפה שלא
 * מרוויחה כאן דבר. הקואורדינטות נשמרות [lat, lng] בלי המרה, כמו בכל שאר
 * המפות במוצר.
 */
import { useEffect, useRef } from 'react'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { ICON, MapPin, STROKE } from '../../components/ui/icons'
import { Autocomplete, Field, Input } from '../../components/ui'
import { addressProvider, shortAddress } from '../../lib/address'
import type { AddressSuggestion } from '../../types/domain'

const FALLBACK_CENTER: [number, number] = [31.9, 35.0]
const FALLBACK_ZOOM = 8

export function LocationPicker({
  lat,
  lng,
  onChange,
  addressText,
  onAddressTextChange,
}: {
  lat: number | null
  lng: number | null
  onChange: (lat: number | null, lng: number | null) => void
  addressText: string
  onAddressTextChange: (v: string) => void
}) {
  const holder = useRef<HTMLDivElement>(null)
  const map = useRef<L.Map | null>(null)
  const marker = useRef<L.Marker | null>(null)
  // ה-callback עובר דרך ref כדי שהמאזין שנרשם פעם אחת ב-mount לא ייתלה
  // בסגירה מיושנת.
  const onChangeRef = useRef(onChange)
  onChangeRef.current = onChange

  useEffect(() => {
    if (!holder.current || map.current) return
    const m = L.map(holder.current, {
      center: lat != null && lng != null ? [lat, lng] : FALLBACK_CENTER,
      zoom: lat != null && lng != null ? 15 : FALLBACK_ZOOM,
      zoomControl: true,
    })
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© OpenStreetMap',
      maxZoom: 18,
    }).addTo(m)
    m.on('click', (e: L.LeafletMouseEvent) => onChangeRef.current(e.latlng.lat, e.latlng.lng))
    map.current = m
    // Leaflet מודד את המכל בזמן היצירה. כשהמפה נולדת בתוך מודל שרק עכשיו
    // נפתח, המידה הזו יוצאת אפס והאריחים לא נטענים עד שמזיזים משהו.
    setTimeout(() => m.invalidateSize(), 0)

    return () => {
      m.remove()
      map.current = null
      marker.current = null
    }
  }, [])

  // הסמן: נוצר/זז כשהקואורדינטות משתנות מבחוץ (חיפוש) או מבפנים (לחיצה/גרירה)
  useEffect(() => {
    const m = map.current
    if (!m) return
    if (lat == null || lng == null) {
      marker.current?.remove()
      marker.current = null
      return
    }
    if (!marker.current) {
      marker.current = L.marker([lat, lng], { draggable: true })
        .addTo(m)
        .on('dragend', () => {
          const p = marker.current?.getLatLng()
          if (p) onChangeRef.current(p.lat, p.lng)
        })
    } else {
      marker.current.setLatLng([lat, lng])
    }
    m.panTo([lat, lng])
  }, [lat, lng])

  return (
    <div className="space-y-2">
      <Autocomplete<AddressSuggestion>
        value={addressText}
        onChange={onAddressTextChange}
        onPick={(s) => {
          onAddressTextChange(s.label)
          onChange(s.lat, s.lng)
          map.current?.setView([s.lat, s.lng], 16)
        }}
        placeholder="חיפוש כתובת..."
        minChars={3}
        debounce={400}
        leading={<MapPin size={ICON.sm} strokeWidth={STROKE} />}
        fetcher={(q) => addressProvider.search(q)}
        getKey={(s) => s.place_id}
        emptyText="לא נמצאה כתובת תואמת"
        renderOption={(s) => (
          <>
            <MapPin size={ICON.sm} className="mt-0.5 shrink-0 text-ink-tertiary" strokeWidth={STROKE} aria-hidden />
            <span className="line-clamp-2">{shortAddress(s.label)}</span>
          </>
        )}
      />
      <div
        ref={holder}
        className="h-56 w-full overflow-hidden rounded-lg border border-line-subtle"
        role="application"
        aria-label="מפה לבחירת מיקום"
      />
      <p className="type-caption text-ink-tertiary">אפשר גם ללחוץ על המפה או לגרור את הסמן.</p>
      <div className="grid grid-cols-2 gap-2">
        <Field label="קו רוחב">
          <Input
            inputSize="sm"
            dir="ltr"
            type="number"
            step="any"
            value={lat ?? ''}
            onChange={(e) => onChange(e.target.value === '' ? null : Number(e.target.value), lng)}
          />
        </Field>
        <Field label="קו אורך">
          <Input
            inputSize="sm"
            dir="ltr"
            type="number"
            step="any"
            value={lng ?? ''}
            onChange={(e) => onChange(lat, e.target.value === '' ? null : Number(e.target.value))}
          />
        </Field>
      </div>
    </div>
  )
}
