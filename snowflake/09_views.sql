-- =============================================================================
-- LRI Automated Commentary Demo -- 09: Views (grid, scoring, comparison) view for the Streamlit app
-- =============================================================================
-- One row per report line, joining the derived facts to whatever commentary
-- exists for it. This is what the app reads, so the app itself contains almost
-- no SQL logic.
--
-- LEFT JOIN, deliberately: a report line with no commentary yet must still
-- appear in the grid. The analyst needs to see the gap, not have it hidden.
-- =============================================================================

USE SCHEMA LRI_DEMO.LRI_BASE;

CREATE OR REPLACE VIEW V_REPORT_GRID
COMMENT = 'Report lines with derived facts and current commentary, for the Limits & Indicators review app.'
AS
SELECT
    f.RECORD_UNIQUE_IDENTIFIER,
    f.REPORT_AS_OF_COB_DATE,
    f.BATCH_IDENTIFIER,
    f.METRIC_KEY,
    f.METRIC_NAME,
    f.reporting_scope,
    f.DIMENSION_TYPE_CODE,
    f.METRIC_TYPE,
    f.METRIC_SUBTYPE,
    f.DISPLAY_FREQ,
    f.RUN_TYPE,
    f.IS_TEMPORARY_LIMIT,

    f.status,
    f.severity_rank,
    f.BREACH_LEVEL,
    f.data_quality_flag,
    f.has_data,
    f.requires_commentary,

    f.current_value,
    f.REPORTING_UNIT,
    f.utilization_pct,
    f.l1_limit,
    f.l2_limit,
    f.l3_limit,
    f.applied_threshold,
    f.breach_amount,
    f.headroom_to_next_level,
    f.next_level_name,
    f.LIMIT_DIRECTION,

    -- Display strings at each metric's own precision. Formatting stays in SQL so
    -- the grid, the fact block and the commentary all show a figure identically;
    -- a blanket 2 decimals in the UI would render 20 DAYS as "20.00".
    FN_FMT_PRETTY(f.current_value, f.DECIMALS)          AS value_display,
    -- The '%' belongs here, not in the UI. SQL owns every displayed figure
    -- including its unit, so the grid, the detail panel and the fact block
    -- cannot disagree about what 142.7 means.
    FN_FMT_PRETTY(f.utilization_pct, 1) || '%'          AS util_display,
    FN_FMT_PRETTY(f.breach_amount, f.DECIMALS)          AS breach_display,
    FN_FMT_PRETTY(f.headroom_to_next_level, f.DECIMALS) AS headroom_display,
    FN_FMT_PRETTY(f.l1_limit, f.DECIMALS)               AS l1_display,
    FN_FMT_PRETTY(f.l2_limit, f.DECIMALS)               AS l2_display,
    FN_FMT_PRETTY(f.l3_limit, f.DECIMALS)               AS l3_display,
    FN_FMT_PRETTY(f.prior_value, f.DECIMALS)            AS prior_display,
    FN_FMT_PRETTY(f.change_in_units, f.DECIMALS)        AS change_display,
    FN_FMT_PRETTY(f.pct_change, 2)                      AS pct_change_display,

    f.prior_value,
    f.prior_period_label,
    f.change_in_units,
    f.pct_change,
    f.trend_direction,
    f.trajectory,
    f.consecutive_periods_in_breach,
    f.consecutive_periods_at_level,
    f.streak_is_left_censored,
    f.level_change,
    f.trend_series,

    -- Commentary and its provenance.
    c.FACT_BLOCK,
    c.AI_COMMENTARY,
    c.FINAL_COMMENTARY,
    COALESCE(c.IS_EDITED, FALSE)    AS IS_EDITED,
    COALESCE(c.NEEDS_REVIEW, FALSE) AS NEEDS_REVIEW,
    c.EDITED_BY,
    c.EDITED_AT,
    c.MODEL_NAME,
    c.PROMPT_VERSION,
    c.GENERATION_METHOD,
    c.GENERATION_SOURCE,
    c.GENERATED_AT,
    (c.RECORD_UNIQUE_IDENTIFIER IS NOT NULL) AS has_commentary,

    -- A line that should carry commentary but does not. Surfaced in the app so
    -- coverage gaps are visible rather than inferred.
    (f.requires_commentary AND c.RECORD_UNIQUE_IDENTIFIER IS NULL) AS commentary_missing
