/*
 * Every SQL statement the app runs, in one place.
 *
 * All of these read objects that already exist in LRI_DEMO.LRI_BASE -- see
 * snowflake/*.sql. The UI owns no arithmetic and no formatting: breach levels,
 * utilisation, streaks, headroom and every display string come out of the SQL
 * layer already computed. That is the same reason the model is handed a prepared
 * fact block rather than a table.
 *
 * Anything originating in the browser is passed as a positional `?` bind.
 */

/** Distinct COB dates, newest first, with commentary coverage per date. */
export const COB_DATES = `
SELECT
    REPORT_AS_OF_COB_DATE   AS cob_date,
    BATCH_IDENTIFIER        AS batch_identifier,
    TOTAL_METRICS           AS total_metrics,
    REQUIRES_COMMENTARY     AS requires_commentary,
    HAS_COMMENTARY          AS has_commentary,
    COMMENTARY_MISSING      AS commentary_missing
FROM V_COB_SUMMARY
ORDER BY REPORT_AS_OF_COB_DATE DESC
`

/** Header tiles for one COB. Coverage figures reflect the grounded approach. */
export const SUMMARY = `
SELECT
    REPORT_AS_OF_COB_DATE   AS cob_date,
    BATCH_IDENTIFIER        AS batch_identifier,
    TOTAL_METRICS           AS total_metrics,
    BREACH_L3               AS breach_l3,
    BREACH_L2               AS breach_l2,
    BREACH_L1               AS breach_l1,
    NEAR_MISS               AS near_miss,
    NO_SOURCE_DATA          AS no_source_data,
    WITHIN_LIMIT            AS within_limit,
    REQUIRES_COMMENTARY     AS requires_commentary,
    HAS_COMMENTARY          AS has_commentary,
    COMMENTARY_MISSING      AS commentary_missing,
    ANALYST_EDITED          AS analyst_edited,
    NEEDS_REVIEW            AS needs_review,
    LAST_GENERATED_AT       AS last_generated_at,
    LAST_GENERATION_SOURCE  AS last_generation_source
FROM V_COB_SUMMARY
WHERE REPORT_AS_OF_COB_DATE = ?
`

/** Ordered column list for the base table, so step 2 shows it in feed order. */
export const RAW_ALL_COLUMNS = `
SELECT
    COLUMN_NAME      AS column_name,
    DATA_TYPE        AS data_type,
    ORDINAL_POSITION AS ordinal_position,
    COMMENT          AS column_comment
FROM LRI_DEMO.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'LRI_BASE'
  AND TABLE_NAME   = 'LIMITS_INDICATORS_REPORT_DATA'
ORDER BY ORDINAL_POSITION
`

/**
 * The whole source row plus the commentary now hanging off it.
 *
 * LEFT JOIN pinned to one approach so a line with all three generated does not
 * fan out into three table rows.
 */
export const RAW_REPORT_FULL = `
SELECT r.*, c.FINAL_COMMENTARY AS AI_GENERATED_COMMENTARY
FROM LIMITS_INDICATORS_REPORT_DATA r
LEFT JOIN AI_COMMENTARY c
       ON c.RECORD_UNIQUE_IDENTIFIER = r.RECORD_UNIQUE_IDENTIFIER
      AND c.APPROACH = ?
WHERE r.REPORT_AS_OF_COB_DATE = ?
ORDER BY TRY_TO_NUMBER(r.SORT_ORDER) NULLS LAST, r.METRIC_KEY
`

