/*
 * Express server for the automated-commentary demo.
 *
 * Owns the Snowflake connection so the browser never holds a credential. Every
 * route is a thin wrapper over a statement in queries.js -- no arithmetic and no
 * formatting happens here, because the SQL layer already did both.
 *
 * There is no scheduling surface. Commentary is generated on demand from the app,
 * under one of two approaches, and can be cleared to run the demo again.
 */

import express from "express"
import { query, queryOne, connectionInfo } from "./snowflake.js"
import * as Q from "./queries.js"
import { registerStarter } from "./starter.js"

const app = express()
app.use(express.json({ limit: "1mb" }))

const PORT = Number(process.env.PORT ?? 3001)

const APPROACHES = new Set(["GROUNDED", "DIRECT_FULL", "STARTER"])

function route(handler) {
  return async (req, res) => {
    try {
      await handler(req, res)
    } catch (err) {
      const status = err?.status ?? 500
      const message = err instanceof Error ? err.message : String(err)
      if (status >= 500) {
        console.error(new Date().toISOString(), req.method, req.path, message)
      }
      res.status(status).json({ error: message })
    }
  }
}

function bad(message) {
  const err = new Error(message)
  err.status = 400
  return err
}

/** Constrain a COB to a date shape before it reaches a bind. */
function requireCob(req) {
  const cob = String(req.query.cob ?? req.body?.cob ?? "")
  if (!/^\d{4}-\d{2}-\d{2}$/.test(cob)) throw bad("cob must be a YYYY-MM-DD date")
  return cob
}

function requireApproach(req, fallback = "GROUNDED") {
  const a = String(req.query.approach ?? req.body?.approach ?? fallback).toUpperCase()
  if (!APPROACHES.has(a)) {
    throw bad("approach must be GROUNDED, DIRECT_FULL or STARTER")
  }
  return a
}

function requireInt(value, name) {
  const n = Number(value)
  if (!Number.isInteger(n)) throw bad(`${name} must be an integer`)
  return n
}

/**
 * Normalise a record-id list into the comma-separated form the procedure parses.
 * Returns null for "every pending line", which is a distinct, meaningful case.
 */
function recordIdList(value) {
  if (value === undefined || value === null) return null
  const arr = Array.isArray(value) ? value : String(value).split(",")
  const ids = arr
    .map((v) => Number(String(v).trim()))
    .filter((n) => Number.isInteger(n))
  if (!ids.length) throw bad("recordIds contained no valid integers")
  return ids.join(",")
}

app.get(
  "/api/health",
  route(async (_req, res) => {
    const row = await queryOne(
      "SELECT CURRENT_USER() AS user, CURRENT_ROLE() AS role, CURRENT_WAREHOUSE() AS warehouse",
    )
    res.json({ ok: true, connection: connectionInfo, session: row })
  }),
)

app.get(
  "/api/cob-dates",
  route(async (_req, res) => res.json(await query(Q.COB_DATES))),
)

app.get(
  "/api/summary",
  route(async (req, res) => {
    const cob = requireCob(req)
    const row = await queryOne(Q.SUMMARY, { binds: [cob] })
    if (!row) return res.status(404).json({ error: `No batch for COB ${cob}` })
    res.json(row)
  }),
)

app.get(
  "/api/report/full",
  route(async (req, res) => {
    const cob = requireCob(req)
    const approach = requireApproach(req)
    const [columns, rows] = await Promise.all([
      query(Q.RAW_ALL_COLUMNS),
      query(Q.RAW_REPORT_FULL, { binds: [approach, cob] }),
    ])
    res.json({
      approach,
      columns: [
        ...columns.map((c) => ({
          name: c.COLUMN_NAME,
          type: c.DATA_TYPE,
          comment: c.COLUMN_COMMENT,
          source: "feed",
        })),
        // Not in INFORMATION_SCHEMA for the base table -- it is joined on. Named
        // separately because "the column that did not exist before" is the point
        // of showing this table.
        {
          name: "AI_GENERATED_COMMENTARY",
          type: "TEXT",
          comment: "Added by Cortex. Empty until commentary is generated.",
          source: "cortex",
        },
      ],
      rows,
    })
  }),
)

app.get(
  "/api/grid",
  route(async (req, res) => {
    const cob = requireCob(req)
    res.json(await query(Q.GRID, { binds: [cob] }))
  }),
)

app.get(
  "/api/metrics",
  route(async (req, res) => {
    const cob = requireCob(req)
    res.json(await query(Q.METRIC_LIST, { binds: [cob] }))
  }),
)

/** What each approach would be given for one line, generated or not. */
app.get(
  "/api/prompt-inputs",
  route(async (req, res) => {
    const recordId = requireInt(req.query.recordId, "recordId")
    const rows = await query(Q.PROMPT_INPUTS, { binds: [recordId] })
    res.json(rows.filter((row) => APPROACHES.has(row.APPROACH)))
  }),
)

