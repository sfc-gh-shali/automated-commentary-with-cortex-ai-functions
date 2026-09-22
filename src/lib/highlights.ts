export interface Highlight {
  metricKey: number
  tag: string
}

export const HIGHLIGHTS: Highlight[] = [
  { metricKey: 37, tag: "Band metric" },
  { metricKey: 1, tag: "Floor metric" },
  { metricKey: 3, tag: "Left-censored streak" },
  { metricKey: 4, tag: "New breach" },
  { metricKey: 2, tag: "Near miss" },
  { metricKey: 6, tag: "No source data" },
]

const BY_KEY = new Map(HIGHLIGHTS.map((highlight) => [highlight.metricKey, highlight]))

export function highlightFor(metricKey: unknown): Highlight | undefined {
  const key = Number(metricKey)
  return Number.isFinite(key) ? BY_KEY.get(key) : undefined
}

export function isHighlighted(metricKey: unknown): boolean {
  return highlightFor(metricKey) !== undefined
}