/** The review grid. Display strings come from SQL, not from the UI. */
export const GRID = `
SELECT
    RECORD_UNIQUE_IDENTIFIER    AS record_id,
    METRIC_KEY                  AS metric_key,
    METRIC_NAME                 AS metric_name,
    REPORTING_SCOPE             AS scope,
    DIMENSION_TYPE_CODE         AS dimension_type_code,
    METRIC_TYPE                 AS metric_type,
    DISPLAY_FREQ                AS display_freq,
    STATUS                      AS status,
    SEVERITY_RANK               AS severity_rank,
    BREACH_LEVEL                AS breach_level,
    DATA_QUALITY_FLAG           AS data_quality_flag,
    HAS_DATA                    AS has_data,
    REQUIRES_COMMENTARY         AS requires_commentary,
    REPORTING_UNIT              AS reporting_unit,
    LIMIT_DIRECTION             AS limit_direction,
    VALUE_DISPLAY               AS value_display,
    UTIL_DISPLAY                AS util_display,
    BREACH_DISPLAY              AS breach_display,
    HEADROOM_DISPLAY            AS headroom_display,
    L1_DISPLAY                  AS l1_display,
    L2_DISPLAY                  AS l2_display,
    L3_DISPLAY                  AS l3_display,
    PRIOR_DISPLAY               AS prior_display,
    CHANGE_DISPLAY              AS change_display,
    PRIOR_PERIOD_LABEL          AS prior_period_label,
    NEXT_LEVEL_NAME             AS next_level_name,
    UTILIZATION_PCT             AS utilization_pct,
    TRAJECTORY                  AS trajectory,
    CONSECUTIVE_PERIODS_IN_BREACH AS periods_in_breach,
    STREAK_IS_LEFT_CENSORED     AS streak_left_censored,
    LEVEL_CHANGE                AS level_change,
    TREND_SERIES                AS trend_series,
    FACT_BLOCK                  AS fact_block,
    AI_COMMENTARY               AS ai_commentary,
    FINAL_COMMENTARY            AS final_commentary,
    IS_EDITED                   AS is_edited,
    NEEDS_REVIEW                AS needs_review,
    EDITED_BY                   AS edited_by,
    MODEL_NAME                  AS model_name,
    PROMPT_VERSION              AS prompt_version,
    GENERATION_METHOD           AS generation_method,
    GENERATION_SOURCE           AS generation_source,
    GENERATED_AT                AS generated_at,
    HAS_COMMENTARY              AS has_commentary,
    COMMENTARY_MISSING          AS commentary_missing
FROM V_REPORT_GRID
WHERE REPORT_AS_OF_COB_DATE = ?
ORDER BY SEVERITY_RANK DESC, METRIC_KEY
`

/** Line picker for the comparison step, worst first. */
export const METRIC_LIST = `
SELECT
    RECORD_UNIQUE_IDENTIFIER AS record_id,
    METRIC_KEY      AS metric_key,
    METRIC_NAME     AS metric_name,
    REPORTING_SCOPE AS scope,
    STATUS          AS status,
    SEVERITY_RANK   AS severity_rank,
    LIMIT_DIRECTION AS limit_direction,
    VALUE_DISPLAY   AS value_display,
    REPORTING_UNIT  AS reporting_unit,
    REQUIRES_COMMENTARY AS requires_commentary,
    HAS_DATA        AS has_data
FROM V_REPORT_GRID
WHERE REPORT_AS_OF_COB_DATE = ?
ORDER BY SEVERITY_RANK DESC, METRIC_KEY
`

/**
 * What each approach would be given for one line, before any generation.
 *
 * Lets the comparison step show the three inputs side by side even when nothing
 * has been generated yet -- which is the honest starting point: the difference
 * between the approaches is entirely a difference of input.
 */
export const PROMPT_INPUTS = `
SELECT
    approach        AS approach,
    prompt_input    AS prompt_input,
    prompt          AS prompt,
    input_hash      AS input_hash,
    prompt_version  AS prompt_version,
    has_data        AS has_data,
    requires_commentary AS requires_commentary,
    LENGTH(prompt)  AS prompt_chars
FROM V_PROMPT_ALL
WHERE RECORD_UNIQUE_IDENTIFIER = ?
ORDER BY CASE approach WHEN 'GROUNDED' THEN 1 WHEN 'DIRECT_FULL' THEN 2 ELSE 3 END
`

