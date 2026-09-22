/*
 * Typed access to the Express API.
 *
 * Column names arrive uppercased because that is how Snowflake returns them; they
 * are left that way rather than renamed, so a field here can be traced straight
 * back to a column in server/queries.js.
 */

import { useCallback } from "react"
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"

export type Approach = "GROUNDED" | "DIRECT_FULL"

export const APPROACH_ORDER: Approach[] = ["GROUNDED", "DIRECT_FULL"]

function supportedApproachRows<Row extends { APPROACH: string }>(rows: Row[]): Row[] {
  return rows.filter((row) => APPROACH_ORDER.some((approach) => approach === row.APPROACH))
}

async function get<T>(path: string): Promise<T> {
  const res = await fetch(path)
  if (!res.ok) {
    const body = await res.json().catch(() => ({}))
    throw new Error(body.error ?? `Request failed: ${res.status}`)
  }
  return res.json()
}

async function post<T>(path: string, body: unknown): Promise<T> {
  const res = await fetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  })
  if (!res.ok) {
    const payload = await res.json().catch(() => ({}))
    throw new Error(payload.error ?? `Request failed: ${res.status}`)
  }
  return res.json()
}

export interface CobDate {
  COB_DATE: string
  BATCH_IDENTIFIER: number
  TOTAL_METRICS: number
  REQUIRES_COMMENTARY: number
  HAS_COMMENTARY: number
  COMMENTARY_MISSING: number
}

export interface Summary {
  COB_DATE: string
  BATCH_IDENTIFIER: number
  TOTAL_METRICS: number
  BREACH_L3: number
  BREACH_L2: number
  BREACH_L1: number
  NEAR_MISS: number
  NO_SOURCE_DATA: number
  WITHIN_LIMIT: number
  REQUIRES_COMMENTARY: number
  HAS_COMMENTARY: number
  COMMENTARY_MISSING: number
  ANALYST_EDITED: number
  NEEDS_REVIEW: number
  LAST_GENERATED_AT: string | null
  LAST_GENERATION_SOURCE: string | null
}

export interface FullColumn {
  name: string
  type: string
  comment: string | null
  source: "feed" | "cortex"
}

export type FullRow = Record<string, unknown>

export interface GridRow {
  RECORD_ID: number
  METRIC_KEY: number
  METRIC_NAME: string
  SCOPE: string
  METRIC_TYPE: string
  DISPLAY_FREQ: string
  STATUS: string
  SEVERITY_RANK: number
  BREACH_LEVEL: string | null
  DATA_QUALITY_FLAG: string
  HAS_DATA: boolean
  REQUIRES_COMMENTARY: boolean
  REPORTING_UNIT: string | null
  LIMIT_DIRECTION: string | null
  VALUE_DISPLAY: string | null
  UTIL_DISPLAY: string | null
  BREACH_DISPLAY: string | null
  HEADROOM_DISPLAY: string | null
  L1_DISPLAY: string | null
  L2_DISPLAY: string | null
  L3_DISPLAY: string | null
  PRIOR_DISPLAY: string | null
  CHANGE_DISPLAY: string | null
  PRIOR_PERIOD_LABEL: string | null
  NEXT_LEVEL_NAME: string | null
  UTILIZATION_PCT: number | null
  TRAJECTORY: string | null
  PERIODS_IN_BREACH: number | null
  STREAK_LEFT_CENSORED: boolean | null
  LEVEL_CHANGE: string | null
  TREND_SERIES: string | null
  FACT_BLOCK: string | null
  AI_COMMENTARY: string | null
  FINAL_COMMENTARY: string | null
  IS_EDITED: boolean | null
  NEEDS_REVIEW: boolean | null
  EDITED_BY: string | null
  MODEL_NAME: string | null
  PROMPT_VERSION: string | null
  GENERATION_METHOD: string | null
  GENERATION_SOURCE: string | null
  GENERATED_AT: string | null
  HAS_COMMENTARY: boolean
  COMMENTARY_MISSING: boolean
}

export interface MetricListItem {
  RECORD_ID: number
  METRIC_KEY: number
  METRIC_NAME: string
  SCOPE: string
  STATUS: string
  SEVERITY_RANK: number
  LIMIT_DIRECTION: string | null
  VALUE_DISPLAY: string | null
  REPORTING_UNIT: string | null
  REQUIRES_COMMENTARY: boolean
  HAS_DATA: boolean
}

