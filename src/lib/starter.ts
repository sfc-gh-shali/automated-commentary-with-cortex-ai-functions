import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"

export interface StarterConfig {
  models: string[]; keyColumns: string[]; deployed: boolean; version: string
  preamble: string; rules: string; toneInstructions: Record<string, string>
  columnComments: Record<string, string>; storageSql: string
}
export interface StarterPreview {
  row: { RECORD_ID: number; METRIC_NAME: string; PROMPT: string; HAS_DATA: boolean; STATUS: string; STATIC_COMMENTARY: string | null } | null
  sql: string
}
export interface ResultRow {
  [key: string]: unknown
  RECORD_UNIQUE_IDENTIFIER: number; METRIC_KEY: number; METRIC_NAME: string; DIMENSION_TYPE_CODE: string
  LOB_DESCRIPTION: string | null; LEGAL_ENTITY_DESCRIPTION: string | null
  CURRENT_VALUE: string | null; REPORTING_UNIT: string | null
  L1_LIMIT_VALUE: string | null; L2_LIMIT_VALUE: string | null; L3_LIMIT_VALUE: string | null
  LIMIT_DIRECTION: string | null; BREACH_LEVEL: string | null; BREACH_AMOUNT: string | null
  CURRENT_UTILIZATION_LEVEL: string | null; HAS_SOURCE_DATA: string | null
  AI_COMMENTARY: string | null; FINAL_COMMENTARY: string | null
  MODEL_NAME: string | null; PROMPT_VERSION: string | null
  GENERATED_AT: string | null
  IS_EDITED: boolean | null; NEEDS_REVIEW: boolean | null
}

async function request<T>(path: string, body?: unknown): Promise<T> {
  const response = await fetch(path, body === undefined ? undefined : { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) })
  const payload = await response.json()
  if (!response.ok) throw new Error(payload.error ?? `Request failed (${response.status})`)
  return payload
}

export const useStarterConfig = () => useQuery({ queryKey: ["starter-config"], queryFn: () => request<StarterConfig>("/api/starter/config"), staleTime: 60000 })
export const useStarterRows = (cob: string) => useQuery({ queryKey: ["starter-rows", cob], queryFn: () => request<Record<string, unknown>[]>(`/api/starter/rows?cob=${cob}`) })
export const useStarterResults = (cob: string) => useQuery({ queryKey: ["starter-results", cob], queryFn: () => request<ResultRow[]>(`/api/starter/results?cob=${cob}`) })
export const useStarterPreview = (cob: string, model: string, enabled: boolean) => useQuery({ queryKey: ["starter-preview", cob, model], queryFn: () => request<StarterPreview>("/api/starter/preview", { cob, model }), enabled, retry: false })

export function useStarterGenerate() {
  const client = useQueryClient()
  return useMutation({ mutationFn: (body: { cob: string; model: string }) => request<{ message: string; elapsed_ms: number; model: string }>("/api/starter/generate", body), onSuccess: () => {
    client.invalidateQueries({ queryKey: ["starter-results"], refetchType: "all" })
    client.invalidateQueries({ queryKey: ["starter-rows"], refetchType: "all" })
    client.invalidateQueries({ queryKey: ["report-full"], refetchType: "all" })
  } })
}

export function useStarterReset() {
  const client = useQueryClient()
  return useMutation({ mutationFn: (body: { cob: string }) => request("/api/starter/reset", body), onSuccess: () => {
    client.invalidateQueries({ queryKey: ["starter-results"], refetchType: "all" })
    client.invalidateQueries({ queryKey: ["starter-rows"], refetchType: "all" })
    client.invalidateQueries({ queryKey: ["report-full"], refetchType: "all" })
  } })
}

