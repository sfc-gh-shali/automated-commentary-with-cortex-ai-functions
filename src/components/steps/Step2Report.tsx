import { useMemo, useState } from "react"
import { Search } from "lucide-react"
import { useRawReportFull } from "@/lib/api"
import { hasValue } from "@/lib/format"
import { Panel, Spinner, ErrorNote, Empty } from "@/components/ui/primitives"
import StatusTiles from "@/components/StatusTiles"
import { highlightFor, isHighlighted } from "@/lib/highlights"
import { cn } from "@/lib/utils"

const FILTERS = ["All rows", "Highlights"] as const

export default function Step2Report({ cob }: { cob: string }) {
  const { data, isPending, error } = useRawReportFull(cob, "STARTER")
  const [filter, setFilter] = useState<string>("All rows")
  const [search, setSearch] = useState("")
  const columns = useMemo(() => (data?.columns ?? []).filter((c) => c.source !== "cortex"), [data])
  const rows = useMemo(() => (data?.rows ?? []).filter((row) => {
    if (filter === "Highlights" && !isHighlighted(row.METRIC_KEY)) return false
    return `${row.METRIC_NAME} ${row.LOB_DESCRIPTION ?? ""} ${row.LEGAL_ENTITY_DESCRIPTION ?? ""}`.toLowerCase().includes(search.toLowerCase())
  }), [data, filter, search])
  if (isPending) return <Spinner label="Loading source report" />
  if (error) return <ErrorNote error={error} />
  if (!data) return null
  return <div className="space-y-5">
    <StatusTiles cob={cob} showCoverage={false} />
    <Panel title="Source records">
      <div className="report-toolbar">
        <div className="segmented" aria-label="Source row filter">{FILTERS.map((label) =>
          <button key={label} aria-pressed={filter === label} onClick={() => setFilter(label)}>{label}</button>)}</div>
        <label className="search-control"><Search size={15} /><input aria-label="Search source records" placeholder="Metric or scope" value={search} onChange={(event) => setSearch(event.target.value)} /></label>
      </div>
      {rows.length === 0 ? <Empty>No matching source records.</Empty> : <div className="source-table-scroll">
        <table className="source-table"><thead><tr>{columns.map((column) => <th key={column.name} title={column.comment ?? undefined}
          className={column.source === "cortex" ? "commentary-cell" : ""}>
          <div>{column.name}</div><span>{column.type}</span></th>)}</tr></thead>
          <tbody>{rows.map((row) => <tr key={String(row.RECORD_UNIQUE_IDENTIFIER)} className={cn(isHighlighted(row.METRIC_KEY) && "row-accent")}>
            {columns.map((column) => <td key={column.name} className={column.source === "cortex" ? "commentary-cell" : ""}>
              {column.name === "METRIC_NAME" && highlightFor(row.METRIC_KEY) && <span className="metric-tag">{highlightFor(row.METRIC_KEY)!.tag}</span>}
              {hasValue(row[column.name]) ? <span className={column.source === "cortex" ? "commentary-text" : column.name === "METRIC_NAME" ? "metric-cell-value" : "cell-value"} title={String(row[column.name])}>{String(row[column.name])}</span>
                : <span className="text-muted-foreground italic">{column.source === "cortex" ? "Not generated" : "null"}</span>}
            </td>)}
          </tr>)}</tbody></table>
      </div>}
      <div className="table-summary"><span>{rows.length} of {data.rows.length} records</span><span>{columns.length} source columns</span></div>
    </Panel>
  </div>
}