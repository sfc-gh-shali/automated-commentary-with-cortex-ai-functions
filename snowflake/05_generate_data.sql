-- =============================================================================
-- LRI Automated Commentary Demo -- 03c: Generate synthetic COB batches
-- =============================================================================
-- Produces 20 COB batches x 200 metrics = 4,000 report rows.
--
-- Values come from a per-metric random walk in UTILIZATION space (100 = at the
-- L1 threshold), then converted back into natural units using the metric's
-- limit direction. Walking in utilization space is what makes breach streaks,
-- escalations, and recoveries coherent -- if values were drawn independently
-- per row, "third consecutive day above L2" would be a lie.
--
-- The walk runs for 65 business days but only the last 5 are emitted as report
-- rows. The earlier 45 days exist so that weekly (t-5) and monthly (t-21, t-42)
-- trend columns have genuine history behind them.
--
-- Everything is deterministic (FN_URAND, not RANDOM), so rebuilding the demo
-- reproduces byte-identical data.
-- =============================================================================

USE SCHEMA LRI_DEMO.LRI_BASE;

-- Idempotence. Without this the INSERT below appends, so re-running this script
-- alone silently doubles the data rather than reproducing it.
TRUNCATE TABLE IF EXISTS LIMITS_INDICATORS_REPORT_DATA;

