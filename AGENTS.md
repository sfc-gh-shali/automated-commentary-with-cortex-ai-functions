# Repository instructions

## Current direction

The approved AI-SQL-first demo supersedes the previous comparison-first story.
Four tabs: Report & Problem, Build the SQL, Commentary Results, Execution & Next Steps.
The main pipeline is Base table -> AI_COMPLETE -> Commentary store -> Analyst review.
Derived facts, structured responses and evaluation are optional best practices.
Keep the fictional GlobalTrust naming and 200-row source dataset.

## Boundaries

- Do not modify Step5Execution.tsx for this redesign; only its navigation position changed. It is reference architecture, with no live scheduling, tasks or streams.
- Do not imply zero prerequisites: Snowflake access, model privileges and compute are required. No model-serving infrastructure or external LLM integration is needed for SQL usage; React/Express is only the presentation client.
- No claim of guaranteed accuracy or production readiness. POC-in-days messaging is conditional on scoped requirements and ready data/access.
- Do not compute risk quantities in the browser. Starter prompts use source data, not hidden derived severity instructions.
- Keep STARTER results distinct from historical GROUNDED, DIRECT_FULL and DIRECT_RAW rows. Do not delete or overwrite historical assets to simplify the UI.

## Files and commands

`npm run dev`, `npm run typecheck`, `npm run build`, `node --test server/starter.test.js`.

`server/starter.js` owns field/model allowlists, validation, core SQL display and starter endpoints.
`snowflake/10_starter.sql` owns the canonical SQL prompt function and generation procedure.
`src/lib/starter.ts` owns starter hooks; `StepBuild.tsx` and `StepResults.tsx` use them.
`src/starter.css` extends the existing theme without modifying the Execution layout.

## Connection safety

The app reads server/.env. The IDE may point at a different account.
Use the declared SQL tool for SQL execution and verify CURRENT_ACCOUNT_NAME before
deployment.

Deploy only 10_starter.sql for this update after verifying the correct account.
The full build script recreates AI_COMMENTARY and destroys seeded drafts/edits.
Do not run it as a migration. Existing procedure signatures remain unchanged.

## Correctness

- Preview and generation must use FN_STARTER_PROMPT with identical inputs. Keep the expanded CONCAT_WS display equivalent, including escaping, null handling, field order and instructions.
- Selected identifiers, fields and models are validated server-side and again in the procedure. Reject malformed lists; do not silently drop invalid values.
- Empty selection never means full report. Filter/stage selected rows before AI calls.
- Fingerprints include model, prompt/version and source usability. Changing model must not serve a stale draft as fresh.
- Preserve analyst final wording on regeneration; refresh original AI text and flag re-review.
- All rows go through AI_COMPLETE; there is no separate STATIC generation branch. Empty AI output is not a valid draft; retry only on explicit generation.
- Model catalog visibility is not invocation authorization or lifecycle eligibility. Never silently substitute another model.
- Generation/reset must remain explicit; no paid calls on preview or UI verification. Reset is scoped to STARTER records and COB, including analyst edits, with confirmation.
- The original comparison checks are heuristics, not starter evaluation or approval. Inspect offending text and source evidence before citing a flag.

## Verification

Run typecheck, build and Node tests. Browser-check navigation, prompt/model
changes, error/deployment states and narrow-screen overflow. Mocked
tests do not prove Snowflake SQL execution. Report blocked deployment and skipped paid
checks explicitly. Do not retry a browser task the user cancelled.

Follow existing semantic CSS classes, Radix/lucide patterns,
and React Query invalidation. Keep credentials out of commits and API responses.
Update README.md, DEMO_WALKTHROUGH.md together when the narrative changes.