/** The three approaches side by side for one line, with their checks. */
export const COMPARISON_ONE = `
SELECT
    RECORD_UNIQUE_IDENTIFIER AS record_id,
    METRIC_KEY          AS metric_key,
    METRIC_NAME         AS metric_name,
    REPORTING_SCOPE     AS scope,
    STATUS              AS status,
    TRUE_BREACH_LEVEL   AS true_breach_level,
    LIMIT_DIRECTION     AS limit_direction,
    BAND_MIDPOINT       AS band_midpoint,
    HAS_DATA            AS has_data,
    REQUIRES_COMMENTARY AS requires_commentary,

    GROUNDED_TEXT       AS grounded_text,
    GROUNDED_WORDS      AS grounded_words,
    GROUNDED_INVENTED   AS grounded_invented,
    GROUNDED_INVENTED_TOKENS AS grounded_invented_tokens,
    GROUNDED_WRONG_LEVEL AS grounded_wrong_level,
    GROUNDED_EMPTY      AS grounded_empty,
    GROUNDED_STATED_LEVEL AS grounded_stated_level,
    GROUNDED_BAND_WRONG AS grounded_band_wrong,

    DIRECT_FULL_TEXT    AS direct_full_text,
    DIRECT_FULL_WORDS   AS direct_full_words,
    DIRECT_FULL_INVENTED AS direct_full_invented,
    DIRECT_FULL_INVENTED_TOKENS AS direct_full_invented_tokens,
    DIRECT_FULL_WRONG_LEVEL AS direct_full_wrong_level,
    DIRECT_FULL_EMPTY   AS direct_full_empty,
    DIRECT_FULL_STATED_LEVEL AS direct_full_stated_level,
    DIRECT_FULL_BAND_WRONG AS direct_full_band_wrong,

    DIRECT_RAW_TEXT     AS direct_raw_text,
    DIRECT_RAW_WORDS    AS direct_raw_words,
    DIRECT_RAW_INVENTED AS direct_raw_invented,
    DIRECT_RAW_INVENTED_TOKENS AS direct_raw_invented_tokens,
    DIRECT_RAW_WRONG_LEVEL AS direct_raw_wrong_level,
    DIRECT_RAW_EMPTY    AS direct_raw_empty,
    DIRECT_RAW_STATED_LEVEL AS direct_raw_stated_level,
    DIRECT_RAW_BAND_WRONG AS direct_raw_band_wrong,

    HAS_GROUNDED        AS has_grounded,
    HAS_DIRECT_FULL     AS has_direct_full,
    HAS_DIRECT_RAW      AS has_direct_raw
FROM V_COMMENTARY_COMPARISON
WHERE RECORD_UNIQUE_IDENTIFIER = ?
`

/** The aggregate scorecard: how each approach performed across a COB. */
export const SCORECARD = `
SELECT
    APPROACH                    AS approach,
    LINES_GENERATED             AS lines_generated,
    MODEL_CALLS                 AS model_calls,
    EMPTY_OUTPUT                AS empty_output,
    WRONG_LEVEL                 AS wrong_level,
    LINES_WITH_INVENTED_NUMBERS AS lines_with_invented_numbers,
    INVENTED_NUMBERS_TOTAL      AS invented_numbers_total,
    BAND_WRONG_QUANTITY         AS band_wrong_quantity,
    CAUSAL_CLAIMS               AS causal_claims,
    REASONING_LEAKS             AS reasoning_leaks,
    MARKDOWN                    AS markdown,
    INTERNAL_CODES              AS internal_codes,
    AVG_WORDS                   AS avg_words
FROM V_APPROACH_SUMMARY
WHERE REPORT_AS_OF_COB_DATE = ?
ORDER BY CASE APPROACH WHEN 'GROUNDED' THEN 1 WHEN 'DIRECT_FULL' THEN 2 ELSE 3 END
`

/**
 * Cost preview for one approach.
 *
 * COALESCE around COUNT_IF is not decorative -- COUNT_IF returns NULL, not 0,
 * over an empty input set.
 */
