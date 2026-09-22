import { useState } from "react"
import { Panel, Spinner, ErrorNote } from "@/components/ui/primitives"
import { useStarterConfig, useStarterRows, useStarterPreview } from "@/lib/starter"

export interface BuilderState { model: string; fields: string[]; initialized: boolean }
export const INITIAL_BUILDER: BuilderState = { model: "claude-sonnet-5", fields: [], initialized: false }

function sqlLit(v: string) { return `'${v.replace(/\\/g, "\\\\").replace(/'/g, "''")}'` }

function buildSqlSections(model: string, fields: string[], preamble: string, rules: string, cob: string, comments: Record<string, string>) {
  const systemPrompt = preamble + "\n\n" + rules
  const dictEntries = fields.filter((f) => comments[f]).map((f) => `${f}: ${comments[f]}`)
  const colLines = fields.map((f) => `      ${sqlLit(f + " = ")} || COALESCE(TO_VARCHAR(r.${f}), '(null)')`)
  const sql = `SELECT r.RECORD_UNIQUE_IDENTIFIER,
  AI_COMPLETE(${sqlLit(model)},
    CONCAT_WS(CHR(10),
      @system_prompt,
      ${dictEntries.length ? "@data_dictionary,\n      " : ""}'RECORD:',
${colLines.join(",\n")}
    )
  )::VARCHAR AS COMMENTARY
FROM LIMITS_INDICATORS_REPORT_DATA r
WHERE r.REPORT_AS_OF_COB_DATE = TO_DATE(${sqlLit(cob)});`
  return { systemPrompt, dictEntries, sql }
}

export default function StepBuild({ cob, state, onChange }: {
  cob: string; state: BuilderState; onChange: (s: BuilderState) => void
}) {
  const config = useStarterConfig()
  const rows = useStarterRows(cob)
  const preview = useStarterPreview(cob, state.model, !!config.data?.deployed)
  const [tab, setTab] = useState("SQL")

  if (!state.initialized && config.data) onChange({ ...state, initialized: true, fields: [...config.data.keyColumns] })

  const allCols = rows.data?.length ? Object.keys(rows.data[0]) : []
  const sections = config.data ? buildSqlSections(state.model, state.fields, config.data.preamble, config.data.rules, cob, config.data.columnComments) : null

  return <div className="space-y-5">
    {config.error && <ErrorNote error={config.error} />}
    {config.isPending && <Spinner label="Checking configuration" />}
    {config.data && !config.data.deployed && <p className="starter-notice" role="status">V_PROMPT_ALL or SP_GENERATE_STARTER not found. Deploy the SQL objects first.</p>}

    {/* Source summary */}
    <p className="muted-note">Source: <strong>LIMITS_INDICATORS_REPORT_DATA</strong> · {rows.data?.length ?? "..."} rows for COB {cob}</p>

    {config.data && <>
      {/* 1. Select columns */}
      <Panel title="Select columns">
        <div className="starter-controls">
          <label className="control-label">Language model
            <select className="field-control" value={state.model} onChange={(e) => onChange({ ...state, model: e.target.value })}>
              {config.data.models.map((m) => <option key={m} value={m}>{m}</option>)}
            </select>
          </label>
        </div>

        <fieldset className="starter-fields mt-4"><legend className="muted-note">Source columns included in prompt</legend>
          <div className="starter-controls" style={{marginBottom:"0.5rem"}}>
            <button className="action-secondary" type="button" onClick={() => onChange({ ...state, fields: [...config.data!.keyColumns] })}>Key columns</button>
            <button className="action-secondary" type="button" onClick={() => onChange({ ...state, fields: [...allCols] })}>All columns</button>
          </div>
          {allCols.map((col) => <label key={col}><input type="checkbox" checked={state.fields.includes(col)} onChange={() => onChange({ ...state, fields: state.fields.includes(col) ? state.fields.filter((f) => f !== col) : [...state.fields, col] })} />{col}</label>)}
        </fieldset>
      </Panel>

      {/* 2. Data dictionary for selected columns */}
      {sections && sections.dictEntries.length > 0 && <Panel title="Data dictionary">
        <p className="muted-note mb-2">DDL column comments for the {sections.dictEntries.length} selected column{sections.dictEntries.length === 1 ? "" : "s"} that have descriptions.</p>
        <pre className="starter-code" style={{maxHeight:"14rem",overflow:"auto"}}>{sections.dictEntries.join("\n")}</pre>
      </Panel>}

      {/* 3. System prompt */}
      <Panel title="System prompt">
        <p className="muted-note mb-2">Preamble + 9 rules ({sections?.systemPrompt.length ?? 0} chars) — sent as the first part of every AI_COMPLETE call.</p>
        <pre className="starter-code" style={{maxHeight:"14rem",overflow:"auto"}}>{sections?.systemPrompt}</pre>

        <details className="mt-3"><summary className="muted-note">Length and tone by breach level (adapts per row)</summary>
          <div className="mt-2 space-y-2">{Object.entries(config.data.toneInstructions).map(([k, v]) =>
            <p key={k} className="muted-note"><strong>{k}:</strong> {v}</p>
          )}</div>
        </details>
      </Panel>

      {/* 4. SQL / Resolved prompt */}
      <Panel title="Preview">
        <div className="segmented">{["SQL", "Resolved prompt"].map((label) =>
          <button key={label} aria-pressed={tab === label} onClick={() => setTab(label)}>{label}</button>)}</div>
        {preview.error && <ErrorNote error={preview.error} />}
        {preview.isFetching && <Spinner label="Loading preview" />}
        <div className="mt-3">
          {tab === "SQL" && sections && <>
            <p className="muted-note mb-2">Self-contained SQL. <code>@system_prompt</code> and <code>@data_dictionary</code> expand to the values shown above.</p>
            <pre className="starter-code">{sections.sql}</pre>
          </>}
          {tab === "Resolved prompt" && preview.data?.row && <>
            <p className="muted-note mb-2">Exact prompt for: {preview.data.row.METRIC_NAME} (record {preview.data.row.RECORD_ID}, status: {preview.data.row.STATUS})</p>
            <pre className="starter-code">{preview.data.row.PROMPT}</pre>
          </>}
        </div>
      </Panel>
    </>}
  </div>
}
