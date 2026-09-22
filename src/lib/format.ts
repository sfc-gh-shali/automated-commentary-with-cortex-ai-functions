/*
 * Display helpers.
 *
 * The rule that runs through this whole app: SQL owns the arithmetic and the
 * formatting. Nothing here computes a figure or re-formats one. These helpers
 * only decide whether a value is safe to put on screen.
 *
 * That distinction earned its own file because the Streamlit version of this UI
 * shipped "Headroom to nan" and crashed on int(NaN). JavaScript has the same
 * holes with different spelling: Number(null) is 0, `${undefined}` is the
 * string "undefined", and NaN is truthy in a template literal.
 */

/**
 * True only when a value is worth rendering.
 *
 * Rejects null, undefined, NaN, and the string forms that leak out of data
 * layers ("nan", "None", "NaT", "null", ""). Anything this returns false for
 * should suppress its whole row or label rather than print a placeholder.
 */
export function hasValue(value: unknown): boolean {
  if (value === null || value === undefined) return false
  if (typeof value === "number") return Number.isFinite(value)
  if (typeof value === "string") {
    const t = value.trim()
    if (t === "") return false
    return !["nan", "none", "nat", "null", "undefined"].includes(t.toLowerCase())
  }
  return true
}

/** A pre-formatted string from SQL, or an em dash. Never "null" or "NaN". */
export function display(value: unknown): string {
  return hasValue(value) ? String(value) : "—"
}

/** Null-safe integer coercion. COUNT_IF returns NULL over an empty set. */
export function asInt(value: unknown): number {
  if (!hasValue(value)) return 0
  const n = Number(value)
  return Number.isFinite(n) ? Math.round(n) : 0
}

/** Null-safe float coercion, returning null rather than 0 for absent values. */
export function asFloat(value: unknown): number | null {
  if (!hasValue(value)) return null
  const n = Number(value)
  return Number.isFinite(n) ? n : null
}

/** "09 Sep 2026 08:52" from an ISO timestamp, or an em dash. */
export function formatTimestamp(value: unknown): string {
  if (!hasValue(value)) return "—"
  const d = new Date(String(value))
  if (Number.isNaN(d.getTime())) return "—"
  return d.toLocaleString("en-GB", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  })
}

/** "09 Sep 2026" from an ISO date, or an em dash. */
export function formatDate(value: unknown): string {
  if (!hasValue(value)) return "—"
  // Parse as UTC so a date-only string does not shift a day in a west-of-UTC
  // timezone, which would make the COB label disagree with the data.
  const d = new Date(`${String(value).slice(0, 10)}T00:00:00Z`)
  if (Number.isNaN(d.getTime())) return "—"
  return d.toLocaleDateString("en-GB", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    timeZone: "UTC",
  })
}

/** Short "9 Sep" form for chart axes. */
export function formatDateShort(value: unknown): string {
  if (!hasValue(value)) return ""
  const d = new Date(`${String(value).slice(0, 10)}T00:00:00Z`)
  if (Number.isNaN(d.getTime())) return ""
  return d.toLocaleDateString("en-GB", {
    day: "numeric",
    month: "short",
    timeZone: "UTC",
  })
}

export type StatusKey =
  | "BREACH_L3"
  | "BREACH_L2"
  | "BREACH_L1"
  | "NEAR_MISS"
  | "WITHIN_LIMIT"
  | "NO_SOURCE_DATA"

/*
 * Status vocabulary.
 *
 * `short` exists because the full label truncated in the grid column of the
 * previous UI and shipped "L3 breach (" to screen. Long labels belong in the
 * detail panel, not in a table cell.
 */
export const STATUS_META: Record<
  StatusKey,
  { short: string; long: string; tone: string; dot: string; rank: number }
> = {
  BREACH_L3: {
    short: "L3 critical",
    long: "L3 breach (critical, executive escalation)",
    tone: "sev-l3",
    dot: "dot-l3",
    rank: 5,
  },
  BREACH_L2: {
    short: "L2 material",
    long: "L2 breach (material, management escalation)",
    tone: "sev-l2",
    dot: "dot-l2",
    rank: 4,
  },
  BREACH_L1: {
    short: "L1 breach",
    long: "L1 breach (first threshold crossed)",
    tone: "sev-l1",
    dot: "dot-l1",
    rank: 3,
  },
  NEAR_MISS: {
    short: "Near miss",
    long: "Near miss (within 10% of L1, not breached)",
    tone: "sev-near",
    dot: "dot-near",
    rank: 2,
  },
  WITHIN_LIMIT: {
    short: "Within limit",
    long: "Within limit",
    tone: "sev-none",
    dot: "dot-none",
    rank: 1,
  },
  NO_SOURCE_DATA: {
    short: "No data",
    long: "No source data (upstream feed unavailable)",
    tone: "sev-nodata",
    dot: "dot-nodata",
    rank: 0,
  },
}

const FALLBACK_STATUS = {
  short: "Unknown",
  long: "Unknown status",
  tone: "text-muted-foreground bg-muted border-border",
  dot: "bg-muted-foreground",
  rank: -1,
}

export function statusMeta(status: unknown) {
  if (!hasValue(status)) return FALLBACK_STATUS
  return STATUS_META[String(status) as StatusKey] ?? FALLBACK_STATUS
}
