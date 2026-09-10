import { useEffect, useRef, useState } from 'react'
import {
  Button,
  Card,
  CardBody,
  CardHeader,
  Field,
  Input,
  Skeleton,
  useToast,
} from '../../components/ui'
import { Building2, ICON, Image as ImageIcon, STROKE, Trash2, Upload } from '../../components/ui/icons'
import { errorMessage } from '../../lib/errors'
import type { CompanyDetails } from '../../types/domain'
import {
  LOGO_MIME,
  useCompanyDetails,
  useCompanyLogoUrl,
  useSaveCompany,
  useUploadCompanyLogo,
} from './companyQueries'

/**
 * פרטי החברה והלוגו — מה שמודפס בכותרת של מסמך הצעת המחיר (0170).
 *
 * הכול יושב ב-`app_settings['company.details']` ולא בקוד, כי מספר טלפון או
 * שיעור מע״מ שמשתנים אינם אמורים לדרוש פריסה. הלוגו הוא היוצא מן הכלל
 * היחיד — הוא קובץ — והוא יושב בדלי `company-assets`.
 */
export function CompanyTab() {
  const toast = useToast()
  const { company, isLoading } = useCompanyDetails()
  const save = useSaveCompany()
  const upload = useUploadCompanyLogo()
  const fileRef = useRef<HTMLInputElement>(null)

  const [draft, setDraft] = useState<CompanyDetails>(company)
  useEffect(() => setDraft(company), [company])
  const set = (patch: Partial<CompanyDetails>) => setDraft((d) => ({ ...d, ...patch }))

  const { data: logoUrl } = useCompanyLogoUrl(company.logo_path)

  const vat = Number(draft.vat_pct)
  const vatValid = Number.isFinite(vat) && vat >= 0 && vat <= 100
  const dirty = JSON.stringify(draft) !== JSON.stringify(company)

  const pickLogo = (file: File | undefined) => {
    if (!file) return
    if (!LOGO_MIME.includes(file.type)) {
      toast.error('הלוגו חייב להיות PNG או JPG')
      return
    }
    upload.mutate(
      { file, company },
      {
        onSuccess: () => toast.success('הלוגו עודכן'),
        onError: (e) => toast.error(errorMessage(e)),
      },
    )
  }

  return (
    <div className="max-w-2xl space-y-5">
      <Card>
        <CardHeader
          title="פרטי החברה"
          subtitle="מה שמודפס בכותרת של הצעת המחיר שנשלחת ללקוח הקצה"
          icon={<Building2 size={ICON.md} strokeWidth={STROKE} />}
        />
        <CardBody>
          {isLoading ? (
            <Skeleton className="h-48 w-full" />
          ) : (
            <form
              className="space-y-4"
              onSubmit={(e) => {
                e.preventDefault()
                if (!vatValid) return
                save.mutate(
                  { ...draft, vat_pct: vat },
                  {
                    onSuccess: () => toast.success('פרטי החברה נשמרו'),
                    onError: (err) => toast.error(errorMessage(err)),
                  },
                )
              }}
            >
              <div className="grid gap-4 sm:grid-cols-2">
                <Field label="שם החברה" className="sm:col-span-2">
                  <Input value={draft.name} onChange={(e) => set({ name: e.target.value })} />
                </Field>
                <Field label="ח.פ">
                  <Input dir="ltr" value={draft.tax_id} onChange={(e) => set({ tax_id: e.target.value })} />
                </Field>
                <Field label="טלפון">
                  <Input dir="ltr" value={draft.phone} onChange={(e) => set({ phone: e.target.value })} />
                </Field>
                <Field label="מייל" className="sm:col-span-2">
                  <Input dir="ltr" type="email" value={draft.email} onChange={(e) => set({ email: e.target.value })} />
                </Field>
                <Field
                  label="שיעור מע״מ"
                  hint="מודפס כשורה נפרדת בהצעת המחיר"
                  error={!vatValid ? 'אחוז בין 0 ל-100' : undefined}
                >
                  <Input
                    type="number"
                    min={0}
                    max={100}
                    step={0.5}
                    dir="ltr"
                    className="text-center"
                    value={String(draft.vat_pct ?? '')}
                    onChange={(e) => set({ vat_pct: Number(e.target.value) })}
                  />
                </Field>
                <Field label="שורת החתימה במסמך" hint="אחריה מתווספים התאריך והשעה">
                  <Input
                    value={draft.quote_footer}
                    onChange={(e) => set({ quote_footer: e.target.value })}
                  />
                </Field>
              </div>
              <Button type="submit" size="sm" variant="primary" loading={save.isPending} disabled={!dirty || !vatValid}>
                שמירה
              </Button>
            </form>
          )}
        </CardBody>
      </Card>

      <Card>
        <CardHeader
          title="לוגו"
          subtitle="מופיע בראש המסמך. ‏PNG או JPG — קובץ SVG אינו נתמך בהטמעה ב-PDF"
          icon={<ImageIcon size={ICON.md} strokeWidth={STROKE} />}
        />
        <CardBody>
          <div className="flex flex-wrap items-center gap-4">
            <div className="flex size-24 shrink-0 items-center justify-center rounded-xl border border-line-subtle bg-subtle/40">
              {logoUrl ? (
                <img src={logoUrl} alt="לוגו החברה" className="max-h-20 max-w-20 object-contain" />
              ) : (
                <ImageIcon size={ICON.lg} strokeWidth={STROKE} className="text-ink-tertiary" />
              )}
            </div>
            <div className="space-y-2">
              <input
                ref={fileRef}
                type="file"
                accept={LOGO_MIME.join(',')}
                className="hidden"
                onChange={(e) => {
                  pickLogo(e.target.files?.[0])
                  e.target.value = ''
                }}
              />
              <div className="flex flex-wrap gap-2">
                <Button size="sm" loading={upload.isPending} onClick={() => fileRef.current?.click()}>
                  <Upload size={ICON.sm} strokeWidth={STROKE} />
                  {company.logo_path ? 'החלפת לוגו' : 'העלאת לוגו'}
                </Button>
                {company.logo_path && (
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() =>
                      save.mutate(
                        { ...company, logo_path: null },
                        {
                          onSuccess: () => toast.success('הלוגו הוסר'),
                          onError: (err) => toast.error(errorMessage(err)),
                        },
                      )
                    }
                  >
                    <Trash2 size={ICON.sm} strokeWidth={STROKE} />
                    הסרה
                  </Button>
                )}
              </div>
              <p className="type-caption text-ink-tertiary">
                בלי לוגו המסמך נפתח בשם החברה בלבד, והוא עדיין תקין.
              </p>
            </div>
          </div>
        </CardBody>
      </Card>
    </div>
  )
}
