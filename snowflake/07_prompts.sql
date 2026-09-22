-- =============================================================================
-- LRI Automated Commentary Demo -- 07: Prompts, three approaches
-- =============================================================================
-- V_PROMPT_ALL emits one row per (report row x approach), so the same line can
-- be narrated three different ways and the results compared directly.
--
--   GROUNDED     The derived fact block from V_METRIC_FACTS. Breach level,
--                direction-aware utilisation, streaks, headroom and every figure
--                already computed and formatted in SQL.
--
--   DIRECT_FULL  The raw source record exactly as the feed delivers it, every
--                field as text -- including the BREACH_LEVEL, BREACH_AMOUNT,
--                THRESHOLD and CURRENT_UTILIZATION_LEVEL columns the feed
--                already carries. This is the fair version of "why do we need a
--                derived table at all?", because the model is handed the breach
--                evaluation rather than being asked to infer it.
--
--   DIRECT_RAW   The same record with those four pre-computed columns removed,
--                so the model must establish the breach position itself from the
--                value and the three limits.
--
-- FAIRNESS -- this matters, because the comparison is worthless if it is rigged:
--
--   * The output requirements (rules 1-9, and the length and tone direction for
--     the row's severity) are byte-identical across all three approaches. They
--     are built once, in the `shared` CTE, and referenced three times.
--
--   * Only ONE instruction differs, and it must: the sentence describing what
--     kind of input follows. Telling the model that a raw feed record was
--     "computed in SQL and reconciled" would be false, and would also suppress
--     the very contradictions the comparison exists to surface. Each approach
--     therefore gets a truthful provenance line, and the UI shows all three side
--     by side so the difference is visible rather than buried here.
--
--   * Neither direct variant is crippled beyond the removal named above. No
--     column is withheld from DIRECT_FULL, and the trend columns the feed
--     carries are included in both.
--
-- What the raw record genuinely cannot supply, at any variant:
--   * BAND_MIDPOINT -- absent from the source table entirely, so a band metric's
--     deviation cannot be derived from the row. This is the sharpest gap.
--   * Breach streaks -- the row holds 5 daily, 2 weekly and 3 monthly points, so
--     "at least N consecutive periods" is unknowable from it.
--   * The meaning of the limit direction, and the formatting of each figure.
-- =============================================================================

USE SCHEMA LRI_DEMO.LRI_BASE;

CREATE OR REPLACE VIEW V_PROMPT_ALL
COMMENT = 'One row per report row per approach (GROUNDED, DIRECT_FULL, DIRECT_RAW). Carries the exact model input, a hash of it for idempotent regeneration, and the assembled prompt. Output instructions are identical across approaches; only the input and its provenance line differ.'
AS
WITH fmt AS (
    SELECT
        f.*,
        -- Pre-format every figure at the metric's own precision so the model is
        -- never in a position to choose how to round.
        FN_FMT_PRETTY(f.current_value, f.DECIMALS)            AS s_value,
        FN_FMT_PRETTY(f.l1_limit, f.DECIMALS)                 AS s_l1,
        FN_FMT_PRETTY(f.l2_limit, f.DECIMALS)                 AS s_l2,
        FN_FMT_PRETTY(f.l3_limit, f.DECIMALS)                 AS s_l3,
        FN_FMT_PRETTY(f.applied_threshold, f.DECIMALS)        AS s_threshold,
        FN_FMT_PRETTY(f.breach_amount, f.DECIMALS)            AS s_breach_amount,
        FN_FMT_PRETTY(f.prior_value, f.DECIMALS)              AS s_prior_value,
        FN_FMT_PRETTY(f.change_in_units, f.DECIMALS)          AS s_change,
        FN_FMT_PRETTY(f.headroom_to_next_level, f.DECIMALS)   AS s_headroom,
        FN_FMT_PRETTY(f.utilization_pct, 1)                   AS s_util,
        FN_FMT_PRETTY(f.pct_change, 2)                        AS s_pct_change,
        FN_FMT_PRETTY(f.BAND_MIDPOINT, f.DECIMALS)            AS s_midpoint,
        FN_FMT_PRETTY(f.deviation_from_midpoint, f.DECIMALS)        AS s_deviation,
        FN_FMT_PRETTY(f.prior_deviation_from_midpoint, f.DECIMALS)  AS s_prior_deviation,
        FN_FMT_PRETTY(f.change_in_deviation, f.DECIMALS)            AS s_change_deviation,

        CASE f.LIMIT_DIRECTION
            WHEN '+'   THEN 'upper limit -- the metric breaches when its value rises ABOVE the threshold'
            WHEN '-'   THEN 'lower limit / floor -- the metric breaches when its value falls BELOW the threshold'
            WHEN '+/-' THEN 'tolerance band around a midpoint -- the metric breaches when its value moves too far AWAY from the midpoint in either direction'
        END AS s_direction_meaning,

        -- ------------------------------------------------------------------
        -- Internal enum values are translated into publishable English HERE,
        -- not by the model. Handing the model a token like 'BREACH_L2' invites
        -- it to copy that token into the report -- which is exactly what it did
        -- before this was added.
        -- ------------------------------------------------------------------
        CASE f.status
            WHEN 'BREACH_L3'      THEN 'Level 3 breach (critical -- executive escalation)'
            WHEN 'BREACH_L2'      THEN 'Level 2 breach (material -- management escalation)'
            WHEN 'BREACH_L1'      THEN 'Level 1 breach (early-warning tolerance)'
            WHEN 'NEAR_MISS'      THEN 'Not in breach, but close to the L1 threshold'
            WHEN 'NO_SOURCE_DATA' THEN 'No sourced value available'
            ELSE                       'Within limit'
        END AS s_status_label,

        CASE f.trajectory
            WHEN 'DETERIORATING' THEN 'deteriorating'
            WHEN 'IMPROVING'     THEN 'improving'
            WHEN 'STABLE'        THEN 'broadly stable'
        END AS s_trajectory_label,

        CASE f.trend_direction
            WHEN 'UP'   THEN 'increased'
            WHEN 'DOWN' THEN 'decreased'
            WHEN 'FLAT' THEN 'was unchanged'
        END AS s_trend_label,

        CASE f.level_change
            WHEN 'UNCHANGED'    THEN 'The breach level is unchanged from the prior reporting period.'
            WHEN 'ESCALATED'    THEN 'The breach has escalated from ' || f.prior_breach_level
                                     || ' to ' || f.BREACH_LEVEL || ' since the prior reporting period.'
            WHEN 'DE_ESCALATED' THEN 'The breach has de-escalated from ' || f.prior_breach_level
                                     || ' to ' || f.BREACH_LEVEL || ' since the prior reporting period.'
            WHEN 'NEW_BREACH'   THEN 'This is a new breach: the metric was within its limit in the prior reporting period.'
            WHEN 'CLEARED'      THEN 'The metric has returned within its limit, having been in '
                                     || f.prior_breach_level || ' breach in the prior reporting period.'
        END AS s_level_change_label
    FROM V_METRIC_FACTS f
),
blocks AS (
    SELECT
        fmt.*,
        -- ------------------------------------------------------------------
        -- The fact block. Every line is a value computed in SQL upstream.
        --
        -- ARRAY_CONSTRUCT_COMPACT drops NULL lines, so a fact that does not
        -- apply to this row simply is not asserted. Note that CONCAT_WS cannot
        -- be used here: in Snowflake it returns NULL if ANY argument is NULL,
        -- which would silently blank the entire fact block the moment an
        -- optional line (band midpoint, breach amount, headroom) did not apply.
        -- ------------------------------------------------------------------
        ARRAY_TO_STRING(ARRAY_CONSTRUCT_COMPACT(
            'Metric: '            || METRIC_NAME,
            'Reporting scope: '   || reporting_scope,
            'Metric class: '      || metric_type_meaning,
            'COB date: '          || TO_VARCHAR(REPORT_AS_OF_COB_DATE, 'DD Mon YYYY'),
            'Reporting frequency: ' || DISPLAY_FREQ,
            'Unit of measure: '   || REPORTING_UNIT,
            'Limit type: '        || s_direction_meaning,
            CASE WHEN LIMIT_DIRECTION = '+/-'
                 THEN 'Band midpoint: ' || s_midpoint || ' ' || REPORTING_UNIT END,
            'Status: '            || s_status_label,
            '',
            'Current value: '     || s_value || ' ' || REPORTING_UNIT,

            -- Band metrics are presented in terms of DEVIATION from the
            -- midpoint, because that is the quantity compared against L1/L2/L3.
            -- Presenting the raw value against the tolerances instead makes the
            -- fact block self-contradictory (value 24.8 "exceeding" 27.0), and a
            -- capable model will notice and start reasoning about the
            -- discrepancy inside the published sentence.
            CASE WHEN LIMIT_DIRECTION = '+/-' THEN
                'Deviation from the band midpoint: ' || s_deviation || ' ' || REPORTING_UNIT
                || ' -- this deviation, not the raw value, is what is tested against the tolerances below'
            END,
            CASE WHEN LIMIT_DIRECTION = '+/-'
                 THEN 'L1 tolerance (early warning): ' || s_l1 || ' ' || REPORTING_UNIT || ' either side of the midpoint'
                 ELSE 'L1 threshold (early warning): ' || s_l1 || ' ' || REPORTING_UNIT END,
            CASE WHEN LIMIT_DIRECTION = '+/-'
                 THEN 'L2 tolerance (material, management escalation): ' || s_l2 || ' ' || REPORTING_UNIT || ' either side of the midpoint'
                 ELSE 'L2 threshold (material, management escalation): ' || s_l2 || ' ' || REPORTING_UNIT END,
            CASE WHEN LIMIT_DIRECTION = '+/-'
                 THEN 'L3 tolerance (critical, executive escalation): ' || s_l3 || ' ' || REPORTING_UNIT || ' either side of the midpoint'
                 ELSE 'L3 threshold (critical, executive escalation): ' || s_l3 || ' ' || REPORTING_UNIT END,
            'Utilisation of the L1 ' || IFF(LIMIT_DIRECTION = '+/-', 'tolerance', 'threshold')
                || ': ' || s_util || '% (100% = exactly at the L1 '
                || IFF(LIMIT_DIRECTION = '+/-', 'tolerance', 'threshold') || '; above 100% = breached)',
            CASE
                WHEN BREACH_LEVEL = 'none' THEN NULL
                WHEN LIMIT_DIRECTION = '+/-' THEN
                    'Tolerance breached: ' || BREACH_LEVEL || ' -- the deviation of ' || s_deviation
                    || ' ' || REPORTING_UNIT || ' exceeds the ' || BREACH_LEVEL || ' tolerance of '
                    || s_threshold || ' ' || REPORTING_UNIT
                ELSE 'Threshold breached: ' || BREACH_LEVEL || ' at ' || s_threshold || ' ' || REPORTING_UNIT
            END,
            CASE WHEN breach_amount IS NOT NULL
                 THEN IFF(LIMIT_DIRECTION = '+/-',
                          'Amount by which the deviation exceeds that tolerance: ',
                          'Amount beyond the breached threshold: ')
                      || s_breach_amount || ' ' || REPORTING_UNIT END,
            CASE WHEN headroom_to_next_level IS NOT NULL AND next_level_name IS NOT NULL
                 THEN 'Remaining headroom before ' || next_level_name || ': ' || s_headroom
                      || ' ' || REPORTING_UNIT
                      || IFF(LIMIT_DIRECTION = '+/-', ' of further deviation', '') END,
            '',
            CASE WHEN prior_value IS NOT NULL
                 THEN IFF(LIMIT_DIRECTION = '+/-', 'Raw value at the ', 'Value at the ')
                      || prior_period_label || ' (' || TO_VARCHAR(prior_date, 'DD Mon YYYY') || '): '
                      || s_prior_value || ' ' || REPORTING_UNIT END,
            CASE WHEN LIMIT_DIRECTION = '+/-' AND prior_deviation_from_midpoint IS NOT NULL
                 THEN 'Deviation from the midpoint at the ' || prior_period_label || ': '
                      || s_prior_deviation || ' ' || REPORTING_UNIT END,
            CASE WHEN LIMIT_DIRECTION = '+/-' AND change_in_deviation IS NOT NULL
                 THEN 'Change in that deviation since then: ' || s_change_deviation || ' '
                      || REPORTING_UNIT
                      || ' -- describe movement for this metric in terms of the deviation, not the raw value'
                 END,
            -- A zero change is stated as "unchanged" rather than "0 DAYS
            -- (0.00% in relative terms)", which reads poorly in published prose.
            CASE
                WHEN change_in_units IS NULL      THEN NULL
                WHEN change_in_units = 0          THEN 'Change since then: unchanged'
                ELSE 'Change since then: ' || s_change || ' ' || REPORTING_UNIT
                     || COALESCE(' (' || s_pct_change || '% in relative terms)', '')
            END,
            CASE WHEN s_trajectory_label IS NOT NULL AND s_trend_label IS NOT NULL
                 THEN 'The value ' || s_trend_label
                      || ' versus the ' || prior_period_label
                      || '; for this metric that means the position is ' || s_trajectory_label || '.' END,
            CASE WHEN consecutive_periods_in_breach > 0
                 THEN 'Consecutive reporting periods in breach: '
                      || IFF(streak_is_left_censored, 'at least ', '')
                      || TO_VARCHAR(consecutive_periods_in_breach)
                      || IFF(streak_is_left_censored,
                             ' (the reporting window held only ' || TO_VARCHAR(cob_periods_available)
                             || ' periods, so this is a minimum, not an exact count)', '') END,
            CASE WHEN consecutive_periods_at_level > 1 AND BREACH_LEVEL <> 'none'
                 THEN 'Consecutive reporting periods at the current level: '
                      || TO_VARCHAR(consecutive_periods_at_level) END,
            s_level_change_label,
            CASE WHEN trend_series IS NOT NULL
                 THEN 'Recent observations (oldest to newest): ' || trend_series END,
            CASE WHEN IS_TEMPORARY_LIMIT = 'true'
                 THEN 'Note: this limit is a temporary, time-bound override rather than the standing limit.' END
        ), CHR(10)) AS fact_block
    FROM fmt
)
,
-- ---------------------------------------------------------------------------
-- Everything shared between the three approaches, built once.
--
-- The instruction text lives here rather than in each branch so it cannot drift
-- between approaches. If it drifts, the comparison stops measuring the input and
-- starts measuring the instructions.
-- ---------------------------------------------------------------------------
shared AS (
    SELECT
        b.*,

        -- Raw source record, rendered as labelled text. COALESCE to '(null)'
        -- rather than dropping the line, so an absent value is visible to the
        -- model as an absence instead of silently disappearing.
        ARRAY_TO_STRING(ARRAY_CONSTRUCT(
            'METRIC_NAME = '               || COALESCE(r.METRIC_NAME, '(null)'),
            'METRIC_IDENTIFIER = '         || COALESCE(r.METRIC_IDENTIFIER, '(null)'),
            'METRIC_TYPE = '               || COALESCE(r.METRIC_TYPE, '(null)'),
            'METRIC_SUBTYPE = '            || COALESCE(r.METRIC_SUBTYPE, '(null)'),
            'DIMENSION_TYPE_CODE = '       || COALESCE(r.DIMENSION_TYPE_CODE, '(null)'),
            'LOB_IDENTIFIER = '            || COALESCE(r.LOB_IDENTIFIER, '(null)'),
            'LOB_DESCRIPTION = '           || COALESCE(r.LOB_DESCRIPTION, '(null)'),
            'LEGAL_ENTITY_IDENTIFIER = '   || COALESCE(r.LEGAL_ENTITY_IDENTIFIER, '(null)'),
            'LEGAL_ENTITY_DESCRIPTION = '  || COALESCE(r.LEGAL_ENTITY_DESCRIPTION, '(null)'),
            'REGION_NAME = '               || COALESCE(r.REGION_NAME, '(null)'),
            'REPORT_AS_OF_COB_DATE = '     || COALESCE(TO_VARCHAR(r.REPORT_AS_OF_COB_DATE), '(null)'),
            'METRIC_COB_DATE = '           || COALESCE(TO_VARCHAR(r.METRIC_COB_DATE), '(null)'),
            'SOURCE_FREQUENCY = '          || COALESCE(r.SOURCE_FREQUENCY, '(null)'),
            'DISPLAY_FREQ = '              || COALESCE(r.DISPLAY_FREQ, '(null)'),
            'LOOKBACK_PERIOD = '           || COALESCE(r.LOOKBACK_PERIOD, '(null)'),
            'SOURCE_UNIT = '               || COALESCE(r.SOURCE_UNIT, '(null)'),
            'REPORTING_UNIT = '            || COALESCE(r.REPORTING_UNIT, '(null)'),
            'CURRENT_VALUE = '             || COALESCE(r.CURRENT_VALUE, '(null)'),
            'L1_LIMIT_VALUE = '            || COALESCE(r.L1_LIMIT_VALUE, '(null)'),
            'L2_LIMIT_VALUE = '            || COALESCE(r.L2_LIMIT_VALUE, '(null)'),
            'L3_LIMIT_VALUE = '            || COALESCE(r.L3_LIMIT_VALUE, '(null)'),
            'LIMIT_OPERATOR = '            || COALESCE(r.LIMIT_OPERATOR, '(null)'),
            'LIMIT_DIRECTION = '           || COALESCE(r.LIMIT_DIRECTION, '(null)'),
            'IS_TEMPORARY_LIMIT = '        || COALESCE(r.IS_TEMPORARY_LIMIT, '(null)'),
            'HAS_SOURCE_DATA = '           || COALESCE(r.HAS_SOURCE_DATA, '(null)'),
            'DAILY_TREND_DATE1 = '         || COALESCE(TO_VARCHAR(r.DAILY_TREND_DATE1), '(null)'),
            'DAILY_TREND_VALUE1 = '        || COALESCE(r.DAILY_TREND_VALUE1, '(null)'),
            'DAILY_TREND_DATE2 = '         || COALESCE(TO_VARCHAR(r.DAILY_TREND_DATE2), '(null)'),
            'DAILY_TREND_VALUE2 = '        || COALESCE(r.DAILY_TREND_VALUE2, '(null)'),
            'DAILY_TREND_DATE3 = '         || COALESCE(TO_VARCHAR(r.DAILY_TREND_DATE3), '(null)'),
            'DAILY_TREND_VALUE3 = '        || COALESCE(r.DAILY_TREND_VALUE3, '(null)'),
            'DAILY_TREND_DATE4 = '         || COALESCE(TO_VARCHAR(r.DAILY_TREND_DATE4), '(null)'),
            'DAILY_TREND_VALUE4 = '        || COALESCE(r.DAILY_TREND_VALUE4, '(null)'),
            'DAILY_TREND_DATE5 = '         || COALESCE(TO_VARCHAR(r.DAILY_TREND_DATE5), '(null)'),
            'DAILY_TREND_VALUE5 = '        || COALESCE(r.DAILY_TREND_VALUE5, '(null)'),
            'WEEKLY_TREND_DATE1 = '        || COALESCE(TO_VARCHAR(r.WEEKLY_TREND_DATE1), '(null)'),
            'WEEKLY_TREND_VALUE1 = '       || COALESCE(r.WEEKLY_TREND_VALUE1, '(null)'),
            'WEEKLY_TREND_DATE2 = '        || COALESCE(TO_VARCHAR(r.WEEKLY_TREND_DATE2), '(null)'),
            'WEEKLY_TREND_VALUE2 = '       || COALESCE(r.WEEKLY_TREND_VALUE2, '(null)'),
            'MONTHLY_TREND_DATE1 = '       || COALESCE(TO_VARCHAR(r.MONTHLY_TREND_DATE1), '(null)'),
            'MONTHLY_TREND_VALUE1 = '      || COALESCE(r.MONTHLY_TREND_VALUE1, '(null)'),
            'MONTHLY_TREND_DATE2 = '       || COALESCE(TO_VARCHAR(r.MONTHLY_TREND_DATE2), '(null)'),
            'MONTHLY_TREND_VALUE2 = '      || COALESCE(r.MONTHLY_TREND_VALUE2, '(null)'),
            'MONTHLY_TREND_DATE3 = '       || COALESCE(TO_VARCHAR(r.MONTHLY_TREND_DATE3), '(null)'),
            'MONTHLY_TREND_VALUE3 = '      || COALESCE(r.MONTHLY_TREND_VALUE3, '(null)')
        ), CHR(10)) AS input_common,

        -- The four columns the feed already carries that amount to a breach
        -- evaluation. Present in DIRECT_FULL, withheld from DIRECT_RAW.
        ARRAY_TO_STRING(ARRAY_CONSTRUCT(
            'THRESHOLD = '                 || COALESCE(r.THRESHOLD, '(null)'),
            'BREACH_LEVEL = '              || COALESCE(r.BREACH_LEVEL, '(null)'),
            'BREACH_AMOUNT = '             || COALESCE(r.BREACH_AMOUNT, '(null)'),
            'CURRENT_UTILIZATION_LEVEL = ' || COALESCE(r.CURRENT_UTILIZATION_LEVEL, '(null)')
        ), CHR(10)) AS input_precomputed,

        'You are a liquidity risk reporting analyst at a global bank, drafting pre-commentary '
        || 'for the daily Limits and Indicators report. Your draft is reviewed and signed off by '
        || 'a human analyst before publication.' AS preamble,

        -- ------------------------------------------------------------------
        -- Output requirements. IDENTICAL for every approach.
        -- ------------------------------------------------------------------
        'Write commentary for the metric below using ONLY the information provided.'
        || CHR(10) || CHR(10) ||
        'RULES -- these are not stylistic preferences:'                                        || CHR(10) ||
        '1. Do NOT state, imply, or speculate about WHY the metric moved. No cause is given, '
        || 'so any explanation you supply would be invented. Describe what the position is and '
        || 'how it has changed, never why.'                                                    || CHR(10) ||
        '2. Do NOT introduce any figure, date, threshold or percentage that is not stated '
        || 'below.'                                                                            || CHR(10) ||
        '3. Refer to the event using this exact terminology: ' || b.metric_noun || '.'          || CHR(10) ||
        '4. Do NOT recommend specific remedial actions, and do NOT name any team, system, '
        || 'desk, client or counterparty.'                                                     || CHR(10) ||
        '5. Write in formal third person. No first person, no addressing the reader, and no '
        || 'hedging filler such as "it appears that" or "it would seem".'                      || CHR(10) ||
        '6. Do NOT use internal system codes, field names or enumerated values in the text '
        || '(for example BREACH_L2, DETERIORATING, CURRENT_VALUE, NO_SOURCE_DATA). Refer to '
        || 'levels in natural language, such as "a Level 2 breach", "the L2 threshold".'       || CHR(10) ||
        '7. Where a figure below is qualified as "at least", you MUST preserve that '
        || 'qualifier. Such a count is a minimum and stating it as exact would overstate what '
        || 'is known.'                                                                        || CHR(10) ||
        '8. Output plain prose only. No markdown, no bullet points, no headings, no preamble, '
        || 'and no closing summary. Do not restate the metric name as a title.'                 || CHR(10) ||
        '9. Output ONLY the finished commentary. Never include reasoning, working, '
        || 'self-correction or asides -- no "wait", no "this needs correction", no restarting '
        || 'the paragraph, no trailing ellipsis. Write one final version and stop.'
        || CHR(10) || CHR(10) ||
        'REQUIRED LENGTH AND TONE FOR THIS ROW:' || CHR(10) ||
        CASE b.status
            WHEN 'BREACH_L3' THEN
                'This is a Level 3 breach: the most severe classification, carrying senior '
                || 'management and executive escalation obligations. Write three to four '
                || 'sentences. State the breach and the amount by which the threshold is '
                || 'exceeded; state how long the position has persisted and whether it has '
                || 'worsened relative to the prior period; state the direction of travel; and '
                || 'close by noting that escalation to executive level is required. The tone '
                || 'is grave and factual, not alarmed.'
            WHEN 'BREACH_L2' THEN
                'This is a Level 2 breach: material, requiring management escalation. Write '
                || 'two to three sentences. State the breach and the amount by which the '
                || 'threshold is exceeded, note its persistence and direction of travel, and '
                || 'note that management escalation applies.'
            WHEN 'BREACH_L1' THEN
                'This is a Level 1 breach: the early-warning tolerance, the least severe level. '
                || 'Write ONE measured sentence stating the position, the amount by which the '
                || 'L1 threshold is exceeded, and the direction of travel. Do not escalate the '
                || 'language beyond what a Level 1 warrants.'
            WHEN 'NEAR_MISS' THEN
                'This metric is NOT in breach, but its utilisation is at or above 90% of the L1 '
                || 'threshold. Write ONE sentence noting how close the metric is to its limit '
                || 'and its direction of travel. You must not describe this as a breach, and '
                || 'you must not imply that any escalation obligation has been triggered.'
            ELSE
                'This metric is within its limit. Write ONE brief sentence confirming the '
                || 'position and its direction of travel.'
        END AS instructions,

        -- Fixed sentence for rows with no sourced value. Identical whichever
        -- approach is selected -- there is nothing to narrate, so no approach
        -- sends these to the model and none is advantaged by them.
        CASE WHEN NOT b.has_data THEN
            'No sourced value was available for this metric as at COB '
            || TO_VARCHAR(b.REPORT_AS_OF_COB_DATE, 'DD Mon YYYY')
            || CASE b.data_quality_flag
                   WHEN 'NO_SOURCE_DATA'      THEN ' (the upstream feed did not supply a value)'
                   WHEN 'VALUE_NOT_NUMERIC'   THEN ' (the supplied value could not be interpreted as a number)'
                   WHEN 'LIMIT_NOT_NUMERIC'   THEN ' (the limit configuration could not be interpreted as a number)'
                   WHEN 'UTILIZATION_MISSING' THEN ' (utilisation could not be evaluated)'
                   ELSE '' END
            || '. Breach status could not be evaluated and no commentary has been generated. '
            || 'The upstream feed should be confirmed before this line is relied upon.'
        END AS static_commentary
    FROM blocks b
    JOIN LIMITS_INDICATORS_REPORT_DATA r
      ON r.RECORD_UNIQUE_IDENTIFIER = b.RECORD_UNIQUE_IDENTIFIER
)
-- ---------------------------------------------------------------------------
-- One row per approach. Note the only differences between the three branches:
-- the approach label, the provenance sentence, and the input block itself.
-- ---------------------------------------------------------------------------
SELECT
    RECORD_UNIQUE_IDENTIFIER, REPORT_AS_OF_COB_DATE, BATCH_IDENTIFIER, METRIC_KEY,
    METRIC_NAME, reporting_scope, METRIC_TYPE, status, severity_rank,
    data_quality_flag, has_data, requires_commentary, fact_block, static_commentary,
    'GROUNDED'  AS approach,
    'v2.0'      AS prompt_version,
    fact_block  AS prompt_input,
    SHA2(fact_block) AS input_hash,
    CONCAT_WS(CHR(10) || CHR(10),
        preamble,
        instructions,
        'The facts below were computed in SQL from the source record and reconciled '
        || 'before reaching you. Treat them as authoritative and internally consistent. '
        || 'Every figure is already in its correct precision -- reproduce it exactly and do '
        || 'not re-derive, re-round or reconcile anything.',
        'FACTS:' || CHR(10) || fact_block,
        'Write the commentary now. Output only the commentary text.'
    ) AS prompt
FROM shared

UNION ALL

SELECT
    RECORD_UNIQUE_IDENTIFIER, REPORT_AS_OF_COB_DATE, BATCH_IDENTIFIER, METRIC_KEY,
    METRIC_NAME, reporting_scope, METRIC_TYPE, status, severity_rank,
    data_quality_flag, has_data, requires_commentary, fact_block, static_commentary,
    'DIRECT_FULL' AS approach,
    'v2.0'        AS prompt_version,
    input_common || CHR(10) || input_precomputed AS prompt_input,
    SHA2(input_common || CHR(10) || input_precomputed) AS input_hash,
    CONCAT_WS(CHR(10) || CHR(10),
        preamble,
        instructions,
        'The block below is the raw source record for this line, exactly as the reporting '
        || 'feed delivers it. Every field arrives as text. Some fields already carry a breach '
        || 'evaluation; others you will need to interpret for yourself.',
        'SOURCE RECORD:' || CHR(10) || input_common || CHR(10) || input_precomputed,
        'Write the commentary now. Output only the commentary text.'
    ) AS prompt
FROM shared

UNION ALL

SELECT
    RECORD_UNIQUE_IDENTIFIER, REPORT_AS_OF_COB_DATE, BATCH_IDENTIFIER, METRIC_KEY,
    METRIC_NAME, reporting_scope, METRIC_TYPE, status, severity_rank,
    data_quality_flag, has_data, requires_commentary, fact_block, static_commentary,
    'DIRECT_RAW' AS approach,
    'v2.0'       AS prompt_version,
    input_common AS prompt_input,
    SHA2(input_common) AS input_hash,
    CONCAT_WS(CHR(10) || CHR(10),
        preamble,
        instructions,
        'The block below is the raw source record for this line as the reporting feed delivers '
        || 'it, with the pre-computed breach evaluation fields removed. Every field arrives as '
        || 'text. Establish the breach position yourself from the value and the limits.',
        'SOURCE RECORD:' || CHR(10) || input_common,
        'Write the commentary now. Output only the commentary text.'
    ) AS prompt
FROM shared;
