import { describe, expect, it } from 'vitest'
import {
  SPEC_MAX_BYTES,
  currentSpec,
  formatBytes,
  pickCompareDefaults,
  specLabel,
  specStoragePath,
  specViewerKind,
  sortedSpecs,
  validateSpecFile,
  validateSpecUrl,
} from './specs'
import type { EventSpec } from '../../types/domain'

const EVENT = '30000000-0000-0000-0000-000000000016'

function spec(over: Partial<EventSpec> & { version: number }): EventSpec {
  return {
    id: `id-${over.version}`,
    event_id: EVENT,
    source: 'file',
    storage_path: `${EVENT}/file-${over.version}.pdf`,
    file_name: `מפרט ${over.version}.pdf`,
    mime_type: 'application/pdf',
    size_bytes: 1000,
    url: null,
    title: null,
    note: null,
    uploaded_by: null,
    uploader_name: 'רכזת',
    created_at: '2026-08-18T09:00:00Z',
    deleted_at: null,
    ...over,
  }
}

describe('specViewerKind', () => {
  it('reads the MIME type first', () => {
    expect(specViewerKind({ source: 'file', mime_type: 'application/pdf', file_name: 'a.bin' })).toBe('pdf')
    expect(specViewerKind({ source: 'file', mime_type: 'image/png', file_name: 'a.bin' })).toBe('image')
  })

  it('falls back to the extension when the browser sent no MIME type', () => {
    expect(specViewerKind({ source: 'file', mime_type: '', file_name: 'מפרט.PDF' })).toBe('pdf')
    expect(specViewerKind({ source: 'file', mime_type: null, file_name: 'plan.jpeg' })).toBe('image')
  })

  /** אין דפדפן שמרנדר HEIC. כרטיס הורדה עדיף על ריבוע שבור. */
  it('sends HEIC to download rather than to the image viewer', () => {
    expect(specViewerKind({ source: 'file', mime_type: 'image/heic', file_name: 'IMG_1.HEIC' })).toBe('download')
    expect(specViewerKind({ source: 'file', mime_type: '', file_name: 'IMG_1.heif' })).toBe('download')
  })

  it('treats anything it cannot place as a download', () => {
    expect(specViewerKind({ source: 'file', mime_type: 'application/zip', file_name: 'a.zip' })).toBe('download')
  })

  it('never inspects the MIME type of a link', () => {
    expect(specViewerKind({ source: 'link', mime_type: 'application/pdf', file_name: null })).toBe('link')
  })
})

describe('validateSpecFile', () => {
  it('accepts a PDF and an image', () => {
    expect(validateSpecFile({ name: 'a.pdf', type: 'application/pdf', size: 5000 })).toBeNull()
    expect(validateSpecFile({ name: 'a.png', type: 'image/png', size: 5000 })).toBeNull()
  })

  it('accepts by extension when the type is missing', () => {
    expect(validateSpecFile({ name: 'מפרט סופי.pdf', type: '', size: 5000 })).toBeNull()
  })

  it('rejects a type nobody asked for', () => {
    expect(validateSpecFile({ name: 'a.docx', type: 'application/vnd.ms-word', size: 500 })).toBe(
      'אפשר להעלות PDF או תמונה בלבד',
    )
  })

  it('rejects an empty file', () => {
    expect(validateSpecFile({ name: 'a.pdf', type: 'application/pdf', size: 0 })).toBe('הקובץ ריק')
  })

  /** הגבול חייב להיות זהה למה שנרשם על ה-bucket ב-0077. */
  it('rejects one byte over the bucket limit and accepts exactly the limit', () => {
    expect(validateSpecFile({ name: 'a.pdf', type: 'application/pdf', size: SPEC_MAX_BYTES })).toBeNull()
    expect(validateSpecFile({ name: 'a.pdf', type: 'application/pdf', size: SPEC_MAX_BYTES + 1 })).toContain('25MB')
  })
})

describe('validateSpecUrl', () => {
  it('accepts http and https', () => {
    expect(validateSpecUrl('https://drive.example.com/a')).toBeNull()
    expect(validateSpecUrl('  http://x.test/a  ')).toBeNull()
  })

  it('rejects anything that is not a document link', () => {
    expect(validateSpecUrl('')).toBe('צריך להזין כתובת')
    expect(validateSpecUrl('drive.example.com/a')).toBe('הכתובת אינה תקינה')
    expect(validateSpecUrl('javascript:alert(1)')).toBe('הכתובת צריכה להתחיל ב-https://')
  })
})