export interface PromptInput {
  APPROACH: Approach
  PROMPT_INPUT: string
  PROMPT: string
  INPUT_HASH: string
  PROMPT_VERSION: string
  HAS_DATA: boolean
  REQUIRES_COMMENTARY: boolean
  PROMPT_CHARS: number
}

/** One line, with both approaches and their checks. */
export interface Comparison {
  RECORD_ID: number
  METRIC_KEY: number
  METRIC_NAME: string
  SCOPE: string
  STATUS: string
  TRUE_BREACH_LEVEL: string | null
  LIMIT_DIRECTION: string | null
  BAND_MIDPOINT: number | null
  HAS_DATA: boolean
  REQUIRES_COMMENTARY: boolean
  GROUNDED_TEXT: string | null
  GROUNDED_WORDS: number | null
  GROUNDED_INVENTED: number | null
  GROUNDED_INVENTED_TOKENS: string | null
  GROUNDED_WRONG_LEVEL: boolean | null
  GROUNDED_EMPTY: boolean | null
  GROUNDED_STATED_LEVEL: string | null
  GROUNDED_BAND_WRONG: boolean | null
  DIRECT_FULL_TEXT: string | null
  DIRECT_FULL_WORDS: number | null
  DIRECT_FULL_INVENTED: number | null
  DIRECT_FULL_INVENTED_TOKENS: string | null
  DIRECT_FULL_WRONG_LEVEL: boolean | null
  DIRECT_FULL_EMPTY: boolean | null
  DIRECT_FULL_STATED_LEVEL: string | null
  DIRECT_FULL_BAND_WRONG: boolean | null
  HAS_GROUNDED: boolean
  HAS_DIRECT_FULL: boolean
}

/** Per-approach view of a Comparison row. */
export interface ApproachResult {
  approach: Approach
  text: string | null
  words: number | null
  invented: number | null
  inventedTokens: string | null
  wrongLevel: boolean | null
  empty: boolean | null
  statedLevel: string | null
  bandWrong: boolean | null
  generated: boolean
}

export function approachResults(c: Comparison): ApproachResult[] {
  return [
    {
      approach: "GROUNDED",
      text: c.GROUNDED_TEXT,
      words: c.GROUNDED_WORDS,
      invented: c.GROUNDED_INVENTED,
      inventedTokens: c.GROUNDED_INVENTED_TOKENS,
      wrongLevel: c.GROUNDED_WRONG_LEVEL,
      empty: c.GROUNDED_EMPTY,
      statedLevel: c.GROUNDED_STATED_LEVEL,
      bandWrong: c.GROUNDED_BAND_WRONG,
      generated: c.HAS_GROUNDED,
    },
    {
      approach: "DIRECT_FULL",
      text: c.DIRECT_FULL_TEXT,
      words: c.DIRECT_FULL_WORDS,
      invented: c.DIRECT_FULL_INVENTED,
      inventedTokens: c.DIRECT_FULL_INVENTED_TOKENS,
      wrongLevel: c.DIRECT_FULL_WRONG_LEVEL,
      empty: c.DIRECT_FULL_EMPTY,
      statedLevel: c.DIRECT_FULL_STATED_LEVEL,
      bandWrong: c.DIRECT_FULL_BAND_WRONG,
      generated: c.HAS_DIRECT_FULL,
    },
  ]
}

export interface ScorecardRow {
  APPROACH: Approach
  LINES_GENERATED: number
  MODEL_CALLS: number
  EMPTY_OUTPUT: number
  WRONG_LEVEL: number
  LINES_WITH_INVENTED_NUMBERS: number
  INVENTED_NUMBERS_TOTAL: number | null
  BAND_WRONG_QUANTITY: number
  CAUSAL_CLAIMS: number
  REASONING_LEAKS: number
  MARKDOWN: number
  INTERNAL_CODES: number
  AVG_WORDS: number | null
}

export interface Pending {
  approach: Approach
  pending_rows: number
  model_calls: number
  static_rows: number
  approx_prompt_tokens: number
}

export interface PendingRow {
  RECORD_ID: number
  METRIC_KEY: number
  METRIC_NAME: string
  STATUS: string
  HAS_DATA: boolean
  SCOPE: string
  SEVERITY_RANK: number
}

export const useCobDates = () =>
  useQuery({ queryKey: ["cob-dates"], queryFn: () => get<CobDate[]>("/api/cob-dates") })

export const useSummary = (cob: string | null) =>
  useQuery({
    queryKey: ["summary", cob],
    queryFn: () => get<Summary>(`/api/summary?cob=${cob}`),
    enabled: !!cob,
  })