/** The two supported approaches side by side for one line, with their checks. */
app.get(
  "/api/comparison",
  route(async (req, res) => {
    const recordId = requireInt(req.query.recordId, "recordId")
    const row = await queryOne(Q.COMPARISON_ONE, { binds: [recordId] })
    if (!row) return res.status(404).json({ error: `No line ${recordId}` })
    res.json(row)
  }),
)

app.get(
  "/api/scorecard",
  route(async (req, res) => {
    const cob = requireCob(req)
    const rows = await query(Q.SCORECARD, { binds: [cob] })
    res.json(rows.filter((row) => APPROACHES.has(row.APPROACH)))
  }),
)

app.get(
  "/api/pending",
  route(async (req, res) => {
    const cob = requireCob(req)
    const approach = requireApproach(req)
    const row = await queryOne(Q.PENDING, { binds: [approach, cob] })
    const promptChars = row?.PROMPT_CHARS ?? 0
    res.json({
      approach,
      pending_rows: row?.PENDING_ROWS ?? 0,
      model_calls: row?.MODEL_CALLS ?? 0,
      static_rows: row?.STATIC_ROWS ?? 0,
      // Estimated from characters: AI_COUNT_TOKENS returns NULL for every model
      // in this account, and an honest estimate beats a fabricated exact.
      approx_prompt_tokens: Math.round(promptChars / 4),
    })
  }),
)

app.get(
  "/api/pending-rows",
  route(async (req, res) => {
    const cob = requireCob(req)
    const approach = requireApproach(req)
    res.json(await query(Q.PENDING_ROWS, { binds: [approach, cob] }))
  }),
)

/**
 * Generate under one approach, for a named set of lines or for every pending line.
 * The only entry point; there is no scheduled path.
 */
app.post(
  "/api/generate",
  route(async (req, res) => {
    const cob = requireCob(req)
    const approach = requireApproach(req)
    if (approach === "STARTER") throw bad("Use /api/starter/generate with explicit rows, fields and model")
    const ids = recordIdList(req.body?.recordIds)
    const force = req.body?.force === true
    const source = ids && ids.split(",").length === 1 ? "LIVE_SINGLE" : "BATCH"

    const started = Date.now()
    const row = await queryOne(Q.GENERATE, {
      binds: [cob, approach, ids, force ? "true" : "false", source],
      timeoutSeconds: 900,
    })
    res.json({
      approach,
      message: row ? Object.values(row)[0] : "",
      elapsed_ms: Date.now() - started,
      lines_requested: ids ? ids.split(",").length : null,
    })
  }),
)

app.post(
  "/api/commentary",
  route(async (req, res) => {
    const recordId = requireInt(req.body?.recordId, "recordId")
    const approach = requireApproach(req)
    const text = String(req.body?.text ?? "").trim()
    if (!text) throw bad("text must not be empty")
    await query(Q.SAVE_COMMENTARY, { binds: [text, recordId, approach] })
    res.json({ ok: true })
  }),
)

app.post(
  "/api/commentary/revert",
  route(async (req, res) => {
    const recordId = requireInt(req.body?.recordId, "recordId")
    const approach = requireApproach(req)
    await query(Q.REVERT_COMMENTARY, { binds: [recordId, approach] })
    res.json({ ok: true })
  }),
)

/**
 * Clear generated commentary. Three scopes, because a demo needs to be resettable
 * at different granularities: this approach on this COB, everything on this COB,
 * or the whole store.
 */
app.post(
  "/api/clear",
  route(async (req, res) => {
    const scope = req.body?.scope
    if (scope === "all") {
      await query(Q.CLEAR_ALL)
      return res.json({ ok: true, scope: "all" })
    }
    if (scope === "cob") {
      const cob = requireCob(req)
      await query(Q.CLEAR_COB, { binds: [cob] })
      return res.json({ ok: true, scope: "cob", cob })
    }
    if (scope === "approach") {
      const cob = requireCob(req)
      const approach = requireApproach(req)
      await query(Q.CLEAR_COB_APPROACH, { binds: [cob, approach] })
      return res.json({ ok: true, scope: "approach", cob, approach })
    }
    throw bad("scope must be 'approach', 'cob' or 'all'")
  }),
)

app.use((err, _req, res, _next) => {
  res.status(err?.status ?? 500).json({ error: err?.message ?? "Unexpected error" })
})

registerStarter(app, { query, queryOne, route })

app.listen(PORT, () => {
  console.log(
    `[server] listening on http://127.0.0.1:${PORT} -> ${connectionInfo.schema} ` +
      `as ${connectionInfo.user}/${connectionInfo.role} on ${connectionInfo.warehouse}`,
  )
})
