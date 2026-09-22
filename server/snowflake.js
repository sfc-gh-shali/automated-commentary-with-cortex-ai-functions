/*
 * Snowflake access for the Express server.
 *
 * Talks to the Snowflake SQL REST API directly, signing a keypair JWT with
 * node:crypto. Zero external dependencies.
 *
 * Why not the official snowflake-sdk? Two reasons, in order of weight:
 *
 *   1. Its dependency tree currently does not install. snowflake-sdk pulls the
 *      full AWS SDK v3 (for stage PUT/GET), and several recently published
 *      aws-sdk packages reference sibling versions one patch ahead of what is
 *      on the registry (e.g. @aws-sdk/credential-provider-login@^3.972.78 when
 *      3.972.77 is the newest published). npm overrides turn into whack-a-mole.
 *   2. This app only runs SELECTs and one CALL. It never transfers a stage
 *      file, so the entire aws/azure/gcp storage tree was dead weight, and the
 *      driver only officially supports Node v20/v22/v24 -- this machine runs
 *      v26.
 *
 * The REST API needs a signed JWT and fetch, both of which Node has built in.
 */

import crypto from "node:crypto"
import fs from "node:fs"

const {
  SNOWFLAKE_ACCOUNT,
  SNOWFLAKE_USER,
  SNOWFLAKE_PRIVATE_KEY_PATH,
  SNOWFLAKE_PRIVATE_KEY_PASS,
  SNOWFLAKE_ROLE,
  SNOWFLAKE_WAREHOUSE,
  SNOWFLAKE_DATABASE,
  SNOWFLAKE_SCHEMA,
} = process.env

for (const [name, value] of Object.entries({
  SNOWFLAKE_ACCOUNT,
  SNOWFLAKE_USER,
  SNOWFLAKE_PRIVATE_KEY_PATH,
})) {
  if (!value) {
    throw new Error(
      `Missing ${name}. Copy server/.env.example to server/.env and fill it in.`,
    )
  }
}

/*
 * Account identifier handling. Two different transformations, easy to conflate:
 *
 *   JWT claims  -- uppercase, keep the org-account hyphen, periods become
 *                  hyphens. SFSENORTHAMERICA-SHALI_AWS1 stays as-is.
 *   URL host    -- lowercase, and underscores become hyphens because
 *                  underscores are not legal in a hostname.
 *                  -> sfsenorthamerica-shali-aws1.snowflakecomputing.com
 */
const ACCOUNT_FOR_JWT = SNOWFLAKE_ACCOUNT.toUpperCase().replace(/\./g, "-")
const USER_FOR_JWT = SNOWFLAKE_USER.toUpperCase()
const ACCOUNT_HOST = SNOWFLAKE_ACCOUNT.toLowerCase().replace(/[._]/g, "-")
const BASE_URL = `https://${ACCOUNT_HOST}.snowflakecomputing.com`

function base64url(buf) {
  return Buffer.from(buf)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "")
}

function loadPrivateKey() {
  const pem = fs.readFileSync(SNOWFLAKE_PRIVATE_KEY_PATH)
  // passphrase must be undefined, not null/"" -- an unencrypted PKCS#8 key
  // throws if one is supplied.
  return crypto.createPrivateKey(
    SNOWFLAKE_PRIVATE_KEY_PASS
      ? { key: pem, format: "pem", passphrase: SNOWFLAKE_PRIVATE_KEY_PASS }
      : { key: pem, format: "pem" },
  )
}

const privateKey = loadPrivateKey()

/**
 * SHA256 of the DER-encoded SubjectPublicKeyInfo, base64, prefixed "SHA256:".
 * Must equal RSA_PUBLIC_KEY_FP from `DESCRIBE USER`.
 */
function publicKeyFingerprint() {
  const der = crypto
    .createPublicKey(privateKey)
    .export({ format: "der", type: "spki" })
  return "SHA256:" + crypto.createHash("sha256").update(der).digest("base64")
}

export const FINGERPRINT = publicKeyFingerprint()

/*
 * JWTs are valid for at most an hour. Mint one for 55 minutes and reuse it, so
 * a grid refresh is not doing RSA work on every request.
 */
let cachedToken = null
let cachedTokenExpiry = 0

function getJwt() {
  const now = Math.floor(Date.now() / 1000)
  if (cachedToken && now < cachedTokenExpiry - 60) return cachedToken

  const qualifiedUser = `${ACCOUNT_FOR_JWT}.${USER_FOR_JWT}`
  const header = { alg: "RS256", typ: "JWT" }
  const payload = {
    iss: `${qualifiedUser}.${FINGERPRINT}`,
    sub: qualifiedUser,
    iat: now,
    exp: now + 55 * 60,
  }

  const signingInput = `${base64url(JSON.stringify(header))}.${base64url(
    JSON.stringify(payload),
  )}`
  const signature = crypto.sign(
    "RSA-SHA256",
    Buffer.from(signingInput),
    privateKey,
  )

  cachedToken = `${signingInput}.${base64url(signature)}`
  cachedTokenExpiry = payload.exp
  return cachedToken
}

/*
 * The SQL API returns every value as a string (or null), plus a rowType array
 * describing the real types. Converting here means route handlers and the React
 * layer never have to think about it.
 */
