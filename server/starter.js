import { readFileSync } from "node:fs"

export const VERSION = "starter-v1"
export const MODELS = ["claude-sonnet-5", "claude-opus-5", "openai-gpt-5.6-terra"]

// System prompt components displayed in the UI (from 07_prompts.sql)
export const PREAMBLE = "You are a liquidity risk reporting analyst at a global bank, drafting pre-commentary for the daily Limits and Indicators report. Your draft is reviewed and signed off by a human analyst before publication."

export const RULES = `Write commentary for the metric below using ONLY the information provided.

RULES -- these are not stylistic preferences:
1. Do NOT state, imply, or speculate about WHY the metric moved. No cause is given, so any explanation you supply would be invented. Describe what the position is and how it has changed, never why.
2. Do NOT introduce any figure, date, threshold or percentage that is not stated below.
3. Refer to the event using the exact terminology defined for the metric.
4. Do NOT recommend specific remedial actions, and do NOT name any team, system, desk, client or counterparty.
5. Write in formal third person. No first person, no addressing the reader, and no hedging filler such as "it appears that" or "it would seem".
6. Do NOT use internal system codes, field names or enumerated values in the text (for example BREACH_L2, DETERIORATING, CURRENT_VALUE, NO_SOURCE_DATA). Refer to levels in natural language, such as "a Level 2 breach", "the L2 threshold".
7. Where a figure below is qualified as "at least", you MUST preserve that qualifier.
8. Output plain prose only. No markdown, no bullet points, no headings, no preamble, and no closing summary. Do not restate the metric name as a title.
9. Output ONLY the finished commentary. Never include reasoning, working, self-correction or asides.`

export const TONE_INSTRUCTIONS = {
  BREACH_L3: "This is a Level 3 breach: the most severe classification, carrying senior management and executive escalation obligations. Write three to four sentences.",
  BREACH_L2: "This is a Level 2 breach: material, requiring management escalation. Write two to three sentences.",
  BREACH_L1: "This is a Level 1 breach: the early-warning tolerance. Write ONE measured sentence.",
  NEAR_MISS: "This metric is NOT in breach, but close to the L1 threshold. Write ONE sentence.",
  WITHIN_LIMIT: "This metric is within its limit. Write ONE brief sentence confirming the position."
}

export const KEY_COLUMNS = ["METRIC_NAME", "DIMENSION_TYPE_CODE", "LOB_DESCRIPTION", "LEGAL_ENTITY_DESCRIPTION", "CURRENT_VALUE", "REPORTING_UNIT", "L1_LIMIT_VALUE", "L2_LIMIT_VALUE", "L3_LIMIT_VALUE", "LIMIT_DIRECTION", "BREACH_LEVEL", "BREACH_AMOUNT", "CURRENT_UTILIZATION_LEVEL", "HAS_SOURCE_DATA"]

export const COLUMN_COMMENTS_SQL = `SELECT OBJECT_AGG(c.COLUMN_NAME, c.COMMENT::VARIANT) AS COMMENTS
 FROM INFORMATION_SCHEMA.COLUMNS c
 WHERE c.TABLE_SCHEMA = 'LRI_BASE' AND c.TABLE_NAME = 'LIMITS_INDICATORS_REPORT_DATA'
 AND c.COMMENT IS NOT NULL`

function invalid(message) { return Object.assign(new Error(message), { status: 400 }) }

export function sqlLiteral(value) { return `'${String(value).replaceAll("\\", "\\\\").replaceAll("'", "''")}'` }

export function batchSql(model) {
  return `SELECT r.RECORD_UNIQUE_IDENTIFIER,
  AI_COMPLETE(${sqlLiteral(model)}, p.PROMPT)::VARCHAR AS COMMENTARY
FROM V_PROMPT_ALL p
JOIN LIMITS_INDICATORS_REPORT_DATA r
  ON r.RECORD_UNIQUE_IDENTIFIER = p.RECORD_UNIQUE_IDENTIFIER
WHERE p.APPROACH = 'DIRECT_FULL'
  AND p.REPORT_AS_OF_COB_DATE = TO_DATE(?)
  AND p.HAS_DATA = TRUE;`
}

// Source rows query
export const SOURCE_ROWS = `SELECT r.*
 FROM LIMITS_INDICATORS_REPORT_DATA r
 WHERE r.REPORT_AS_OF_COB_DATE = TO_DATE(?) ORDER BY r.METRIC_KEY`

