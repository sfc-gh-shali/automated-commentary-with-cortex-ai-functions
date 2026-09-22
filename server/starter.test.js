import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { validateRequest, coreSql, sqlLiteral, registerStarter, DEFAULT_INSTRUCTION, DEFAULT_FIELDS, GUARDRAILS, MODELS, PREVIEW } from "./starter.js"

const valid = () => ({ cob: "2026-09-08", recordIds: [10], fields: [...DEFAULT_FIELDS], instruction: DEFAULT_INSTRUCTION, model: MODELS[0] })
test("valid request preserves selected field order and instruction content", () => {
  const body = { ...valid(), instruction: "  Analyst's note\nDo not speculate.  ", fields: ["CURRENT_VALUE", "METRIC_NAME"] }
  const result = validateRequest(body)
  assert.equal(result.instruction, "Analyst's note\nDo not speculate.")
  assert.deepEqual(result.fields, body.fields)
})
test("reject invalid scopes, dates, models and identifiers", () => {
  for (const patch of [
    { cob: "2026-02-30" }, { cob: "2026-09-08'; DELETE" }, { recordIds: [] },
    { recordIds: [1, "2"] }, { recordIds: [1, 1] }, { recordIds: [1.5] },
    { recordIds: [-1] }, { recordIds: [Number.MAX_SAFE_INTEGER + 1] },
    { recordIds: Array.from({ length: 41 }, (_, index) => index + 1) },
    { fields: [] }, { fields: ["CURRENT_VALUE", "CURRENT_VALUE"] },
    { fields: ["CURRENT_VALUE); DROP TABLE x"] }, { fields: [null] },
    { instruction: " " }, { instruction: "x".repeat(2001) }, { model: "not-allowed" },
  ]) assert.throws(() => validateRequest({ ...valid(), ...patch }), { status: 400 })
})
test("core SQL selects the requested model and bounds rows before generation", () => {
  const sql = coreSql({ ...valid(), recordIds: [10, 20], model: MODELS[2] })
  assert.ok(sql.includes(`AI_COMPLETE('${MODELS[2]}'`))
  assert.ok(sql.includes("IN (10, 20)"))
  assert.ok(sql.includes("COALESCE(TO_VARCHAR(r.CURRENT_VALUE), '(null)')"))
  assert.ok(sql.includes(GUARDRAILS))
  assert.ok(!sql.includes("V_METRIC_FACTS"))
})
test("literal escaping retains apostrophes, newlines and backslashes", () => {
  assert.equal(sqlLiteral("O'Brien\\n\nline"), "'O''Brien\\\\n\nline'")
})
test("preview and generation reference one prompt function and aligned guardrails", () => {
  const sql = readFileSync(new URL("../snowflake/10_starter.sql", import.meta.url), "utf8")
  assert.ok(PREVIEW.includes("FN_STARTER_PROMPT"))
  assert.ok(sql.includes("FN_STARTER_PROMPT(OBJECT_CONSTRUCT_KEEP_NULL(r.*), :v_fields, TRIM(:P_INSTRUCTION))"))
  assert.ok(sql.includes(GUARDRAILS))
  assert.ok(sql.includes("IS_NULL_VALUE(GET(RECORD"))
  assert.ok(sql.includes("ORDER BY field.index"))
  assert.ok(sql.includes("ARRAY_CONSTRUCT(source.PROMPT, source.HAS_DATA, :P_MODEL, 'starter-v1')"))
  assert.ok(sql.includes("IFF(target.IS_EDITED, target.FINAL_COMMENTARY, source.COMMENTARY)"))
  assert.ok(sql.includes("FROM TMP_STARTER_PENDING pending WHERE HAS_DATA"))
  assert.ok(sql.includes("FROM TMP_STARTER_PENDING pending WHERE NOT HAS_DATA"))
  assert.ok(!sql.includes("CREATE OR REPLACE TABLE AI_COMMENTARY"))
})

function harness(overrides = {}) {
  const routes = new Map()
  const calls = []
  registerStarter({ get: (path, handler) => routes.set(path, handler), post: (path, handler) => routes.set(path, handler) }, {
    route: (handler) => handler,
    query: async (sql, options) => { calls.push({ sql, options }); return overrides.rows ?? [] },
    queryOne: async (sql, options) => { calls.push({ sql, options }); return { RESULT: "done" } },
  })
  return { calls, async invoke(path, body) {
    let payload
    await routes.get(path)({ body }, { json: (value) => { payload = value } })
    return payload
  } }
}
test("generation binds model, instructions and exact row/COB scope", async () => {
  const app = harness()
  const body = { ...valid(), model: MODELS[1], instruction: "O'Brien\nsource only" }
  const result = await app.invoke("/api/starter/generate", body)
  assert.equal(app.calls.length, 1)
  assert.deepEqual(app.calls[0].options.binds, [body.cob, "[10]", JSON.stringify(body.fields), body.instruction, MODELS[1]])
  assert.ok(app.calls[0].sql.startsWith("CALL SP_GENERATE_STARTER"))
  assert.equal(result.model, MODELS[1])
})
test("wrong COB row selection rejects a preview", async () => {
  const app = harness({ rows: [] })
  await assert.rejects(app.invoke("/api/starter/preview", valid()), { status: 400 })
})
test("local SQL preview invokes no database or model", async () => {
  const app = harness()
  const result = await app.invoke("/api/starter/sql", valid())
  assert.ok(result.sql.includes("CONCAT_WS"))
  assert.equal(app.calls.length, 0)
})
test("reset deletes only selected STARTER rows and date", async () => {
  const app = harness()
  await app.invoke("/api/starter/reset", { cob: valid().cob, recordIds: [10, 20] })
  assert.ok(app.calls[0].sql.includes("APPROACH = 'STARTER'"))
  assert.deepEqual(app.calls[0].options.binds, [valid().cob, "[10,20]"])
})