-- =============================================================================
-- LRI Automated Commentary Demo -- 04: Fact derivation layer
-- =============================================================================
-- V_METRIC_FACTS turns each raw report row into a set of PRE-COMPUTED FACTS.
--
-- This is the most important object in the demo. Every number that will appear
-- in the commentary -- breach level, breach amount, utilization, period-over-
-- period change, how many consecutive days a metric has been in breach, how much
-- headroom remains to the next threshold -- is computed HERE, in SQL, and can be
-- reconciled against the report by anyone.
--
-- The language model is never asked to calculate, compare, or infer a number.
-- It is handed the arithmetic and asked only to write the sentence. That split
-- is what makes this pattern defensible in a regulated reporting process.
--
-- Note on the DIM_METRIC_DEFINITION join: it supplies BAND_MIDPOINT for the
-- '+/-' (band) metrics only, which the report table does not carry. In a real
-- deployment this comes from the limit configuration master. Every other fact
-- is derived from the report table itself.
-- =============================================================================

USE SCHEMA LRI_DEMO.LRI_BASE;

CREATE OR REPLACE VIEW V_METRIC_FACTS
COMMENT = 'Pre-computed, reconcilable facts per metric per COB. All breach, trend, streak and headroom arithmetic happens here in SQL so the AI commentary layer never performs a calculation.'
AS
WITH cast_layer AS (
    SELECT
        r.RECORD_UNIQUE_IDENTIFIER,
        r.REPORT_AS_OF_COB_DATE,
        r.BATCH_IDENTIFIER,
        r.METRIC_KEY,
        r.METRIC_NAME,
        r.METRIC_IDENTIFIER,
        r.METRIC_TYPE,
        r.METRIC_SUBTYPE,
        r.DIMENSION_TYPE_CODE,
        r.LOB_IDENTIFIER,
        r.LOB_DESCRIPTION,
        r.LEGAL_ENTITY_IDENTIFIER,
        r.LEGAL_ENTITY_DESCRIPTION,
        r.REGION_NAME,
        r.REPORTING_UNIT,
        r.SOURCE_UNIT,
        r.DISPLAY_FREQ,
        r.LIMIT_DIRECTION,
        r.LIMIT_OPERATOR,
        r.IS_TEMPORARY_LIMIT,
        r.RUN_TYPE,
        r.BREACH_LEVEL,
        r.HAS_SOURCE_DATA,
        d.BAND_MIDPOINT,
        d.DECIMALS,

        -- Every numeric column in the source is VARCHAR. TRY_TO_DOUBLE means a
        -- malformed value degrades to NULL and is caught as a data-quality
        -- issue below, rather than failing the batch or -- far worse -- silently
        -- producing commentary about a number that could not be parsed.
        TRY_TO_DOUBLE(r.CURRENT_VALUE)             AS current_value,
        TRY_TO_DOUBLE(r.L1_LIMIT_VALUE)            AS l1_limit,
        TRY_TO_DOUBLE(r.L2_LIMIT_VALUE)            AS l2_limit,
        TRY_TO_DOUBLE(r.L3_LIMIT_VALUE)            AS l3_limit,
        TRY_TO_DOUBLE(r.THRESHOLD)                 AS applied_threshold,
        TRY_TO_DOUBLE(r.CURRENT_UTILIZATION_LEVEL) AS utilization_pct,
        TRY_TO_DOUBLE(r.BREACH_AMOUNT)             AS breach_amount,

        -- Frequency-appropriate comparison point. A weekly metric must be
        -- compared week-on-week, not against yesterday's carried-forward value.
        CASE r.DISPLAY_FREQ
            WHEN 'daily'   THEN TRY_TO_DOUBLE(r.DAILY_TREND_VALUE2)
            WHEN 'weekly'  THEN TRY_TO_DOUBLE(r.WEEKLY_TREND_VALUE2)
            WHEN 'monthly' THEN TRY_TO_DOUBLE(r.MONTHLY_TREND_VALUE2)
        END AS prior_value,
        CASE r.DISPLAY_FREQ
            WHEN 'daily'   THEN r.DAILY_TREND_DATE2
            WHEN 'weekly'  THEN r.WEEKLY_TREND_DATE2
            WHEN 'monthly' THEN r.MONTHLY_TREND_DATE2
        END AS prior_date,
        CASE r.DISPLAY_FREQ
            WHEN 'daily'   THEN 'prior business day'
            WHEN 'weekly'  THEN 'prior week'
            WHEN 'monthly' THEN 'prior month'
        END AS prior_period_label,

        -- Chronological trend series, oldest to newest, at the metric's own
        -- display frequency. Given to the model as evidence, never recomputed.
        CASE r.DISPLAY_FREQ
            WHEN 'daily' THEN CONCAT_WS('; ',
                r.DAILY_TREND_DATE5 || ': ' || r.DAILY_TREND_VALUE5,
                r.DAILY_TREND_DATE4 || ': ' || r.DAILY_TREND_VALUE4,
                r.DAILY_TREND_DATE3 || ': ' || r.DAILY_TREND_VALUE3,
                r.DAILY_TREND_DATE2 || ': ' || r.DAILY_TREND_VALUE2,
                r.DAILY_TREND_DATE1 || ': ' || r.DAILY_TREND_VALUE1)
            WHEN 'weekly' THEN CONCAT_WS('; ',
                r.WEEKLY_TREND_DATE2 || ': ' || r.WEEKLY_TREND_VALUE2,
                r.WEEKLY_TREND_DATE1 || ': ' || r.WEEKLY_TREND_VALUE1)
            WHEN 'monthly' THEN CONCAT_WS('; ',
                r.MONTHLY_TREND_DATE3 || ': ' || r.MONTHLY_TREND_VALUE3,
                r.MONTHLY_TREND_DATE2 || ': ' || r.MONTHLY_TREND_VALUE2,
                r.MONTHLY_TREND_DATE1 || ': ' || r.MONTHLY_TREND_VALUE1)
        END AS trend_series
    FROM LIMITS_INDICATORS_REPORT_DATA r
    LEFT JOIN DIM_METRIC_DEFINITION d USING (METRIC_KEY)
),
-- ---------------------------------------------------------------------------
-- Data quality gate. Everything downstream keys off HAS_DATA, and the
-- commentary layer refuses to narrate a row that fails this gate.
-- ---------------------------------------------------------------------------
quality AS (
    SELECT
        c.*,
        CASE
            WHEN c.HAS_SOURCE_DATA = 'false'  THEN 'NO_SOURCE_DATA'
            WHEN c.current_value IS NULL      THEN 'VALUE_NOT_NUMERIC'
            WHEN c.l1_limit IS NULL           THEN 'LIMIT_NOT_NUMERIC'
            WHEN c.utilization_pct IS NULL    THEN 'UTILIZATION_MISSING'
            ELSE 'OK'
        END AS data_quality_flag
    FROM cast_layer c
),
flagged AS (
    SELECT
        q.*,
        (q.data_quality_flag = 'OK')                                AS has_data,
        (q.BREACH_LEVEL IN ('L1','L2','L3') AND q.data_quality_flag = 'OK') AS is_breached
    FROM quality q
),
-- ---------------------------------------------------------------------------
-- Breach persistence, measured across the COB snapshots already in the table.
-- "Third consecutive day above L2" is a factual claim, so it is counted in SQL.
--
-- Streaks use the standard gaps-and-islands construction: rank the rows overall,
-- rank them again WITHIN the state being tracked, and difference the two. The
-- difference is constant across a run of same-state rows. Ranking within the
-- state matters -- a cumulative counter would let the row that ends a quiet run
-- share an island with the breach run that follows it, inflating every streak
-- by one.
-- ---------------------------------------------------------------------------
prior_level AS (
    SELECT
        f.*,
        LAG(f.BREACH_LEVEL) OVER (
            PARTITION BY f.METRIC_KEY ORDER BY f.REPORT_AS_OF_COB_DATE
        ) AS prior_breach_level,
        ROW_NUMBER() OVER (
            PARTITION BY f.METRIC_KEY ORDER BY f.REPORT_AS_OF_COB_DATE
        ) AS period_seq,
        ROW_NUMBER() OVER (
            PARTITION BY f.METRIC_KEY, f.is_breached ORDER BY f.REPORT_AS_OF_COB_DATE
        ) AS seq_within_breach_state,
        ROW_NUMBER() OVER (
            PARTITION BY f.METRIC_KEY, f.BREACH_LEVEL ORDER BY f.REPORT_AS_OF_COB_DATE
        ) AS seq_within_level,
        COUNT(*) OVER (PARTITION BY f.METRIC_KEY) AS cob_periods_available
    FROM flagged f
),
islands AS (
    SELECT
        p.*,
        p.period_seq - p.seq_within_breach_state AS breach_island,
        p.period_seq - p.seq_within_level        AS level_island
    FROM prior_level p
),
streaks AS (
    SELECT
        i.*,
        IFF(i.is_breached,
            ROW_NUMBER() OVER (PARTITION BY i.METRIC_KEY, i.is_breached, i.breach_island
                               ORDER BY i.REPORT_AS_OF_COB_DATE),
            0) AS consecutive_periods_in_breach,
        ROW_NUMBER() OVER (PARTITION BY i.METRIC_KEY, i.BREACH_LEVEL, i.level_island
                           ORDER BY i.REPORT_AS_OF_COB_DATE) AS consecutive_periods_at_level
    FROM islands i
)
SELECT
    -- ----- identity ---------------------------------------------------------
    RECORD_UNIQUE_IDENTIFIER,
    REPORT_AS_OF_COB_DATE,
    BATCH_IDENTIFIER,
    METRIC_KEY,
    METRIC_NAME,
    METRIC_IDENTIFIER,
    METRIC_TYPE,
    METRIC_SUBTYPE,
    DISPLAY_FREQ,
    RUN_TYPE,
    REPORTING_UNIT,
    IS_TEMPORARY_LIMIT,
    DECIMALS,
    BAND_MIDPOINT,

    -- Human-readable reporting scope, e.g. "Institutional Markets (LOB 101)"
    -- or "GlobalTrust
    -- Securities plc / EMEA". Saves the model from assembling it.
    CASE DIMENSION_TYPE_CODE
        WHEN 'FIRM' THEN 'Firm-wide'
        WHEN 'LOB'  THEN LOB_DESCRIPTION || ' (LOB ' || LOB_IDENTIFIER || ')'
        WHEN 'LE'   THEN LEGAL_ENTITY_DESCRIPTION || ' (LE ' || LEGAL_ENTITY_IDENTIFIER
                         || ', ' || REGION_NAME || ')'
    END AS reporting_scope,
    DIMENSION_TYPE_CODE,

    -- ----- data quality ----------------------------------------------------
    data_quality_flag,
    has_data,

    -- ----- levels ----------------------------------------------------------
    current_value,
    utilization_pct,
    l1_limit,
    l2_limit,
    l3_limit,
    applied_threshold,
    breach_amount,
    LIMIT_DIRECTION,
    LIMIT_OPERATOR,
    BREACH_LEVEL,
    prior_breach_level,

    -- For band ('+/-') metrics the quantity actually tested against L1/L2/L3 is
    -- the distance from the midpoint, NOT the raw value. Without this, a fact
    -- block reads "value 24.8, L2 threshold 27.0, L2 breached", which is
    -- self-contradictory: 24.8 does not exceed 27.0. The deviation (32.8) does.
    CASE WHEN has_data AND LIMIT_DIRECTION = '+/-'
         THEN ABS(current_value - BAND_MIDPOINT) END AS deviation_from_midpoint,
    -- The prior period's deviation is supplied as well, so movement can be
    -- described in deviation terms throughout. Given only the prior raw value,
    -- the model conflates the two and reports a change in value as a change in
    -- deviation.
    CASE WHEN has_data AND LIMIT_DIRECTION = '+/-' AND prior_value IS NOT NULL
         THEN ABS(prior_value - BAND_MIDPOINT) END AS prior_deviation_from_midpoint,
    CASE WHEN has_data AND LIMIT_DIRECTION = '+/-' AND prior_value IS NOT NULL
         THEN ABS(current_value - BAND_MIDPOINT) - ABS(prior_value - BAND_MIDPOINT)
         END AS change_in_deviation,

    -- Overall status. NO_SOURCE_DATA takes precedence over everything: a row
    -- with no value must never be described as being within its limit.
    CASE
        WHEN NOT has_data                       THEN 'NO_SOURCE_DATA'
        WHEN BREACH_LEVEL = 'L3'                THEN 'BREACH_L3'
        WHEN BREACH_LEVEL = 'L2'                THEN 'BREACH_L2'
        WHEN BREACH_LEVEL = 'L1'                THEN 'BREACH_L1'
        WHEN utilization_pct >= 90              THEN 'NEAR_MISS'
        ELSE                                         'WITHIN_LIMIT'
    END AS status,

    CASE
        WHEN NOT has_data          THEN 1
        WHEN BREACH_LEVEL = 'L3'   THEN 5
        WHEN BREACH_LEVEL = 'L2'   THEN 4
        WHEN BREACH_LEVEL = 'L1'   THEN 3
        WHEN utilization_pct >= 90 THEN 2
        ELSE                            0
    END AS severity_rank,

    -- Vocabulary matters to this audience: breaching a Limit is a formal
    -- breach with escalation obligations; crossing an Indicator threshold is a
    -- signal. The model is told which noun to use rather than choosing.
    CASE WHEN METRIC_TYPE = 'Limit'
         THEN 'formal limit breach'
         ELSE 'indicator threshold crossing'
    END AS metric_noun,
    CASE WHEN METRIC_TYPE = 'Limit'
         THEN 'Limit -- crossing constitutes a formal breach requiring escalation'
         ELSE 'Indicator -- crossing is an early-warning signal, not a formal breach'
    END AS metric_type_meaning,

    -- ----- movement --------------------------------------------------------
    prior_value,
    prior_date,
    prior_period_label,
    trend_series,
    CASE WHEN has_data AND prior_value IS NOT NULL
         THEN current_value - prior_value END AS change_in_units,
    CASE WHEN has_data AND prior_value IS NOT NULL AND prior_value <> 0
         THEN (current_value - prior_value) / ABS(prior_value) * 100 END AS pct_change,

    CASE
        WHEN NOT has_data OR prior_value IS NULL         THEN 'UNKNOWN'
        WHEN current_value > prior_value                 THEN 'UP'
        WHEN current_value < prior_value                 THEN 'DOWN'
        ELSE                                                  'FLAT'
    END AS trend_direction,

    -- Direction-aware trajectory. For a floor metric such as LCR, falling is
    -- deteriorating; for a ceiling metric, rising is. For a band metric it is
    -- movement AWAY from the midpoint that is deteriorating. Getting this
    -- wrong would have the commentary call a worsening metric "improving".
    CASE
        WHEN NOT has_data OR prior_value IS NULL THEN 'UNKNOWN'
        WHEN LIMIT_DIRECTION = '+' THEN
            CASE WHEN current_value > prior_value THEN 'DETERIORATING'
                 WHEN current_value < prior_value THEN 'IMPROVING'
                 ELSE 'STABLE' END
        WHEN LIMIT_DIRECTION = '-' THEN
            CASE WHEN current_value < prior_value THEN 'DETERIORATING'
                 WHEN current_value > prior_value THEN 'IMPROVING'
                 ELSE 'STABLE' END
        WHEN LIMIT_DIRECTION = '+/-' THEN
            CASE WHEN ABS(current_value - BAND_MIDPOINT) > ABS(prior_value - BAND_MIDPOINT)
                     THEN 'DETERIORATING'
                 WHEN ABS(current_value - BAND_MIDPOINT) < ABS(prior_value - BAND_MIDPOINT)
                     THEN 'IMPROVING'
                 ELSE 'STABLE' END
        ELSE 'UNKNOWN'
    END AS trajectory,

    -- ----- persistence -----------------------------------------------------
    consecutive_periods_in_breach,
    consecutive_periods_at_level,
    -- The reporting window is finite, so a streak spanning every snapshot we
    -- hold is a lower bound, not an exact count. The prompt is told to say
    -- "at least N" in that case rather than asserting a precise figure.
    (consecutive_periods_in_breach >= period_seq AND consecutive_periods_in_breach > 0)
        AS streak_is_left_censored,
    cob_periods_available,

    (is_breached AND COALESCE(prior_breach_level, 'none') = 'none') AS is_new_breach,

    CASE
        WHEN NOT has_data                                              THEN 'NO_DATA'
        WHEN prior_breach_level IS NULL                                THEN 'NO_PRIOR_PERIOD'
        WHEN BREACH_LEVEL = prior_breach_level                          THEN 'UNCHANGED'
        WHEN prior_breach_level = 'none' AND BREACH_LEVEL <> 'none'     THEN 'NEW_BREACH'
        WHEN BREACH_LEVEL = 'none' AND prior_breach_level <> 'none'     THEN 'CLEARED'
        WHEN BREACH_LEVEL > prior_breach_level                          THEN 'ESCALATED'
        ELSE                                                                'DE_ESCALATED'
    END AS level_change,

    -- ----- headroom --------------------------------------------------------
    -- Distance, in the metric's own unit, to the next more severe threshold.
    -- NULL at L3 because there is no level beyond it.
    CASE
        WHEN NOT has_data THEN NULL
        WHEN BREACH_LEVEL = 'L3' THEN NULL
        ELSE
            CASE LIMIT_DIRECTION
                WHEN '+'   THEN CASE BREACH_LEVEL
                                    WHEN 'none' THEN l1_limit - current_value
                                    WHEN 'L1'   THEN l2_limit - current_value
                                    WHEN 'L2'   THEN l3_limit - current_value END
                WHEN '-'   THEN CASE BREACH_LEVEL
                                    WHEN 'none' THEN current_value - l1_limit
                                    WHEN 'L1'   THEN current_value - l2_limit
                                    WHEN 'L2'   THEN current_value - l3_limit END
                WHEN '+/-' THEN CASE BREACH_LEVEL
                                    WHEN 'none' THEN l1_limit - ABS(current_value - BAND_MIDPOINT)
                                    WHEN 'L1'   THEN l2_limit - ABS(current_value - BAND_MIDPOINT)
                                    WHEN 'L2'   THEN l3_limit - ABS(current_value - BAND_MIDPOINT) END
            END
    END AS headroom_to_next_level,

    CASE
        WHEN NOT has_data THEN NULL
        ELSE CASE BREACH_LEVEL
                 WHEN 'none' THEN 'L1'
                 WHEN 'L1'   THEN 'L2'
                 WHEN 'L2'   THEN 'L3'
                 ELSE NULL
             END
    END AS next_level_name,

    -- ----- commentary routing ----------------------------------------------
    -- Only breaches, near-misses and data gaps are narrated. Metrics sitting
    -- comfortably inside their limits do not need a paragraph, and generating
    -- one for all 200 would be both noisy and needlessly expensive.
    (   NOT has_data
     OR BREACH_LEVEL IN ('L1','L2','L3')
     OR utilization_pct >= 90 ) AS requires_commentary
FROM streaks;