// Results (table out) query
export const RESULTS_ROWS = `SELECT r.RECORD_UNIQUE_IDENTIFIER, r.METRIC_KEY, r.METRIC_NAME, r.DIMENSION_TYPE_CODE,
 r.LOB_DESCRIPTION, r.LEGAL_ENTITY_DESCRIPTION, r.CURRENT_VALUE, r.REPORTING_UNIT,
 r.L1_LIMIT_VALUE, r.L2_LIMIT_VALUE, r.L3_LIMIT_VALUE, r.LIMIT_DIRECTION,
 r.BREACH_LEVEL, r.BREACH_AMOUNT, r.CURRENT_UTILIZATION_LEVEL, r.HAS_SOURCE_DATA,
 c.AI_COMMENTARY, c.AI_COMMENTARY AS ORIGINAL_DRAFT, c.FINAL_COMMENTARY,
 c.MODEL_NAME, c.MODEL_NAME AS STORED_MODEL, c.PROMPT_INPUT AS STORED_PROMPT,
 c.PROMPT_VERSION, c.PROMPT_VERSION AS STORED_VERSION,
 c.GENERATED_AT, c.IS_EDITED, c.NEEDS_REVIEW
 FROM LIMITS_INDICATORS_REPORT_DATA r
 LEFT JOIN AI_COMMENTARY c ON c.RECORD_UNIQUE_IDENTIFIER = r.RECORD_UNIQUE_IDENTIFIER AND c.APPROACH = 'STARTER'
 WHERE r.REPORT_AS_OF_COB_DATE = TO_DATE(?) ORDER BY r.METRIC_KEY`

// First-row prompt from V_PROMPT_ALL for preview
export const FIRST_ROW_PROMPT = `SELECT RECORD_UNIQUE_IDENTIFIER AS RECORD_ID, METRIC_NAME,
 PROMPT, PROMPT_INPUT, HAS_DATA, STATUS, STATIC_COMMENTARY
 FROM V_PROMPT_ALL
 WHERE APPROACH = 'DIRECT_FULL' AND REPORT_AS_OF_COB_DATE = TO_DATE(?)
 ORDER BY SEVERITY_RANK DESC, METRIC_KEY
 LIMIT 1`

export function registerStarter(app, { query, queryOne, route }) {
  let columnComments = null
  async function getComments() {
    if (columnComments) return columnComments
    try {
      const row = await queryOne(COLUMN_COMMENTS_SQL)
      const raw = row?.COMMENTS ?? "{}"
      columnComments = typeof raw === "string" ? JSON.parse(raw) : raw
    } catch { columnComments = {} }
    return columnComments
  }

  // Config
  app.get("/api/starter/config", route(async (_req, res) => {
    let deployed = false
    try {
      const procedures = await query("SHOW PROCEDURES LIKE 'SP_GENERATE_STARTER' IN SCHEMA")
      const viewCheck = await queryOne("SELECT COUNT(*) AS CNT FROM V_PROMPT_ALL WHERE APPROACH = 'DIRECT_FULL' LIMIT 1")
      deployed = procedures.some((e) => String(e.name ?? e.NAME).toUpperCase() === "SP_GENERATE_STARTER") && (viewCheck?.CNT ?? 0) > 0
    } catch { deployed = false }
    res.json({
      models: MODELS, keyColumns: KEY_COLUMNS, deployed, version: VERSION,
      preamble: PREAMBLE, rules: RULES, toneInstructions: TONE_INSTRUCTIONS,
      columnComments: await getComments(),
      storageSql: readFileSync(new URL("../snowflake/10_starter.sql", import.meta.url), "utf8")
    })
  }))

  // Source rows (table in)
  app.get("/api/starter/rows", route(async (req, res) => {
    const cob = req.query.cob
    if (!cob || !/^\d{4}-\d{2}-\d{2}$/.test(cob)) throw invalid("Valid COB required")
    res.json(await query(SOURCE_ROWS, { binds: [cob] }))
  }))

  // Results (table out)
  app.get("/api/starter/results", route(async (req, res) => {
    const cob = req.query.cob
    if (!cob || !/^\d{4}-\d{2}-\d{2}$/.test(cob)) throw invalid("Valid COB required")
    res.json(await query(RESULTS_ROWS, { binds: [cob] }))
  }))

  // Preview (first row prompt + SQL)
  app.post("/api/starter/preview", route(async (req, res) => {
    const { cob, model } = req.body ?? {}
    if (!cob || !MODELS.includes(model)) throw invalid("Valid COB and model required")
    const row = await queryOne(FIRST_ROW_PROMPT, { binds: [cob] })
    res.json({
      row,
      sql: batchSql(model).replace("TO_DATE(?)", `TO_DATE(${sqlLiteral(cob)})`)
    })
  }))

  // Generate (batch — all rows for COB)
  app.post("/api/starter/generate", route(async (req, res) => {
    const { cob, model } = req.body ?? {}
    if (!cob || !/^\d{4}-\d{2}-\d{2}$/.test(cob)) throw invalid("Valid COB required")
    if (!MODELS.includes(model)) throw invalid("Unsupported model")
    const started = Date.now()
    const result = await queryOne("CALL SP_GENERATE_STARTER(TO_DATE(?), ?)", {
      binds: [cob, model], timeoutSeconds: 900,
    })
    res.json({ message: result ? Object.values(result)[0] : "No result returned", elapsed_ms: Date.now() - started, model })
  }))

  // Reset (all STARTER commentary for COB)
  app.post("/api/starter/reset", route(async (req, res) => {
    const { cob } = req.body ?? {}
    if (!cob || !/^\d{4}-\d{2}-\d{2}$/.test(cob)) throw invalid("Valid COB required")
    const result = await query("DELETE FROM AI_COMMENTARY WHERE APPROACH = 'STARTER' AND REPORT_AS_OF_COB_DATE = TO_DATE(?)", { binds: [cob] })
    res.json({ ok: true, result })
  }))
}