FROM V_METRIC_FACTS f
-- Pinned to the grounded approach. AI_COMMENTARY is now keyed by
-- (row, approach), so without this predicate a line carrying all three
-- variants would fan out into three grid rows.
LEFT JOIN AI_COMMENTARY c
       ON c.RECORD_UNIQUE_IDENTIFIER = f.RECORD_UNIQUE_IDENTIFIER
      AND c.APPROACH = 'GROUNDED';


-- -----------------------------------------------------------------------------
-- Per-COB summary powering the app's header and freshness banner.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW V_COB_SUMMARY
COMMENT = 'Per-COB counts of breaches, near misses, data gaps and commentary coverage.'
AS
SELECT
    REPORT_AS_OF_COB_DATE,
    BATCH_IDENTIFIER,
    COUNT(*)                                       AS total_metrics,
    COUNT_IF(status = 'BREACH_L3')                 AS breach_l3,
    COUNT_IF(status = 'BREACH_L2')                 AS breach_l2,
    COUNT_IF(status = 'BREACH_L1')                 AS breach_l1,
    COUNT_IF(status = 'NEAR_MISS')                 AS near_miss,
    COUNT_IF(status = 'NO_SOURCE_DATA')            AS no_source_data,
    COUNT_IF(status = 'WITHIN_LIMIT')              AS within_limit,
    COUNT_IF(requires_commentary)                  AS requires_commentary,
    COUNT_IF(has_commentary)                       AS has_commentary,
    COUNT_IF(commentary_missing)                   AS commentary_missing,
    COUNT_IF(IS_EDITED)                            AS analyst_edited,
    COUNT_IF(NEEDS_REVIEW)                         AS needs_review,
    MAX(GENERATED_AT)                              AS last_generated_at,
    MAX(GENERATION_SOURCE)                         AS last_generation_source
FROM V_REPORT_GRID
GROUP BY ALL;


