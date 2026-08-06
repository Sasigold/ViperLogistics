import { supabase } from './supabase'
import type { AddressSuggestion } from '../types/domain'

/**
 * Pluggable address-autocomplete provider. To switch to Google Places later,
 * implement AddressProvider and change the export at the bottom — nothing in
 * the UI needs to change.
 */
export interface AddressProvider {
  search(q: string, signal?: AbortSignal): Promise<AddressSuggestion[]>
}

class NominatimProvider implements AddressProvider {
  async search(q: string): Promise<AddressSuggestion[]> {
    if (q.trim().length < 3) return []
    const { data, error } = await supabase.functions.invoke(
      `geocode-proxy?q=${encodeURIComponent(q)}`,
      { method: 'GET' },
    )
    if (error) return []
    return (data as AddressSuggestion[]) ?? []
  }
}

export const addressProvider: AddressProvider = new NominatimProvider()