export const useRawReportFull = (
  cob: string | null,
  approach: Approach | "STARTER",
  enabled = true,
) =>
  useQuery({
    queryKey: ["report-full", cob, approach],
    queryFn: () =>
      get<{ approach: Approach; columns: FullColumn[]; rows: FullRow[] }>(
        `/api/report/full?cob=${cob}&approach=${approach}`,
      ),
    enabled: !!cob && enabled,
  })

export const useGrid = (cob: string | null, enabled = true) =>
  useQuery({
    queryKey: ["grid", cob],
    queryFn: () => get<GridRow[]>(`/api/grid?cob=${cob}`),
    enabled: !!cob && enabled,
  })

export const useMetricList = (cob: string | null, enabled = true) =>
  useQuery({
    queryKey: ["metrics", cob],
    queryFn: () => get<MetricListItem[]>(`/api/metrics?cob=${cob}`),
    enabled: !!cob && enabled,
  })

export const usePromptInputs = (recordId: number | null) =>
  useQuery({
    queryKey: ["prompt-inputs", recordId],
    queryFn: () => get<PromptInput[]>(`/api/prompt-inputs?recordId=${recordId}`),
    select: supportedApproachRows<PromptInput>,
    enabled: recordId !== null,
  })

export const useComparison = (recordId: number | null) =>
  useQuery({
    queryKey: ["comparison", recordId],
    queryFn: () => get<Comparison>(`/api/comparison?recordId=${recordId}`),
    enabled: recordId !== null,
  })

export const useScorecard = (cob: string | null, enabled = true) =>
  useQuery({
    queryKey: ["scorecard", cob],
    queryFn: () => get<ScorecardRow[]>(`/api/scorecard?cob=${cob}`),
    select: supportedApproachRows<ScorecardRow>,
    enabled: !!cob && enabled,
  })

export const usePending = (cob: string | null, approach: Approach, enabled = true) =>
  useQuery({
    queryKey: ["pending", cob, approach],
    queryFn: () => get<Pending>(`/api/pending?cob=${cob}&approach=${approach}`),
    enabled: !!cob && enabled,
  })

export const usePendingRows = (
  cob: string | null,
  approach: Approach,
  enabled = true,
) =>
  useQuery({
    queryKey: ["pending-rows", cob, approach],
    queryFn: () =>
      get<PendingRow[]>(`/api/pending-rows?cob=${cob}&approach=${approach}`),
    enabled: !!cob && enabled,
  })

/**
 * Invalidate everything a generation run can change.
 *
 * refetchType "all" matters: the default only refetches queries React Query
 * considers active, which previously left cost panels showing pre-run figures
 * until the step was remounted.
 */
export function useInvalidateCommentary() {
  const qc = useQueryClient()
  return useCallback(() => {
    for (const key of [
      "summary",
      "grid",
      "metrics",
      "comparison",
      "scorecard",
      "pending",
      "pending-rows",
      "report-full",
      "cob-dates",
      "prompt-inputs",
    ]) {
      qc.invalidateQueries({ queryKey: [key], refetchType: "all" })
    }
  }, [qc])
}

export function useGenerate() {
  const invalidate = useInvalidateCommentary()
  return useMutation({
    mutationFn: (vars: {
      cob: string
      approach: Approach
      recordIds?: number[]
      force?: boolean
    }) =>
      post<{
        approach: Approach
        message: string
        elapsed_ms: number
        lines_requested: number | null
      }>("/api/generate", vars),
    onSuccess: invalidate,
  })
}

export function useSaveCommentary() {
  const invalidate = useInvalidateCommentary()
  return useMutation({
    mutationFn: (vars: { recordId: number; approach: Approach; text: string }) =>
      post<{ ok: true }>("/api/commentary", vars),
    onSuccess: invalidate,
  })
}

export function useRevertCommentary() {
  const invalidate = useInvalidateCommentary()
  return useMutation({
    mutationFn: (vars: { recordId: number; approach: Approach }) =>
      post<{ ok: true }>("/api/commentary/revert", vars),
    onSuccess: invalidate,
  })
}

export function useClear() {
  const invalidate = useInvalidateCommentary()
  return useMutation({
    mutationFn: (vars: {
      scope: "approach" | "cob" | "all"
      cob?: string
      approach?: Approach
    }) => post<{ ok: true }>("/api/clear", vars),
    onSuccess: invalidate,
  })
}