-- =============================================================================
-- V_COMMENTARY_SCORED -- one row per (report line x approach), with mechanical
-- checks of the generated text against the AUTHORITATIVE derived facts.
-- =============================================================================
-- This is what makes "is the derived table necessary?" a measurement rather than
-- an assertion. Every approach is scored against the same facts, including the
-- approaches that were never shown them.
--
-- On the invented-number check, and its limits -- stated plainly because it is
-- the easiest thing here to accidentally rig:
--
--   * Every number in the text is extracted and compared against the set of
--     figures the row legitimately contains: its value, its three limits, the
--     breach amount, utilisation, prior value, change, headroom, band midpoint
--     and deviation, the streak counts, and every point in the trend series.
--
--   * Numbers that are legitimately present for other reasons are added to that
--     set rather than counted as inventions: digits inside the metric name
--     ("3M", "Top 10", "5Y"), the COB day, month and year, the level numbers
--     1-3, and the values 90 and 100 which the instructions themselves name.
--
--   * Comparison is numeric with a tolerance, against values rounded to the
--     metric's own display precision, because the text quotes formatted figures.
--
--   * It is an INDICATOR, not a verdict. A false positive is possible (an
--     unusual but fair paraphrase) and so is a false negative (a wrong number
--     that happens to coincide with another figure on the row). It is reported
--     as a count to be looked at, and the offending tokens are listed so any
--     claim can be checked by eye.
-- =============================================================================
CREATE OR REPLACE VIEW V_COMMENTARY_SCORED
COMMENT = 'Per approach, per report line: the generated commentary with mechanical checks against the authoritative derived facts, including numbers present in the text but not in the facts.'
AS
WITH base AS (
    SELECT
        c.RECORD_UNIQUE_IDENTIFIER,
        c.APPROACH,
        c.REPORT_AS_OF_COB_DATE,
        c.METRIC_KEY,
        c.METRIC_NAME,
        f.reporting_scope,
        c.STATUS,
        f.BREACH_LEVEL           AS true_breach_level,
        f.LIMIT_DIRECTION,
        f.BAND_MIDPOINT,
        f.DECIMALS,
        c.PROMPT_INPUT,
        c.FACT_BLOCK,
        c.AI_COMMENTARY,
        c.FINAL_COMMENTARY,
        c.GENERATION_METHOD,
        c.MODEL_NAME,
        c.PROMPT_VERSION,
        c.GENERATION_SOURCE,
        c.GENERATED_AT,
        c.IS_EDITED,
        c.NEEDS_REVIEW,
        LOWER(COALESCE(c.FINAL_COMMENTARY, '')) AS txt,
        -- Same text with backward-looking level references stripped, used only
        -- for deciding which level the sentence ASSERTS.
        REGEXP_REPLACE(
            LOWER(COALESCE(c.FINAL_COMMENTARY, '')),
            '(de-escalated|escalated|improved|recovered|moved|down|up) from (a |an |the )?level [0-9]( breach)?',
            ' '
        ) AS txt_asserted,
        -- Commas stripped before extraction so "82,607" reads as one number.
        REPLACE(COALESCE(c.FINAL_COMMENTARY, ''), ',', '') AS txt_nocomma,
        -- Every figure the row legitimately contains.
        ARRAY_CAT(
            ARRAY_CONSTRUCT_COMPACT(
                ROUND(f.current_value,            f.DECIMALS),
                ROUND(f.l1_limit,                 f.DECIMALS),
                ROUND(f.l2_limit,                 f.DECIMALS),
                ROUND(f.l3_limit,                 f.DECIMALS),
                ROUND(f.applied_threshold,        f.DECIMALS),
                ROUND(f.breach_amount,            f.DECIMALS),
                ROUND(f.headroom_to_next_level,   f.DECIMALS),
                ROUND(f.prior_value,              f.DECIMALS),
                ROUND(f.change_in_units,          f.DECIMALS),
                ROUND(f.band_midpoint,            f.DECIMALS),
                ROUND(f.deviation_from_midpoint,  f.DECIMALS),
                ROUND(f.prior_deviation_from_midpoint, f.DECIMALS),
                ROUND(f.change_in_deviation,      f.DECIMALS),
                ROUND(f.utilization_pct, 1),
                ROUND(f.pct_change, 2),
                f.consecutive_periods_in_breach,
                f.consecutive_periods_at_level,
                f.cob_periods_available,
                -- Named in the instructions or the level vocabulary itself.
                1, 2, 3, 90, 100,
                DAY(c.REPORT_AS_OF_COB_DATE),
                MONTH(c.REPORT_AS_OF_COB_DATE),
                YEAR(c.REPORT_AS_OF_COB_DATE)
            ),
            ARRAY_CAT(
                -- Digits inside the metric name: "3M", "Top 10", "5Y", "30-Day".
                COALESCE(REGEXP_SUBSTR_ALL(c.METRIC_NAME, '[0-9]+(\.[0-9]+)?'), ARRAY_CONSTRUCT()),
                ARRAY_CAT(
                    -- Scope identifiers, which appear in the scope label the text
                    -- quotes: "(LE 0743, EMEA)", "(LOB 101)".
                    ARRAY_CONSTRUCT_COMPACT(
                        TRY_TO_DOUBLE(r.LEGAL_ENTITY_IDENTIFIER),
                        TRY_TO_DOUBLE(r.LOB_IDENTIFIER)
                    ),
                    -- Every observation the RAW record carries, not just the daily
                    -- points the derived trend_series exposes. The direct
                    -- approaches are shown the weekly and monthly columns too, so
                    -- a figure quoted from them is legitimate.
                    ARRAY_CONSTRUCT_COMPACT(
                        TRY_TO_DOUBLE(r.DAILY_TREND_VALUE1),
                        TRY_TO_DOUBLE(r.DAILY_TREND_VALUE2),
                        TRY_TO_DOUBLE(r.DAILY_TREND_VALUE3),
                        TRY_TO_DOUBLE(r.DAILY_TREND_VALUE4),
                        TRY_TO_DOUBLE(r.DAILY_TREND_VALUE5),
                        TRY_TO_DOUBLE(r.WEEKLY_TREND_VALUE1),
                        TRY_TO_DOUBLE(r.WEEKLY_TREND_VALUE2),
                        TRY_TO_DOUBLE(r.MONTHLY_TREND_VALUE1),
                        TRY_TO_DOUBLE(r.MONTHLY_TREND_VALUE2),
                        TRY_TO_DOUBLE(r.MONTHLY_TREND_VALUE3)
                    )
                )
            )
        ) AS allowed_raw,
        -- Formatted figures used by the band check below.
        FN_FMT_PRETTY(f.current_value, f.DECIMALS)           AS s_value,
        FN_FMT_PRETTY(f.deviation_from_midpoint, f.DECIMALS) AS s_deviation
    FROM AI_COMMENTARY c
    JOIN V_METRIC_FACTS f
      ON f.RECORD_UNIQUE_IDENTIFIER = c.RECORD_UNIQUE_IDENTIFIER
    JOIN LIMITS_INDICATORS_REPORT_DATA r
      ON r.RECORD_UNIQUE_IDENTIFIER = c.RECORD_UNIQUE_IDENTIFIER
),
-- Numbers actually present in the generated text.
tokens AS (
    SELECT
        b.RECORD_UNIQUE_IDENTIFIER,
        b.APPROACH,
        t.value::VARCHAR AS tok_str,
        TRY_TO_DOUBLE(t.value::VARCHAR) AS tok
    FROM base b,
         LATERAL FLATTEN(input => COALESCE(
             REGEXP_SUBSTR_ALL(b.txt_nocomma, '[0-9]+(\.[0-9]+)?'),
             ARRAY_CONSTRUCT()
         )) t
),
-- The allowed set, as numbers.
allowed AS (
    SELECT
        b.RECORD_UNIQUE_IDENTIFIER,
        b.APPROACH,
        TRY_TO_DOUBLE(a.value::VARCHAR) AS val
    FROM base b,
         LATERAL FLATTEN(input => b.allowed_raw) a
),
-- Does each extracted token correspond to a figure the row legitimately holds?
token_match AS (
    SELECT
        tk.RECORD_UNIQUE_IDENTIFIER,
        tk.APPROACH,
        tk.tok_str,
        -- Magnitudes on both sides: the extractor cannot see a minus sign, so a
        -- signed comparison would flag "a decline of 12.51" against a stored
        -- -12.51.
        MAX(IFF(al.val IS NOT NULL
                AND ABS(ABS(al.val) - ABS(tk.tok)) <= GREATEST(0.051, ABS(al.val) * 0.0005),
                1, 0)) AS matched
    FROM tokens tk
    LEFT JOIN allowed al
           ON al.RECORD_UNIQUE_IDENTIFIER = tk.RECORD_UNIQUE_IDENTIFIER
          AND al.APPROACH                 = tk.APPROACH
    WHERE tk.tok IS NOT NULL
    GROUP BY 1, 2, 3
),
unmatched AS (
    SELECT
        RECORD_UNIQUE_IDENTIFIER,
        APPROACH,
        COUNT(*)                            AS invented_count,
        LISTAGG(DISTINCT tok_str, ', ')     AS invented_tokens
    FROM token_match
    WHERE matched = 0
    GROUP BY 1, 2
),
-- The level the text claims, computed once rather than repeated per output column.
levelled AS (
    SELECT
        b.RECORD_UNIQUE_IDENTIFIER,
        b.APPROACH,
        CASE
            -- Only an explicit assertion counts: "a Level 3 breach", "breach of
            -- the L3 threshold", "breach at Level 3". Merely naming a level --
            -- "headroom to L3" -- does not.
            WHEN REGEXP_COUNT(b.txt_asserted, 'level 3 breach|l3 breach|breach of the l3|breach of its l3|breach at level 3|level 3 classification|breach of the level 3') > 0 THEN 'L3'
            WHEN REGEXP_COUNT(b.txt_asserted, 'level 2 breach|l2 breach|breach of the l2|breach of its l2|breach at level 2|level 2 classification|breach of the level 2') > 0 THEN 'L2'
            WHEN REGEXP_COUNT(b.txt_asserted, 'level 1 breach|l1 breach|breach of the l1|breach of its l1|breach at level 1|level 1 classification|breach of the level 1') > 0 THEN 'L1'
            ELSE NULL
        END AS stated_breach_level
    FROM base b
)
SELECT
    b.RECORD_UNIQUE_IDENTIFIER,
    b.APPROACH,
    b.REPORT_AS_OF_COB_DATE,
    b.METRIC_KEY,
    b.METRIC_NAME,
    b.reporting_scope,
    b.STATUS,
    b.true_breach_level,
    b.LIMIT_DIRECTION,
    b.PROMPT_INPUT,
    b.FACT_BLOCK,
    b.AI_COMMENTARY,
    b.FINAL_COMMENTARY,
    b.GENERATION_METHOD,
    b.MODEL_NAME,
    b.PROMPT_VERSION,
    b.GENERATION_SOURCE,
    b.GENERATED_AT,
    b.IS_EDITED,
    b.NEEDS_REVIEW,

    REGEXP_COUNT(b.txt, '[a-z]+') AS word_count,

    -- The model produced nothing at all. Not a template case -- the call was made
    -- and came back empty. Worth its own flag rather than reading as a data gap.
    (b.GENERATION_METHOD = 'AI' AND LENGTH(TRIM(COALESCE(b.FINAL_COMMENTARY, ''))) = 0)
        AS flag_empty_output,

    -- Which level, if any, the text claims.
    lv.stated_breach_level,

    -- Stated a level that is not the level the facts establish. Only meaningful
    -- where the text names a level and the row is actually in breach.
    (   b.true_breach_level IN ('L1','L2','L3')
    AND lv.stated_breach_level IS NOT NULL
    AND lv.stated_breach_level <> b.true_breach_level
    ) AS flag_wrong_level,

    COALESCE(u.invented_count, 0)  AS invented_number_count,
    u.invented_tokens              AS invented_numbers,
    (COALESCE(u.invented_count, 0) > 0) AS flag_invented_number,

    (REGEXP_COUNT(b.txt, 'because|due to|driven by|as a result of|attributable to|owing to|reflect(s|ing) the impact') > 0)
        AS flag_causal_claim,
    (REGEXP_COUNT(b.txt, '(^|[^a-z])wait([^a-z]|$)') > 0
     OR REGEXP_COUNT(b.txt, 'needs correction|correction based on|apolog') > 0
     OR REGEXP_COUNT(b.txt, '(^|[^a-z])let me([^a-z]|$)') > 0
     OR REGEXP_COUNT(b.txt, '(^|[^a-z])i should([^a-z]|$)') > 0
     OR REGEXP_COUNT(b.FINAL_COMMENTARY, '[.][.][.][[:space:]]*$') > 0)
        AS flag_reasoning_leak,
    (REGEXP_COUNT(b.FINAL_COMMENTARY, '[*#`]|^- ') > 0)
        AS flag_markdown,
    (REGEXP_COUNT(b.txt, 'breach_l|no_source_data|current_value|limit_direction|near_miss|within_limit') > 0)
        AS flag_internal_code,

    -- Band metric described against the wrong quantity: the raw value is quoted
    -- and the deviation from the midpoint never is. The resulting sentence
    -- compares a value to a tolerance that does not apply to it.
    (   b.LIMIT_DIRECTION = '+/-'
    AND b.s_deviation IS NOT NULL
    AND LENGTH(TRIM(COALESCE(b.FINAL_COMMENTARY, ''))) > 0
    AND POSITION(b.s_value IN b.FINAL_COMMENTARY) > 0
    AND POSITION(b.s_deviation IN b.FINAL_COMMENTARY) = 0
    ) AS flag_band_wrong_quantity