function convert(raw, type) {
  if (raw === null || raw === undefined) return null
  switch (type) {
    case "fixed":
    case "real":
      // NaN is impossible from Snowflake here, but Number("") is 0, which would
      // silently invent a zero. Guard the empty string explicitly.
      return raw === "" ? null : Number(raw)
    case "boolean":
      return raw === "true" || raw === true
    case "date":
      // Days since epoch, per the SQL API wire format.
      return new Date(Number(raw) * 86_400_000).toISOString().slice(0, 10)
    case "timestamp_ntz":
    case "timestamp_ltz":
    case "timestamp_tz": {
      // Seconds with a fractional part. Normalise to ISO at the boundary:
      // locale strings break both display and sorting downstream.
      const seconds = Number(String(raw).split(" ")[0])
      if (!Number.isFinite(seconds)) return String(raw)
      return new Date(seconds * 1000).toISOString()
    }
    default:
      return raw
  }
}

function shapeRows(body) {
  const columns = (body.resultSetMetaData?.rowType ?? []).map((c) => ({
    name: c.name,
    type: c.type,
  }))
  return (body.data ?? []).map((row) => {
    const out = {}
    row.forEach((value, i) => {
      const col = columns[i]
      if (col) out[col.name] = convert(value, col.type)
    })
    return out
  })
}

async function post(path, body) {
  const res = await fetch(`${BASE_URL}${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${getJwt()}`,
      "X-Snowflake-Authorization-Token-Type": "KEYPAIR_JWT",
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify(body),
  })
  return res
}

async function getStatement(handle) {
  const res = await fetch(`${BASE_URL}/api/v2/statements/${handle}`, {
    headers: {
      Authorization: `Bearer ${getJwt()}`,
      "X-Snowflake-Authorization-Token-Type": "KEYPAIR_JWT",
      Accept: "application/json",
    },
  })
  return res
}

async function readError(res) {
  let detail = ""
  try {
    const body = await res.json()
    detail = body.message || body.error || JSON.stringify(body)
  } catch {
    detail = await res.text().catch(() => "")
  }
  return `Snowflake returned ${res.status}: ${detail}`.trim()
}

/**
 * Run a statement and return fully typed rows.
 *
 * `binds` are positional `?` placeholders. Always use them for anything that
 * came from the browser -- the commentary save route writes to a table.
 *
 * Long statements (the generate procedure takes roughly 20 seconds) are handled
 * by polling: the API returns 202 with a statementHandle when it exceeds the
 * inline timeout, so we wait on the handle rather than holding one long request.
 */
export async function query(sql, { binds = [], timeoutSeconds = 300 } = {}) {
  const body = {
    statement: sql,
    timeout: timeoutSeconds,
    warehouse: SNOWFLAKE_WAREHOUSE,
    database: SNOWFLAKE_DATABASE,
    schema: SNOWFLAKE_SCHEMA,
  }
  if (SNOWFLAKE_ROLE) body.role = SNOWFLAKE_ROLE
  if (binds.length) {
    body.bindings = Object.fromEntries(
      binds.map((v, i) => [
        String(i + 1),
        { type: "TEXT", value: v === null || v === undefined ? null : String(v) },
      ]),
    )
  }

  let res = await post("/api/v2/statements", body)

  // 202 means still running -- poll the handle until it resolves.
  if (res.status === 202) {
    const { statementHandle } = await res.json()
    const deadline = Date.now() + timeoutSeconds * 1000
    while (Date.now() < deadline) {
      await new Promise((r) => setTimeout(r, 1000))
      res = await getStatement(statementHandle)
      if (res.status !== 202) break
    }
    if (res.status === 202) {
      throw new Error(
        `Statement ${statementHandle} still running after ${timeoutSeconds}s`,
      )
    }
  }

  if (!res.ok) throw new Error(await readError(res))

  const payload = await res.json()
  const rows = shapeRows(payload)

  /*
   * Paginate. The API caps an inline page, and the report grid asks for 200
   * rows of a wide view, so this is not hypothetical.
   */
  const totalPages = payload.resultSetMetaData?.partitionInfo?.length ?? 1
  if (totalPages > 1 && payload.statementHandle) {
    for (let p = 1; p < totalPages; p++) {
      const pageRes = await fetch(
        `${BASE_URL}/api/v2/statements/${payload.statementHandle}?partition=${p}`,
        {
          headers: {
            Authorization: `Bearer ${getJwt()}`,
            "X-Snowflake-Authorization-Token-Type": "KEYPAIR_JWT",
            Accept: "application/json",
          },
        },
      )
      if (!pageRes.ok) throw new Error(await readError(pageRes))
      const pageBody = await pageRes.json()
      // Later partitions carry no metadata of their own.
      rows.push(
        ...shapeRows({
          data: pageBody.data,
          resultSetMetaData: payload.resultSetMetaData,
        }),
      )
    }
  }

  return rows
}

/** First row only, or null. */
export async function queryOne(sql, options) {
  const rows = await query(sql, options)
  return rows[0] ?? null
}

export const connectionInfo = {
  account: SNOWFLAKE_ACCOUNT,
  host: ACCOUNT_HOST,
  user: SNOWFLAKE_USER,
  role: SNOWFLAKE_ROLE,
  warehouse: SNOWFLAKE_WAREHOUSE,
  schema: `${SNOWFLAKE_DATABASE}.${SNOWFLAKE_SCHEMA}`,
  fingerprint: FINGERPRINT,
}