describe('specStoragePath', () => {
  /** התיקייה הראשונה היא מה שפוליסת ה-Storage קוראת. */
  it('puts the event id first and keeps only the extension', () => {
    expect(specStoragePath(EVENT, 'מפרט סופי.PDF', 'u1')).toBe(`${EVENT}/u1.pdf`)
  })

  it('drops a file name with no extension rather than inventing one', () => {
    expect(specStoragePath(EVENT, 'scan', 'u1')).toBe(`${EVENT}/u1`)
  })

  /** הנתיב חייב להישאר '<event_id>/<uuid>.<ext>' — סיומת שנושאת '/' או '..'
      הייתה מזיזה את הקובץ מחוץ לתיקיית האירוע, ואיתו את ההרשאה עליו. */
  it('cannot be walked out of the event folder', () => {
    expect(specStoragePath(EVENT, 'a.p df/../x', 'u1')).toBe(`${EVENT}/u1.x`)
    expect(specStoragePath(EVENT, 'a.pdf/../../etc', 'u1').split('/')).toHaveLength(2)
  })
})

describe('sortedSpecs / currentSpec', () => {
  const specs = [spec({ version: 1 }), spec({ version: 3 }), spec({ version: 2 })]

  it('reads newest first', () => {
    expect(sortedSpecs(specs).map((s) => s.version)).toEqual([3, 2, 1])
  })

  it('the active version is the highest that was not removed', () => {
    expect(currentSpec(specs)?.version).toBe(3)
    const withRemoved = [...specs, spec({ version: 4, deleted_at: '2026-08-18T10:00:00Z' })]
    expect(currentSpec(withRemoved)?.version).toBe(3)
  })

  it('has no active version when nothing was uploaded', () => {
    expect(currentSpec([])).toBeUndefined()
  })
})

describe('pickCompareDefaults', () => {
  it('opens the active version against the one before it', () => {
    const [right, left] = pickCompareDefaults([spec({ version: 1 }), spec({ version: 2 }), spec({ version: 3 })])!
    expect([right.version, left.version]).toEqual([3, 2])
  })

  /** חלונית ריקה נראית כמו תקלה; אותה גרסה פעמיים אומרת "אין עוד מה להשוות". */
  it('shows the only version on both sides when there is nothing to compare to', () => {
    const [right, left] = pickCompareDefaults([spec({ version: 1 })])!
    expect([right.version, left.version]).toEqual([1, 1])
  })

  it('ignores removed versions', () => {
    const pair = pickCompareDefaults([spec({ version: 1 }), spec({ version: 2, deleted_at: 'now' })])!
    expect(pair.map((s) => s.version)).toEqual([1, 1])
  })

  it('returns null when there is no spec at all', () => {
    expect(pickCompareDefaults([])).toBeNull()
  })
})

describe('specLabel', () => {
  it('prefers the title the uploader wrote', () => {
    expect(specLabel(spec({ version: 2, title: 'אחרי סיור' }))).toBe('גרסה 2 · אחרי סיור')
  })

  it('falls back to the file name, and to the link', () => {
    expect(specLabel(spec({ version: 2 }))).toBe('גרסה 2 · מפרט 2.pdf')
    expect(specLabel(spec({ version: 5, source: 'link', file_name: null, url: 'https://x.test/a' }))).toBe(
      'גרסה 5 · https://x.test/a',
    )
  })

  it('names the version alone when nothing else is known', () => {
    expect(specLabel(spec({ version: 7, file_name: null }))).toBe('גרסה 7')
  })
})

describe('formatBytes', () => {
  it('scales to the unit a person reads', () => {
    expect(formatBytes(900)).toBe('900 B')
    expect(formatBytes(2048)).toBe('2 KB')
    expect(formatBytes(3 * 1024 * 1024)).toBe('3.0 MB')
  })

  it('says nothing when the size is unknown', () => {
    expect(formatBytes(null)).toBe('')
    expect(formatBytes(0)).toBe('')
  })
})
