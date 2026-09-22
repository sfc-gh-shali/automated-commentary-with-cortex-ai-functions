# Automated Commentary with Cortex AI — Handout

Generate first-draft commentary for a liquidity-risk report using one SQL function.
No model-serving infrastructure, no external LLM API, no SDK.

## What this does

```
Source report table  →  AI_COMPLETE(model, prompt)  →  Commentary store  →  Analyst review
```

Each row in the report gets a prompt assembled from a system instruction, a data dictionary,
and the row's own column values. `AI_COMPLETE` returns the model's response as a VARCHAR.
A stored procedure wraps this in fingerprint checks so unchanged rows are skipped on re-runs.

## Prerequisites

- A Snowflake account with Cortex AI access
- A warehouse (the setup script creates `LRI_DEMO_WH`, size XS)
- Model privileges for the model you intend to use (e.g. `claude-sonnet-5`)

## Setup

### Option A: CLI

```bash
# From the repo root — creates database, schema, tables, views, and seed data
snowflake/build.sh <connection>
```

### Option B: Manual

Run each SQL file in order in a Snowflake worksheet:

```
snowflake/01_setup.sql          -- database, schema, warehouse
snowflake/02_base_table.sql     -- source report table
snowflake/03_udfs.sql           -- helper functions
snowflake/04_metric_definitions.sql  -- 10 metrics × 4 scopes
snowflake/05_generate_data.sql  -- 200 synthetic report rows
snowflake/06_derived_facts.sql  -- fact derivation view
snowflake/07_prompts.sql        -- prompt assembly view
snowflake/08_commentary_store.sql    -- commentary table + historical procedure
snowflake/09_views.sql          -- report and summary views
snowflake/10_starter.sql        -- starter prompt function + batch procedure
```

## Notebook walkthrough

Open `handout/automated_commentary.ipynb` in a Snowsight workspace and run the cells in order.

### What each cell does

| Step | What it does |
| --- | --- |
| 1. Setup | Sets the warehouse and schema |
| 2. Explore | Shows key columns from the source report for one COB date |
| 3. Prompt | Displays the pre-built prompt from `V_PROMPT_ALL` for one row |
| 4. Single row | Calls `AI_COMPLETE` on one row — the core pattern |
| 5. Batch | Calls `SP_GENERATE_STARTER` to process all 40 rows |
| 6. Review | Queries `AI_COMMENTARY` to see stored results with model and timestamps |
| 7. Fingerprint | Re-runs the procedure to show unchanged rows are skipped |
| 8. Standalone | Self-contained `SELECT` with `CONCAT_WS` — no views needed |
| 9. Cleanup | Points to the cleanup script |

## Key SQL patterns

### The core call

```sql
SELECT AI_COMPLETE('claude-sonnet-5', prompt)::VARCHAR AS COMMENTARY
FROM V_PROMPT_ALL
WHERE APPROACH = 'DIRECT_FULL' AND REPORT_AS_OF_COB_DATE = '2026-09-08';
```

### Building a prompt from columns

```sql
CONCAT_WS(CHR(10),
  'Your instruction here.',
  'RECORD:',
  'METRIC_NAME = ' || COALESCE(TO_VARCHAR(r.METRIC_NAME), '(null)'),
  'CURRENT_VALUE = ' || COALESCE(TO_VARCHAR(r.CURRENT_VALUE), '(null)'),
  'BREACH_LEVEL = ' || COALESCE(TO_VARCHAR(r.BREACH_LEVEL), '(null)')
)
```

`CONCAT_WS` joins parts with newlines. `COALESCE` makes missing values explicit
rather than turning the entire prompt into NULL.

### Persisting with fingerprint checks

The stored procedure:
1. Reads prompts from `V_PROMPT_ALL`
2. Compares `INPUT_HASH` against stored commentary
3. Only calls `AI_COMPLETE` for rows where the prompt or model changed
4. MERGEs results into `AI_COMMENTARY`, preserving analyst edits

## Demo app (optional)

The repo also includes a React/Express presentation client that provides a visual
walkthrough of the same flow.

```bash
npm install
npm run dev
# Open http://localhost:5177
```

The app is a presentation layer — the same SQL runs in a worksheet.

## Cleanup

When done, drop all demo objects to avoid recurring warehouse and storage costs:

```bash
snow sql -c DEMO -f snowflake/cleanup.sql
```

Or run `snowflake/cleanup.sql` in a worksheet. It drops views, procedures, functions,
tables, the warehouse, the schema, and the database — in that order.

## Customization

To adapt this for a different source table:

1. **Change the source query** — Replace `LIMITS_INDICATORS_REPORT_DATA` with your table
2. **Choose your columns** — Pick the columns that carry the facts the commentary should reference
3. **Write the system prompt** — Set the persona, tone, and rules for the model
4. **Add a data dictionary** — Include DDL column comments so the model understands field names
5. **Pick a model** — Use `SHOW CORTEX BASE MODELS` to see what's available in your account
6. **Store results** — MERGE into a commentary table with the prompt, model, and timestamp

The pattern is the same regardless of the domain: `AI_COMPLETE(model, CONCAT_WS(...))`.