FROM base b
JOIN levelled lv
       ON lv.RECORD_UNIQUE_IDENTIFIER = b.RECORD_UNIQUE_IDENTIFIER
      AND lv.APPROACH                 = b.APPROACH
LEFT JOIN unmatched u
       ON u.RECORD_UNIQUE_IDENTIFIER = b.RECORD_UNIQUE_IDENTIFIER
      AND u.APPROACH                 = b.APPROACH;


-- -----------------------------------------------------------------------------
-- V_COMMENTARY_COMPARISON -- the three approaches side by side, one row per line.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW V_COMMENTARY_COMPARISON
COMMENT = 'One row per report line with the grounded and both direct approaches side by side, each with its own checks. Drives the comparison step in the app.'
AS
SELECT
    f.RECORD_UNIQUE_IDENTIFIER,
    f.REPORT_AS_OF_COB_DATE,
    f.METRIC_KEY,
    f.METRIC_NAME,
    f.reporting_scope,
    f.STATUS,
    f.BREACH_LEVEL       AS true_breach_level,
    f.LIMIT_DIRECTION,
    f.BAND_MIDPOINT,
    f.requires_commentary,
    f.has_data,

    g.FINAL_COMMENTARY   AS grounded_text,
    g.word_count         AS grounded_words,
    g.invented_number_count AS grounded_invented,
    g.invented_numbers   AS grounded_invented_tokens,
    g.flag_wrong_level   AS grounded_wrong_level,
    g.flag_empty_output  AS grounded_empty,
    g.stated_breach_level AS grounded_stated_level,
    g.flag_band_wrong_quantity AS grounded_band_wrong,

    df.FINAL_COMMENTARY  AS direct_full_text,
    df.word_count        AS direct_full_words,
    df.invented_number_count AS direct_full_invented,
    df.invented_numbers  AS direct_full_invented_tokens,
    df.flag_wrong_level  AS direct_full_wrong_level,
    df.flag_empty_output AS direct_full_empty,
    df.stated_breach_level AS direct_full_stated_level,
    df.flag_band_wrong_quantity AS direct_full_band_wrong,

    dr.FINAL_COMMENTARY  AS direct_raw_text,
    dr.word_count        AS direct_raw_words,
    dr.invented_number_count AS direct_raw_invented,
    dr.invented_numbers  AS direct_raw_invented_tokens,
    dr.flag_wrong_level  AS direct_raw_wrong_level,
    dr.flag_empty_output AS direct_raw_empty,
    dr.stated_breach_level AS direct_raw_stated_level,
    dr.flag_band_wrong_quantity AS direct_raw_band_wrong,

    (g.RECORD_UNIQUE_IDENTIFIER  IS NOT NULL) AS has_grounded,
    (df.RECORD_UNIQUE_IDENTIFIER IS NOT NULL) AS has_direct_full,
    (dr.RECORD_UNIQUE_IDENTIFIER IS NOT NULL) AS has_direct_raw
