/**
 * Customer colours come from the database and are picked by users against a
 * white background, so a chip painted with one can end up either very light
 * or very dark. These helpers keep the label readable either way and build
 * the soft gradient used on calendar and board chips.
 */

const FALLBACK = '#64748b'

function parseHex(hex: string | null | undefined): [number, number, number] | null {
  if (!hex) return null
  let h = hex.trim().replace('#', '')
  if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2]
  if (h.length !== 6 || /[^0-9a-f]/i.test(h)) return null
  return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)]
}

/** WCAG relative luminance, 0 (black) to 1 (white). */
export function luminance(hex: string | null | undefined): number {
  const rgb = parseHex(hex) ?? parseHex(FALLBACK)!
  const [r, g, b] = rgb.map((v) => {
    const s = v / 255
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4
  })
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

/** Black or white — whichever actually reads on the given fill. */
export function readableOn(hex: string | null | undefined): string {
  return luminance(hex) > 0.55 ? '#0b0d12' : '#ffffff'
}

export interface ChipPaint {
  background: string
  color: string
  railColor: string
  borderColor: string
}

/** The filled treatment used for calendar events. */
export function chipPaint(hex: string | null | undefined): ChipPaint {
  const c = hex || FALLBACK
  const dark = luminance(c) <= 0.55
  return {
    background: `linear-gradient(160deg, ${c} 0%, color-mix(in srgb, ${c} 82%, ${dark ? '#000' : '#fff'}) 100%)`,
    color: readableOn(c),
    railColor: `color-mix(in srgb, ${c} 65%, #000)`,
    borderColor: `color-mix(in srgb, ${c} 78%, #000)`,
  }
}

/** The tinted treatment used where a filled chip would be too loud. */
export function softPaint(hex: string | null | undefined) {
  const c = hex || FALLBACK
  return {
    background: `color-mix(in srgb, ${c} 12%, transparent)`,
    borderColor: `color-mix(in srgb, ${c} 32%, transparent)`,
    color: c,
  }
}
