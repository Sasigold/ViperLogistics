import { useMutation, useQueryClient } from '@tanstack/react-query'
import { EyeOff, ICON, STROKE, SlidersHorizontal } from '../../components/ui/icons'
import { Card, CardBody, CardHeader, SegmentedControl, Skeleton, useToast } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { useCustomerFormConfig, useFormFields, useUserFormFields } from '../../lib/queries'
import type { FieldState, Profile } from '../../types/domain'

const OVERRIDE_STATES = [
  { key: 'default' as const, label: 'כמו הלקוח' },
  { key: 'hidden' as const, label: 'מוסתר', icon: <EyeOff size={12} /> },
  { key: 'required' as const, label: 'חובה', icon: <span className="text-error">*</span> },
]

const INHERITED_LABEL: Record<FieldState, string> = {
  visible: 'מוצג',
  hidden: 'מוסתר',
  required: 'חובה',
}

/**
 * Which fields of the event form this particular user gets.
 *
 * Distinct from `FieldPermissions` in features/permissions, which governs
 * access to the *data* and is enforced by RLS. This one governs the *shape of
 * the form* — whether a field is offered at all, and whether it is required.
 * The two look alike and answer different questions, so they stay apart:
 * hiding a field here does not hide the value from anyone who can query it.
 */
export function ClientFormFieldsCard({ profile }: { profile: Profile }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { data: fields = [], isLoading } = useFormFields()
  const { data: companyConfig = [] } = useCustomerFormConfig(profile.customer_id)
  const { data: overrides = [] } = useUserFormFields(profile.id)

  const companyState = (key: string): FieldState =>
    companyConfig.find((c) => c.field_key === key)?.state ?? 'visible'
  const overrideState = (key: string): 'default' | 'hidden' | 'required' =>
    (overrides.find((o) => o.field_key === key)?.state as 'hidden' | 'required' | undefined) ?? 'default'

  const update = useMutation({
    mutationFn: async ({ key, state }: { key: string; state: string }) => {
      if (state === 'default') {
        const { error } = await supabase
          .from('user_form_fields')
          .delete()
          .eq('profile_id', profile.id)
          .eq('field_key', key)
        if (error) throw error
      } else {
        // composite primary key, so a plain upsert infers the conflict target
        const { error } = await supabase
          .from('user_form_fields')
          .upsert({ profile_id: profile.id, field_key: key, state })
        if (error) throw error
      }
    },
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['user_form_fields', profile.id] }),
    onError: (e) => toast.error((e as Error).message),
  })

  return (
    <Card>
      <CardHeader
        title="שדות טופס האירוע"
        subtitle={overrides.length > 0 ? `${overrides.length} חריגות מהגדרת הלקוח` : 'הכול לפי הגדרת הלקוח'}
        icon={<SlidersHorizontal size={ICON.md} strokeWidth={STROKE} />}
      />
      <CardBody padded={false}>
        <p className="border-b border-line-subtle bg-subtle/40 px-4 py-2.5 type-caption text-ink-secondary">
          ההגדרה כאן מצטמצמת מעל הגדרת הלקוח ולעולם לא מרחיבה אותה — שדה שהוסתר ללקוח כולו יישאר מוסתר גם אם יסומן כאן
          אחרת.
        </p>
        {isLoading ? (
          <div className="p-4">
            <Skeleton className="h-40 w-full" />
          </div>
        ) : (
          <ul>
            {fields.map((f) => {
              const inherited = companyState(f.field_key)
              // hidden company-wide → the intersection makes any override moot
              const locked = inherited === 'hidden' || f.field_key === 'event_date'
              return (
                <li
                  key={f.field_key}
                  className="flex items-center gap-3 border-b border-line-subtle px-4 py-2.5 last:border-0"
                >
                  <span className="min-w-0 flex-1">
                    <span className="block truncate type-body font-medium">{f.label_he}</span>
                    <span className="type-caption text-ink-tertiary">
                      {f.field_key === 'event_date' ? 'שדה חובה קבוע' : `אצל הלקוח: ${INHERITED_LABEL[inherited]}`}
                    </span>
                  </span>
                  <SegmentedControl
                    items={OVERRIDE_STATES}
                    value={locked ? 'default' : overrideState(f.field_key)}
                    onChange={(state) => !locked && update.mutate({ key: f.field_key, state })}
                    className={locked ? 'pointer-events-none opacity-55' : undefined}
                  />
                </li>
              )
            })}
          </ul>
        )}
      </CardBody>
    </Card>
  )
}