FROM V_METRIC_FACTS f
LEFT JOIN V_COMMENTARY_SCORED g  ON g.RECORD_UNIQUE_IDENTIFIER  = f.RECORD_UNIQUE_IDENTIFIER AND g.APPROACH  = 'GROUNDED'
LEFT JOIN V_COMMENTARY_SCORED df ON df.RECORD_UNIQUE_IDENTIFIER = f.RECORD_UNIQUE_IDENTIFIER AND df.APPROACH = 'DIRECT_FULL'
LEFT JOIN V_COMMENTARY_SCORED dr ON dr.RECORD_UNIQUE_IDENTIFIER = f.RECORD_UNIQUE_IDENTIFIER AND dr.APPROACH = 'DIRECT_RAW';


-- -----------------------------------------------------------------------------
-- V_APPROACH_SUMMARY -- the scorecard, aggregated per approach per COB.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW V_APPROACH_SUMMARY
COMMENT = 'Aggregate scorecard per approach per COB: how many lines generated, and how many tripped each check.'
AS
SELECT
    REPORT_AS_OF_COB_DATE,
    APPROACH,
    COUNT(*)                                    AS lines_generated,
    COUNT_IF(GENERATION_METHOD = 'AI')          AS model_calls,
    COUNT_IF(flag_empty_output)                 AS empty_output,
    COUNT_IF(flag_wrong_level)                  AS wrong_level,
    COUNT_IF(flag_invented_number)              AS lines_with_invented_numbers,
    SUM(invented_number_count)                  AS invented_numbers_total,
    COUNT_IF(flag_causal_claim)                 AS causal_claims,
    COUNT_IF(flag_reasoning_leak)               AS reasoning_leaks,
    COUNT_IF(flag_markdown)                     AS markdown,
    COUNT_IF(flag_internal_code)                AS internal_codes,
    COUNT_IF(flag_band_wrong_quantity)          AS band_wrong_quantity,
    ROUND(AVG(word_count), 1)                   AS avg_words
FROM V_COMMENTARY_SCORED
GROUP BY ALL;
