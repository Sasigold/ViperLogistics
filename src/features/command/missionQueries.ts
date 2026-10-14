/**
 * משימות ניהול (0227) — הקריאות והכתיבות.
 *
 * הכול תחת `['command', …]`, וכל כתיבה פוסלת את כולו: הלוח, הסטטיסטיקה והתג
 * בתפריט נגזרים מאותן שורות. שני מנהלים — אין שידור בזמן אמת; הלוח מתרענן
 * כל דקה ובחזרה לחלון.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import type {
  MissionCompleteResult,
  MissionRecurrence,
  MissionsBoard,
  MissionsStats,
} from '../../types/domain'

export function useMissionsBoard(owner: string | null, enabled = true) {
  return useQuery({
    queryKey: ['command', 'board', owner],
    enabled,
    refetchInterval: 60_000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('missions_board', { p_owner: owner })
      if (error) throw error
      return { ...(data as MissionsBoard), fetchedAt: Date.now() }
    },
  })
}

export function useMissionsStats(owner: string | null, days = 84, enabled = true) {
  return useQuery({
    queryKey: ['command', 'stats', owner, days],
    enabled,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('missions_stats', { p_owner: owner, p_days: days })
      if (error) throw error
      return data as MissionsStats
    },
  })
}

export interface MissionInput {
  title: string
  description: string | null
  owner_id: string
  due_at: string
  priority: 1 | 2 | 3 | 4
  recurrence: MissionRecurrence
  steps: { id?: string; title: string; done: boolean }[]
}

function useInvalidate() {
  const qc = useQueryClient()
  return () => void qc.invalidateQueries({ queryKey: ['command'] })
}

export function useSaveMission() {
  const done = useInvalidate()
  return useMutation({
    mutationFn: async ({ id, input }: { id: string | null; input: MissionInput }) => {
      const { data, error } = await supabase.rpc('mission_save', { p_id: id, p: input })
      if (error) throw error
      return data as string
    },
    onSuccess: done,
  })
}

export function useCompleteMission() {
  const done = useInvalidate()
  return useMutation({
    mutationFn: async (id: string) => {
      const { data, error } = await supabase.rpc('mission_complete', { p_id: id })
      if (error) throw error
      return data as MissionCompleteResult
    },
    onSuccess: done,
  })
}

export function useReopenMission() {
  const done = useInvalidate()
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.rpc('mission_reopen', { p_id: id })
      if (error) throw error
    },
    onSuccess: done,
  })
}

export function useSnoozeMission() {
  const done = useInvalidate()
  return useMutation({
    mutationFn: async ({ id, minutes }: { id: string; minutes: number }) => {
      const { data, error } = await supabase.rpc('mission_snooze', { p_id: id, p_minutes: minutes })
      if (error) throw error
      return data as string
    },
    onSuccess: done,
  })
}

export function useRemoveMission() {
  const done = useInvalidate()
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.rpc('mission_remove', { p_id: id })
      if (error) throw error
    },
    onSuccess: done,
  })
}

export function useToggleStep() {
  const done = useInvalidate()
  return useMutation({
    mutationFn: async (stepId: string) => {
      const { data, error } = await supabase.rpc('mission_step_toggle', { p_step_id: stepId })
      if (error) throw error
      return data as boolean
    },
    onSuccess: done,
  })
}
