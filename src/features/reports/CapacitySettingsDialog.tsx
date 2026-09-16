import { useState, useEffect } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Modal,
  Button,
  Field,
  Input,
  Switch,
  Badge,
  useToast,
  Skeleton,
} from '../../components/ui'
import {
  HardHat,
  Truck,
  Users,
  Crown,
} from '../../components/ui/icons'
import { supabase } from '../../lib/supabase'
import { useAppSetting } from '../attendance/attendanceQueries'
import type { OpsCapacityConfig } from '../../types/domain'

interface ContractorWorkerCount {
  id: string
  name: string
  worker_count: number
}

interface CapacitySettingsDialogProps {
  open: boolean
  onClose: () => void
}

export function CapacitySettingsDialog({ open, onClose }: CapacitySettingsDialogProps) {
  const toast = useToast()
  const qc = useQueryClient()

  // 1. קריאת ההגדרות הקיימות
  const { data: config, isLoading: loadingConfig } = useAppSetting<OpsCapacityConfig>('ops.capacity')

  // 2. קריאת קיבולת נגזרת עכשווית כדי להראות למשתמש מה השרת מחשב כרגע
  const { data: derivedData, isLoading: loadingDerived } = useQuery({
    queryKey: ['load_capacity_derived_check'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('load_capacity', { p_scope: 'internal' })
      if (error) throw error
      return data as { workers: number; trucks: number; team_leads: number }
    },
    enabled: open,
  })

  // 3. קריאת רשימת הקבלנים ומספר העובדים הפעילים שלהם
  const { data: contractors = [], isLoading: loadingContractors } = useQuery<ContractorWorkerCount[]>({
    queryKey: ['contractors_active_worker_counts'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('contractors')
        .select(`
          id,
          name,
          contractor_workers (
            id,
            is_active,
            deleted_at
          )
        `)
        .is('deleted_at', null)
        .eq('is_active', true)
        .order('name')
      if (error) throw error
      return (data ?? []).map((c: any) => ({
        id: c.id,
        name: c.name,
        worker_count: (c.contractor_workers ?? []).filter((w: any) => !w.deleted_at && w.is_active).length,
      }))
    },
    enabled: open,
  })

  // מצבי טופס
  const [manualWorkers, setManualWorkers] = useState(false)
  const [workersCount, setWorkersCount] = useState<string>('')

  const [manualTrucks, setManualTrucks] = useState(false)
  const [trucksCount, setTrucksCount] = useState<string>('')

  const [manualLeads, setManualLeads] = useState(false)
  const [leadsCount, setLeadsCount] = useState<string>('')

  // קיבולת מותאמת אישית לקבלנים
  const [contractorOverrides, setContractorOverrides] = useState<Record<string, string>>({})

  // אתחול נתונים ברגע שטוענים את ההגדרות
  useEffect(() => {
    if (!open) return
    if (config) {
      if (config.workers != null) {
        setManualWorkers(true)
        setWorkersCount(String(config.workers))
      } else {
        setManualWorkers(false)
        setWorkersCount('')
      }

      if (config.trucks != null) {
        setManualTrucks(true)
        setTrucksCount(String(config.trucks))
      } else {
        setManualTrucks(false)
        setTrucksCount('')
      }

      if (config.team_leads != null) {
        setManualLeads(true)
        setLeadsCount(String(config.team_leads))
      } else {
        setManualLeads(false)
        setLeadsCount('')
      }

      const overrides: Record<string, string> = {}
      if (config.contractors) {
        for (const [cId, val] of Object.entries(config.contractors)) {
          if (val?.workers != null) {
            overrides[cId] = String(val.workers)
          }
        }
      }
      setContractorOverrides(overrides)
    }
  }, [open, config])

  // שמירת ההגדרות
  const saveMutation = useMutation({
    mutationFn: async () => {
      const payload: OpsCapacityConfig = {
        workers: manualWorkers && workersCount !== '' ? Math.max(1, Number(workersCount)) : null,
        trucks: manualTrucks && trucksCount !== '' ? Math.max(1, Number(trucksCount)) : null,
        team_leads: manualLeads && leadsCount !== '' ? Math.max(1, Number(leadsCount)) : null,
        contractors: {},
      }

      for (const [cId, val] of Object.entries(contractorOverrides)) {
        if (val.trim() !== '') {
          payload.contractors = payload.contractors || {}
          payload.contractors[cId] = {
            workers: Math.max(1, Number(val)),
          }
        }
      }

      const { error } = await supabase
        .from('app_settings')
        .upsert({ key: 'ops.capacity', value: payload })

      if (error) throw error
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['app_settings', 'ops.capacity'] })
      void qc.invalidateQueries({ queryKey: ['load_heatmap'] })
      void qc.invalidateQueries({ queryKey: ['load_day'] })
      void qc.invalidateQueries({ queryKey: ['load_capacity_derived_check'] })
      toast.success('הגדרות הקיבולת נשמרו בהצלחה')
      onClose()
    },
    onError: (err) => {
      toast.error(`שגיאה בשמירת הגדרות הקיבולת: ${(err as Error).message}`)
    },
  })

  const isLoading = loadingConfig || loadingDerived || loadingContractors

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="הגדרת קיבולת ותקרת עומסים"
      size="lg"
      footer={
        <div className="flex items-center justify-between gap-2">
          <Button variant="outlined" onClick={onClose} disabled={saveMutation.isPending}>
            ביטול
          </Button>
          <Button
            variant="primary"
            onClick={() => saveMutation.mutate()}
            loading={saveMutation.isPending}
          >
            שמור שינויים
          </Button>
        </div>
      }
    >
      <div className="space-y-6 py-1">
        <div className="rounded-lg border border-line-subtle bg-surface-subtle p-3 text-sm text-ink-secondary">
          <p className="font-semibold text-ink">איך מחושב העומס?</p>
          <p className="mt-1">
            מפת העומסים מחשבת את אחוז העומס בכל שעה ויום על ידי השוואת הדרישה (עובדים, משאיות, ראשי צוות)
            מול הקיבולת המוגדרת כאן.
          </p>
          <p className="mt-1 text-xs text-ink-tertiary">
            באפשרותך לקבוע את מספר העובדים הפעילים בפועל בצוות הפנימי (כדי לנטרל משתמשים שאינם פעילים בשטח),
            וכן להגדיר קיבולת עבור כל קבלן.
          </p>
        </div>

        {isLoading ? (
          <Skeleton className="h-48 w-full" />
        ) : (
          <div className="space-y-5">
            {/* 1. עובדים בצוות פנימי */}
            <div className="rounded-xl border border-line p-4 transition-colors">
              <div className="flex items-center justify-between gap-3">
                <div className="flex items-center gap-2.5">
                  <div className="flex size-9 items-center justify-center rounded-lg bg-primary/10 text-primary">
                    <Users size={18} />
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="font-bold text-ink">עובדים בצוות פנימי</span>
                      <Badge tone={manualWorkers ? 'primary' : 'neutral'}>
                        {manualWorkers ? 'הגדרה ידנית' : 'נגזר מהמאגר'}
                      </Badge>
                    </div>
                    <p className="text-xs text-ink-tertiary">
                      {manualWorkers
                        ? 'מחושב לפי המספר שהגדרת'
                        : `נספר אוטומטית מהמאגר: ${derivedData?.workers ?? 0} עובדי צוות פעילים`}
                    </p>
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <span className="text-xs text-ink-secondary">הגדרה ידנית</span>
                  <Switch checked={manualWorkers} onChange={setManualWorkers} />
                </div>
              </div>

              {manualWorkers && (
                <div className="mt-4 pt-3 border-t border-line-subtle">
                  <Field
                    label="כמות עובדים פעילים בפועל"
                    hint="הזן את כמות העובדים הזמינים לעבודה בשטח בו-זמנית בצוות הפנימי"
                  >
                    <Input
                      type="number"
                      min={1}
                      max={100}
                      value={workersCount}
                      onChange={(e) => setWorkersCount(e.target.value)}
                      placeholder="לדוגמה: 8"
                      className="max-w-[140px]"
                    />
                  </Field>
                </div>
              )}
            </div>

            {/* 2. משאיות ורכבים */}
            <div className="rounded-xl border border-line p-4 transition-colors">
              <div className="flex items-center justify-between gap-3">
                <div className="flex items-center gap-2.5">
                  <div className="flex size-9 items-center justify-center rounded-lg bg-emerald-500/10 text-emerald-600 dark:text-emerald-400">
                    <Truck size={18} />
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="font-bold text-ink">משאיות פעילות</span>
                      <Badge tone={manualTrucks ? 'primary' : 'neutral'}>
                        {manualTrucks ? 'הגדרה ידנית' : 'נגזר מהצי'}
                      </Badge>
                    </div>
                    <p className="text-xs text-ink-tertiary">
                      {manualTrucks
                        ? 'מחושב לפי המספר שהגדרת'
                        : `נספר מצי הרכב הפעיל: ${derivedData?.trucks ?? 0} משאיות`}
                    </p>
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <span className="text-xs text-ink-secondary">הגדרה ידנית</span>
                  <Switch checked={manualTrucks} onChange={setManualTrucks} />
                </div>
              </div>

              {manualTrucks && (
                <div className="mt-4 pt-3 border-t border-line-subtle">
                  <Field label="כמות משאיות זמינות">
                    <Input
                      type="number"
                      min={1}
                      max={50}
                      value={trucksCount}
                      onChange={(e) => setTrucksCount(e.target.value)}
                      placeholder="לדוגמה: 4"
                      className="max-w-[140px]"
                    />
                  </Field>
                </div>
              )}
            </div>

            {/* 3. ראשי צוות */}
            <div className="rounded-xl border border-line p-4 transition-colors">
              <div className="flex items-center justify-between gap-3">
                <div className="flex items-center gap-2.5">
                  <div className="flex size-9 items-center justify-center rounded-lg bg-amber-500/10 text-amber-600 dark:text-amber-400">
                    <Crown size={18} />
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="font-bold text-ink">ראשי צוות</span>
                      <Badge tone={manualLeads ? 'primary' : 'neutral'}>
                        {manualLeads ? 'הגדרה ידנית' : 'נגזר מהתפקידים'}
                      </Badge>
                    </div>
                    <p className="text-xs text-ink-tertiary">
                      {manualLeads
                        ? 'מחושב לפי המספר שהגדרת'
                        : `נספר מבעלי תפקיד ראש צוות: ${derivedData?.team_leads ?? 0} ראשי צוות`}
                    </p>
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <span className="text-xs text-ink-secondary">הגדרה ידנית</span>
                  <Switch checked={manualLeads} onChange={setManualLeads} />
                </div>
              </div>

              {manualLeads && (
                <div className="mt-4 pt-3 border-t border-line-subtle">
                  <Field label="כמות ראשי צוות זמינים">
                    <Input
                      type="number"
                      min={1}
                      max={30}
                      value={leadsCount}
                      onChange={(e) => setLeadsCount(e.target.value)}
                      placeholder="לדוגמה: 2"
                      className="max-w-[140px]"
                    />
                  </Field>
                </div>
              )}
            </div>

            {/* 4. קיבולת קבלנים */}
            <div className="rounded-xl border border-line p-4">
              <div className="flex items-center gap-2 mb-3">
                <HardHat size={18} className="text-primary" />
                <span className="font-bold text-ink">קיבולת קבלנים לעבודה במקביל</span>
              </div>
              <p className="text-xs text-ink-secondary mb-3">
                כאשר משימה מועברת לקבלן, ניתן לצפות במפת העומסים עבור אותו קבלן ספציפי.
                כאן ניתן לוודא או לעדכן את כמות העובדים הזמינים של כל קבלן:
              </p>

              {contractors.length === 0 ? (
                <p className="text-sm text-ink-tertiary">אין קבלנים פעילים במערכת</p>
              ) : (
                <div className="space-y-2.5">
                  {contractors.map((c) => {
                    const override = contractorOverrides[c.id]
                    return (
                      <div
                        key={c.id}
                        className="flex items-center justify-between gap-3 rounded-lg border border-line-subtle bg-surface px-3 py-2"
                      >
                        <div className="min-w-0 flex-1">
                          <span className="font-medium text-ink">{c.name}</span>
                          <span className="text-xs text-ink-tertiary block">
                            במאגר: {c.worker_count} עובדים רשומים
                          </span>
                        </div>
                        <div className="flex items-center gap-2">
                          <span className="text-xs text-ink-secondary">תקן עובדים:</span>
                          <Input
                            type="number"
                            min={1}
                            max={50}
                            placeholder={String(c.worker_count || 1)}
                            value={override ?? ''}
                            onChange={(e) =>
                              setContractorOverrides((prev) => ({
                                ...prev,
                                [c.id]: e.target.value,
                              }))
                            }
                            className="w-20 text-center"
                          />
                        </div>
                      </div>
                    )
                  })}
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </Modal>
  )
}