INSERT INTO LIMITS_INDICATORS_REPORT_DATA (
    DIMENSION_TYPE_CODE, LOB_IDENTIFIER, LOB_DESCRIPTION,
    LEGAL_ENTITY_IDENTIFIER, LEGAL_ENTITY_DESCRIPTION,
    METRIC_NAME, SOURCE_FREQUENCY, SOURCE_UNIT, METRIC_TYPE, METRIC_COB_DATE,
    CURRENT_UTILIZATION_LEVEL, CURRENT_VALUE,
    L1_LIMIT_VALUE, L2_LIMIT_VALUE, L3_LIMIT_VALUE, THRESHOLD,
    LIMIT_OPERATOR, LIMIT_DIRECTION, METRIC_IDENTIFIER, LOOKBACK_PERIOD,
    METRIC_SUBTYPE, REPORTING_UNIT, METRIC_SOURCE, REGION_NAME, REPORTING_DATES,
    BREACH_LEVEL, BREACH_AMOUNT, SORT_ORDER,
    DAILY_TREND_DATE1, DAILY_TREND_VALUE1, DAILY_TREND_DATE2, DAILY_TREND_VALUE2,
    DAILY_TREND_DATE3, DAILY_TREND_VALUE3, DAILY_TREND_DATE4, DAILY_TREND_VALUE4,
    DAILY_TREND_DATE5, DAILY_TREND_VALUE5,
    WEEKLY_TREND_DATE1, WEEKLY_TREND_VALUE1, WEEKLY_TREND_DATE2, WEEKLY_TREND_VALUE2,
    MONTHLY_TREND_DATE1, MONTHLY_TREND_VALUE1, MONTHLY_TREND_DATE2, MONTHLY_TREND_VALUE2,
    MONTHLY_TREND_DATE3, MONTHLY_TREND_VALUE3,
    CREATED_BY_USER_IDENTIFIER, CREATED_ON_DATE, METRIC_KEY,
    IS_TEMPORARY_LIMIT, HAS_SOURCE_DATA, DISPLAY_FREQ, REPORT_AS_OF_COB_DATE,
    RUN_TYPE, CONTEXT_NAME, USER_GROUP, LOAD_ID, BATCH_IDENTIFIER
)
WITH
-- ---------------------------------------------------------------------------
-- Business-day calendar: 65 weekdays ending on the anchor COB date.
-- day_idx 1 = oldest, day_idx 65 = final/most recent COB.
-- ---------------------------------------------------------------------------
calendar_days AS (
    SELECT DATEADD(day, -seq4()::INT, DATE '2026-09-08') AS d
    FROM TABLE(GENERATOR(ROWCOUNT => 130))
),
business_days AS (
    SELECT d, ROW_NUMBER() OVER (ORDER BY d DESC) AS rn_desc
    FROM calendar_days
    WHERE DAYOFWEEKISO(d) <= 5          -- Monday-Friday
),
walk_days AS (
    SELECT d AS cob_date, 66 - rn_desc AS day_idx
    FROM business_days
    WHERE rn_desc <= 65
),
-- ---------------------------------------------------------------------------
-- The walk itself. Drift is applied only across the emitted 20-day window
-- (day_idx 61-65) so planted narratives play out inside the reported period
-- rather than being stretched across the full 65-day history.
-- ---------------------------------------------------------------------------
walk AS (
    SELECT
        m.metric_key,
        w.cob_date,
        w.day_idx,
        m.decimals,
        m.limit_direction,
        m.l1_limit,
        m.band_midpoint,
        m.band_side,
        m.is_missing_final,
        GREATEST(5.0,
            CASE
                -- Clean for most of the window, then a sudden jump into L3.
                WHEN m.scenario = 'NEW_L3'
                    THEN IFF(w.day_idx >= 64, m.util_jump, 70.0)
                ELSE m.util_start
                     + (m.util_end - m.util_start)
                       * GREATEST(0, (w.day_idx - 61) / 4.0)
            END
            + (FN_URAND(m.metric_key, w.day_idx) - 0.5) * 2 * m.noise_amp
        ) AS util
    FROM DIM_METRIC_DEFINITION m
    CROSS JOIN walk_days w
),
-- ---------------------------------------------------------------------------
-- Convert utilization back into natural units, honouring limit direction.
--   '+'   value rises into breach          -> value = L1 * u/100
--   '-'   value falls into breach          -> value = L1 * 100/u
--   '+/-' distance from midpoint breaches  -> value = mid +/- L1 * u/100
--
-- The value is ROUNDED TO DISPLAY PRECISION HERE, before breach evaluation, so
-- that the value shown on the report, its utilization, its breach level and its
-- breach amount are all derived from the same number. Evaluating breaches on
-- unrounded values would let a metric display '27' against an L2 limit of '27'
-- while being reported as an L1 breach.
--
-- The final COB value is suppressed for metrics flagged as an upstream gap.
-- ---------------------------------------------------------------------------
valued AS (
    SELECT
        w.*,
        ROUND(
            CASE
                WHEN w.is_missing_final AND w.day_idx = 65 THEN NULL
                WHEN w.limit_direction = '+'   THEN w.l1_limit * w.util / 100
                WHEN w.limit_direction = '-'   THEN w.l1_limit * 100 / w.util
                WHEN w.limit_direction = '+/-' THEN w.band_midpoint + w.band_side * w.l1_limit * w.util / 100
            END,
            w.decimals
        ) AS raw_value
    FROM walk w
),
-- ---------------------------------------------------------------------------
-- Lagged observations feeding the daily / weekly / monthly trend columns.
--   daily   t, t-1 .. t-4
--   weekly  t, t-5      (one business week)
--   monthly t, t-21, t-42 (approx. month-ends in business days)
-- ---------------------------------------------------------------------------
lagged AS (
    SELECT
        v.*,
        LAG(raw_value, 1)  OVER (PARTITION BY metric_key ORDER BY day_idx) AS v_l1,
        LAG(raw_value, 2)  OVER (PARTITION BY metric_key ORDER BY day_idx) AS v_l2,
        LAG(raw_value, 3)  OVER (PARTITION BY metric_key ORDER BY day_idx) AS v_l3,
        LAG(raw_value, 4)  OVER (PARTITION BY metric_key ORDER BY day_idx) AS v_l4,
        LAG(raw_value, 5)  OVER (PARTITION BY metric_key ORDER BY day_idx) AS v_w1,
        LAG(raw_value, 21) OVER (PARTITION BY metric_key ORDER BY day_idx) AS v_m1,
        LAG(raw_value, 42) OVER (PARTITION BY metric_key ORDER BY day_idx) AS v_m2,
        LAG(cob_date, 1)   OVER (PARTITION BY metric_key ORDER BY day_idx) AS d_l1,
        LAG(cob_date, 2)   OVER (PARTITION BY metric_key ORDER BY day_idx) AS d_l2,
        LAG(cob_date, 3)   OVER (PARTITION BY metric_key ORDER BY day_idx) AS d_l3,
        LAG(cob_date, 4)   OVER (PARTITION BY metric_key ORDER BY day_idx) AS d_l4,
        LAG(cob_date, 5)   OVER (PARTITION BY metric_key ORDER BY day_idx) AS d_w1,
        LAG(cob_date, 21)  OVER (PARTITION BY metric_key ORDER BY day_idx) AS d_m1,
        LAG(cob_date, 42)  OVER (PARTITION BY metric_key ORDER BY day_idx) AS d_m2
    FROM valued v
),
-- ---------------------------------------------------------------------------
-- Emit only the reported window, and evaluate breach state using the shared
-- UDFs so the stored report values and the derived fact block cannot diverge.
-- ---------------------------------------------------------------------------
emitted AS (
    SELECT
        l.*,
        d.metric_name, d.metric_type, d.metric_subtype, d.source_unit, d.reporting_unit,
        d.display_freq, d.source_frequency, d.lookback_period,
        d.dimension_type_code, d.lob_identifier, d.lob_description,
        d.legal_entity_identifier, d.legal_entity_description, d.region_name,
        d.metric_identifier, d.metric_source, d.reporting_dates, d.context_name,
        d.run_type, d.is_temporary_limit, d.user_group, d.sort_order,
        d.l2_limit, d.l3_limit,
        FN_BREACH_LEVEL(l.raw_value, d.l1_limit, d.l2_limit, d.l3_limit,
                        d.limit_direction, d.band_midpoint)                AS breach_level,
        FN_UTILIZATION(l.raw_value, d.l1_limit, d.limit_direction,
                       d.band_midpoint)                                   AS util_pct
    FROM lagged l
    JOIN DIM_METRIC_DEFINITION d USING (metric_key)
    WHERE l.day_idx BETWEEN 61 AND 65
),
final AS (
    SELECT
        e.*,
        -- The threshold actually applied: the breached level if in breach,
        -- otherwise the binding L1 threshold.
        CASE e.breach_level
            WHEN 'L3' THEN e.l3_limit
            WHEN 'L2' THEN e.l2_limit
            WHEN 'L1' THEN e.l1_limit
            ELSE e.l1_limit
        END AS applied_threshold,
        CASE e.breach_level
            WHEN 'L3' THEN e.l3_limit
            WHEN 'L2' THEN e.l2_limit
            WHEN 'L1' THEN e.l1_limit
            ELSE NULL
        END AS breached_limit
    FROM emitted e
)
SELECT
    dimension_type_code,
    lob_identifier,
    lob_description,
    legal_entity_identifier,
    legal_entity_description,
    metric_name,
    source_frequency,
    source_unit,
    metric_type,
    cob_date                                                    AS metric_cob_date,
    FN_FMT(util_pct, 1)                                         AS current_utilization_level,
    FN_FMT(raw_value, decimals)                                 AS current_value,
    FN_FMT(l1_limit, decimals)                                  AS l1_limit_value,
    FN_FMT(l2_limit, decimals)                                  AS l2_limit_value,
    FN_FMT(l3_limit, decimals)                                  AS l3_limit_value,
    FN_FMT(applied_threshold, decimals)                         AS threshold,
    CASE limit_direction WHEN '+' THEN '>=' WHEN '-' THEN '<=' ELSE 'between' END AS limit_operator,
    limit_direction,
    metric_identifier,
    lookback_period,
    metric_subtype,
    reporting_unit,
    metric_source,
    region_name,
    reporting_dates,
    COALESCE(breach_level, 'none')                              AS breach_level,
    FN_FMT(FN_BREACH_AMOUNT(raw_value, breached_limit, limit_direction, band_midpoint), decimals)
                                                                AS breach_amount,
    TO_VARCHAR(sort_order)                                      AS sort_order,

    -- Daily trend points: populated only for metrics displayed daily.
    IFF(display_freq = 'daily', cob_date, NULL)                 AS daily_trend_date1,
    IFF(display_freq = 'daily', FN_FMT(raw_value, decimals), NULL) AS daily_trend_value1,
    IFF(display_freq = 'daily', d_l1, NULL)                     AS daily_trend_date2,
    IFF(display_freq = 'daily', FN_FMT(v_l1, decimals), NULL)   AS daily_trend_value2,
    IFF(display_freq = 'daily', d_l2, NULL)                     AS daily_trend_date3,
    IFF(display_freq = 'daily', FN_FMT(v_l2, decimals), NULL)   AS daily_trend_value3,
    IFF(display_freq = 'daily', d_l3, NULL)                     AS daily_trend_date4,
    IFF(display_freq = 'daily', FN_FMT(v_l3, decimals), NULL)   AS daily_trend_value4,
    IFF(display_freq = 'daily', d_l4, NULL)                     AS daily_trend_date5,
    IFF(display_freq = 'daily', FN_FMT(v_l4, decimals), NULL)   AS daily_trend_value5,

    -- Weekly trend points: daily and weekly metrics both carry weekly history.
    IFF(display_freq IN ('daily','weekly'), cob_date, NULL)            AS weekly_trend_date1,
    IFF(display_freq IN ('daily','weekly'), FN_FMT(raw_value, decimals), NULL) AS weekly_trend_value1,
    IFF(display_freq IN ('daily','weekly'), d_w1, NULL)                AS weekly_trend_date2,
    IFF(display_freq IN ('daily','weekly'), FN_FMT(v_w1, decimals), NULL)      AS weekly_trend_value2,

    -- Monthly trend points: populated for every metric.
    cob_date                                                    AS monthly_trend_date1,
    FN_FMT(raw_value, decimals)                                 AS monthly_trend_value1,
    d_m1                                                        AS monthly_trend_date2,
    FN_FMT(v_m1, decimals)                                      AS monthly_trend_value2,
    d_m2                                                        AS monthly_trend_date3,
    FN_FMT(v_m2, decimals)                                      AS monthly_trend_value3,

    'LRI_BATCH_PROCESS'                                         AS created_by_user_identifier,
    cob_date                                                    AS created_on_date,
    metric_key,
    is_temporary_limit,
    IFF(raw_value IS NULL, 'false', 'true')                     AS has_source_data,
    display_freq,
    cob_date                                                    AS report_as_of_cob_date,
    -- Month-end COB dates are flagged as End Of Month runs.
    IFF(cob_date = LAST_DAY(cob_date)
        OR (DAYOFWEEKISO(cob_date) = 5 AND MONTH(DATEADD(day, 1, cob_date)) <> MONTH(cob_date)),
        'EOM', 'EOD')                                           AS run_type,
    context_name,
    user_group,
    'LOAD_' || TO_VARCHAR(cob_date, 'YYYYMMDD')                 AS load_id,
    TO_NUMBER(TO_CHAR(cob_date, 'YYYYMMDD'))                    AS batch_identifier
FROM final;