export const PENDING = `
WITH pending AS (
    SELECT p.RECORD_UNIQUE_IDENTIFIER, p.has_data, LENGTH(p.prompt) AS prompt_chars
    FROM V_PROMPT_ALL p
    LEFT JOIN AI_COMMENTARY c
           ON c.RECORD_UNIQUE_IDENTIFIER = p.RECORD_UNIQUE_IDENTIFIER
          AND c.APPROACH                 = p.approach
    WHERE p.approach = ?
      AND p.REPORT_AS_OF_COB_DATE = ?
      AND p.requires_commentary
      AND (   c.RECORD_UNIQUE_IDENTIFIER IS NULL
           OR c.INPUT_HASH     <> p.input_hash
           OR c.PROMPT_VERSION <> p.prompt_version )
)
SELECT
    COUNT(*)                                         AS pending_rows,
    COALESCE(COUNT_IF(has_data), 0)                   AS model_calls,
    COALESCE(COUNT_IF(NOT has_data), 0)               AS static_rows,
    COALESCE(SUM(IFF(has_data, prompt_chars, 0)), 0)  AS prompt_chars
FROM pending
`

/** Lines still pending under one approach, worst first. */
export const PENDING_ROWS = `
SELECT
    p.RECORD_UNIQUE_IDENTIFIER AS record_id,
    p.METRIC_KEY        AS metric_key,
    p.METRIC_NAME       AS metric_name,
    p.status            AS status,
    p.has_data          AS has_data,
    p.reporting_scope   AS scope,
    p.severity_rank     AS severity_rank
FROM V_PROMPT_ALL p
LEFT JOIN AI_COMMENTARY c
       ON c.RECORD_UNIQUE_IDENTIFIER = p.RECORD_UNIQUE_IDENTIFIER
      AND c.APPROACH                 = p.approach
WHERE p.approach = ?
  AND p.REPORT_AS_OF_COB_DATE = ?
  AND p.requires_commentary
  AND (   c.RECORD_UNIQUE_IDENTIFIER IS NULL
       OR c.INPUT_HASH     <> p.input_hash
       OR c.PROMPT_VERSION <> p.prompt_version )
ORDER BY p.severity_rank DESC, p.METRIC_KEY
`

/**
 * Generate. One procedure for every caller.
 *
 * P_RECORD_IDS is a comma-separated list, or NULL for every pending line on the
 * COB, which is how the multi-select batch and the whole-COB run share a path.
 */
export const GENERATE = `
CALL SP_GENERATE_COMMENTARY(TO_DATE(?), ?, ?, TO_BOOLEAN(?), ?)
`

/** Publish an analyst edit against one approach. */
export const SAVE_COMMENTARY = `
UPDATE AI_COMMENTARY
   SET FINAL_COMMENTARY = ?,
       IS_EDITED        = TRUE,
       NEEDS_REVIEW     = FALSE,
       EDITED_BY        = CURRENT_USER(),
       EDITED_AT        = CURRENT_TIMESTAMP()
 WHERE RECORD_UNIQUE_IDENTIFIER = ?
   AND APPROACH = ?
`

/** Drop the edit and fall back to the stored model draft. */
export const REVERT_COMMENTARY = `
UPDATE AI_COMMENTARY
   SET FINAL_COMMENTARY = AI_COMMENTARY,
       IS_EDITED        = FALSE,
       NEEDS_REVIEW     = FALSE,
       EDITED_BY        = NULL,
       EDITED_AT        = NULL
 WHERE RECORD_UNIQUE_IDENTIFIER = ?
   AND APPROACH = ?
`

/*
 * Clear, so the demo can be run again.
 *
 * Deletes rather than blanking: a row with empty text but a matching INPUT_HASH
 * still counts as current to the generator and would not regenerate, leaving the
 * demo with a Generate button that does nothing.
 */
export const CLEAR_COB = `DELETE FROM AI_COMMENTARY WHERE REPORT_AS_OF_COB_DATE = ?`
export const CLEAR_COB_APPROACH = `DELETE FROM AI_COMMENTARY WHERE REPORT_AS_OF_COB_DATE = ? AND APPROACH = ?`
export const CLEAR_ALL = `DELETE FROM AI_COMMENTARY`
