import { useMemo, useState } from "react"
import { Play, Eraser, Columns3 } from "lucide-react"
import { Panel, Spinner, ErrorNote, Empty } from "@/components/ui/primitives"
import { useStarterConfig, useStarterRows, useStarterResults, useStarterGenerate, useStarterReset } from "@/lib/starter"
import { isHighlighted, highlightFor } from "@/lib/highlights"
import { cn } from "@/lib/utils"
import type { BuilderState } from "./StepBuild"

const FILTERS = ["All rows", "Highlights"] as const

export default function StepResults({ cob, builder, onBusyChange }: {
  cob: string; builder: BuilderState; onBusyChange: (b: boolean) => void
}) {
  const config = useStarterConfig()
  const rows = useStarterRows(cob)
  const results = useStarterResults(cob)
  const generate = useStarterGenerate()
  const reset = useStarterReset()
  const busy = generate.isPending || reset.isPending
  const [wideOut, setWideOut] = useState(false)
  const [filter, setFilter] = useState<string>("All rows")

  const allResultRows = results.data ?? []
  const resultRows = useMemo(() =>
    filter === "Highlights" ? allResultRows.filter((r) => isHighlighted(r.METRIC_KEY)) : allResultRows
  , [allResultRows, filter])
  const resultKeyCols = ["METRIC_NAME", "DIMENSION_TYPE_CODE", "BREACH_LEVEL", "CURRENT_VALUE", "REPORTING_UNIT"]
  const commentaryCols = ["AI_COMMENTARY", "MODEL_NAME", "GENERATED_AT"]
  const allResultCols = allResultRows.length ? Object.keys(allResultRows[0]) : []
  const outCols = wideOut ? allResultCols : [...resultKeyCols, ...commentaryCols]
  const hasCommentary = allResultRows.some((r) => r.AI_COMMENTARY)
  const commentaryCount = allResultRows.filter((r) => r.AI_COMMENTARY).length

  return <div className="space-y-5">
    {/* Generate controls */}
    <Panel title="Generate commentary">
      <div className="starter-controls">
        <button className="action-primary" disabled={busy || !config.data?.deployed} onClick={() => { onBusyChange(true); generate.mutate({ cob, model: builder.model }, { onSettled: () => onBusyChange(false) }) }}>
          <Play size={16} />{generate.isPending ? "Generating..." : `Generate all ${rows.data?.length ?? 0} rows`}
        </button>
        <span className="muted-note">Model: {builder.model}</span>
      </div>
      {generate.error && <ErrorNote error={generate.error} />}
      {generate.data && <p className="starter-notice" role="status">{generate.data.message} {(generate.data.elapsed_ms / 1000).toFixed(1)}s.</p>}
    </Panel>

    {/* Table Out */}
    <Panel title="Commentary store" right={<span className="muted-note">{commentaryCount} of {allResultRows.length} rows have commentary</span>}>
      <div className="report-toolbar">
        <div className="segmented" aria-label="Result row filter">{FILTERS.map((label) =>
          <button key={label} aria-pressed={filter === label} onClick={() => setFilter(label)}>{label}</button>)}</div>
        <label className="columns-control"><Columns3 size={16} /><select className="field-control" value={wideOut ? "all" : "key"} onChange={(e) => setWideOut(e.target.value === "all")}>
          <option value="key">Key + commentary</option><option value="all">All columns</option></select></label>
        <button className="action-secondary" disabled={busy || !hasCommentary} onClick={() => {
          if (window.confirm(`Delete ALL starter commentary for COB ${cob}? Source records are unchanged.`)) {
            onBusyChange(true); reset.mutate({ cob }, { onSettled: () => onBusyChange(false) })
          }
        }}><Eraser size={16} />Reset commentary store</button>
      </div>
      {reset.error && <ErrorNote error={reset.error} />}
      {results.isPending && <Spinner label="Loading results" />}{results.error && <ErrorNote error={results.error} />}
      {resultRows.length === 0 ? <Empty>{filter === "Highlights" ? "No highlighted rows." : "No commentary generated yet. Click Generate to run all rows."}</Empty> :
        <div className="source-table-scroll"><table className="source-table"><thead><tr>{outCols.map((c) => <th key={c} className={c === "AI_COMMENTARY" ? "commentary-cell" : ""}>{c}</th>)}</tr></thead>
          <tbody>{resultRows.map((row, i) => <tr key={i} className={cn(isHighlighted(row.METRIC_KEY) && "row-accent")}>
            {outCols.map((c) => {
              const val = (row as Record<string, unknown>)[c]
              return <td key={c} className={c === "AI_COMMENTARY" ? "commentary-cell" : ""}>
                {c === "METRIC_NAME" && highlightFor(row.METRIC_KEY) && <span className="metric-tag">{highlightFor(row.METRIC_KEY)!.tag}</span>}
                {val != null ? <span className={c === "AI_COMMENTARY" ? "commentary-text" : "cell-value"} title={String(val)}>{String(val)}</span>
                  : <span className="text-muted-foreground italic">null</span>}
              </td>
            })}
          </tr>)}</tbody></table></div>}
      <div className="table-summary"><span>{resultRows.length} of {allResultRows.length} rows</span></div>
    </Panel>
  </div>
}
