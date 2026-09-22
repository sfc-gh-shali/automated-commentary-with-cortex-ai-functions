-- =============================================================================
-- LRI Automated Commentary Demo -- 03b: Metric definitions (40 metrics)
-- =============================================================================
-- 10 base liquidity metrics x 4 reporting scopes (FIRM, 1 LOB, 2 legal
-- entities) = 40 metrics per COB batch, x 5 COB dates = 200 report rows.
--
-- Kept deliberately small. The ten base metrics still cover every case the
-- commentary layer has to handle -- ceiling, floor and band limits; Limit versus
-- Indicator vocabulary; daily, weekly and monthly frequencies; internal versus
-- market sourced -- so shrinking the row count costs no coverage.
--
-- Thresholds are set in natural units per metric. For '-' (floor) metrics the
-- L2/L3 levels sit BELOW L1; for '+' (ceiling) metrics they sit above; for
-- '+/-' (band) metrics L1/L2/L3 are half-widths around BAND_MIDPOINT.
--
-- METRIC_KEY is assigned scope-first, so keys 1-10 are the FIRM-level metrics,
-- 11-20 the LOB, 21-30 and 31-40 the two legal entities. The planted narrative
-- scenarios are pinned to keys 1-6, plus key 37 (the band metric at the EMEA
-- entity) so the band example is reliable rather than left to the shuffle.
-- =============================================================================

USE SCHEMA LRI_DEMO.LRI_BASE;

CREATE OR REPLACE TABLE DIM_METRIC_DEFINITION AS
WITH base_metric AS (
    SELECT * FROM VALUES
    --  idx, short,       metric_name,                                   metric_type, metric_subtype,       src_unit, rpt_unit, dir,   l1,      l2,       l3,       midpoint, dec, display_freq
    -- Order matters: base_idx 1-6 receive the planted scenarios at FIRM scope.
        (1,  'lcr',       'Liquidity Coverage Ratio',                    'Limit',     'Internal Indicator', '%',      '%',      '-',   100.0,   90.0,     75.0,     NULL,     2,   'daily'),
        (2,  'nsfr',      'Net Stable Funding Ratio',                    'Limit',     'Internal Indicator', '%',      '%',      '-',   100.0,   95.0,     88.0,     NULL,     2,   'monthly'),
        (3,  'hqla',      'HQLA Buffer',                                 'Limit',     'Internal Indicator', 'CCY',    'USD MM', '-',   85000.0, 76500.0,  63750.0,  NULL,     0,   'daily'),
        (4,  'ssh',       'Internal Stress Survival Horizon',            'Limit',     'Internal Indicator', 'DAYS',   'DAYS',   '-',   30.0,    27.0,     22.0,     NULL,     0,   'daily'),
        (5,  'intraday',  'Intraday Liquidity Peak Usage',               'Limit',     'Internal Indicator', 'CCY',    'USD MM', '+',   42000.0, 46200.0,  52500.0,  NULL,     0,   'daily'),
        (6,  'coll-enc',  'Collateral Encumbrance Ratio',                'Limit',     'Internal Indicator', '%',      '%',      '+',   45.00,   49.50,    56.30,    NULL,     2,   'weekly'),
        (7,  'fx-basis',  'EUR/USD 3M FX Basis',                         'Indicator', 'Market Indicator',   'BPS',    'bps',    '+/-', 18.0,    27.00,    36.00,    -8.0,     1,   'daily'),
        (8,  'fx-mm-eur', 'FX Liquidity Mismatch EUR',                   'Limit',     'Internal Indicator', 'CCY',    'EUR MM', '+/-', 3200.0,  4800.0,   6400.0,   0.0,      0,   'daily'),
        (9,  'cds-5y',    '5Y Senior CDS Spread',                        'Indicator', 'Market Indicator',   'BPS',    'bps',    '+',   68.0,    74.80,    85.00,    NULL,     1,   'daily'),
        (10, 'dep-conc',  'Deposit Concentration Top 10 Counterparties', 'Limit',     'Internal Indicator', '%',      '%',      '+',   12.50,   13.75,    15.63,    NULL,     2,   'weekly')
    AS t(base_idx, metric_short, metric_name, metric_type, metric_subtype,
         source_unit, reporting_unit, limit_direction, l1_limit, l2_limit, l3_limit,
         band_midpoint, decimals, display_freq)
),
scope AS (
    SELECT * FROM VALUES
    --  idx, dim_type, lob_id, lob_desc,                 le_id,  le_desc,                       region,          entity_token
        (1, 'FIRM', NULL,  NULL,                     NULL,   NULL,                          'Global',        'gtfg'),
        (2, 'LOB',  '101', 'Capital Markets',        NULL,   NULL,                          'Global',        'gtfg-cm'),
        (3, 'LE',   NULL,  NULL,                     '0802', 'GlobalTrust Bank NA',         'North America', 'gtbna'),
        (4, 'LE',   NULL,  NULL,                     '0743', 'GlobalTrust Securities plc',  'EMEA',          'gtsec')
    AS s(scope_idx, dimension_type_code, lob_identifier, lob_description,
         legal_entity_identifier, legal_entity_description, region_name, entity_token)
),
-- Stage 1: cross base metrics with scopes and assign the stable METRIC_KEY.
crossed AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY s.scope_idx, b.base_idx) AS metric_key,
        b.base_idx, b.metric_short, b.metric_name, b.metric_type, b.metric_subtype,
        b.source_unit, b.reporting_unit, b.limit_direction,
        b.l1_limit::FLOAT AS l1_limit, b.l2_limit::FLOAT AS l2_limit,
        b.l3_limit::FLOAT AS l3_limit, b.band_midpoint::FLOAT AS band_midpoint,
        b.decimals, b.display_freq,
        s.dimension_type_code, s.lob_identifier, s.lob_description,
        s.legal_entity_identifier, s.legal_entity_description, s.region_name,
        s.entity_token
    FROM base_metric b CROSS JOIN scope s
),
-- Stage 2: assign the narrative scenario and draw the random status bucket.
scenario_assigned AS (
    SELECT
        c.*,
        CASE c.metric_key
            WHEN 1 THEN 'ESCALATING'     -- LCR FIRM: walks L1 -> L2 -> L3
            WHEN 2 THEN 'RECEDING'       -- NSFR FIRM: was breached, now back in limit
            WHEN 3 THEN 'PERSISTENT_L2'  -- HQLA FIRM: breached every day in the window
            WHEN 4 THEN 'NEW_L3'         -- Survival horizon FIRM: clean, then sudden L3
            WHEN 5 THEN 'OSCILLATING'    -- Intraday peak FIRM: hovering either side of L1
            WHEN 6 THEN 'NO_DATA'        -- Encumbrance FIRM: upstream feed missing on final COB
            -- Key 37 = EUR/USD 3M FX Basis at the EMEA entity. Pinned into a
            -- band breach because it is the strongest example in the demo and
            -- must not depend on where the shuffle happens to place it.
            WHEN 37 THEN 'BAND_L3'
            ELSE 'RANDOM'
        END                          AS scenario,
        FN_URAND(c.metric_key, 7)    AS r_status,
        FN_URAND(c.metric_key, 13)   AS r_drift,
        FN_URAND(c.metric_key, 17)   AS r_noise,
        FN_URAND(c.metric_key, 23)   AS r_temp,
        FN_URAND(c.metric_key, 991)  AS r_side
    FROM crossed c
),
-- Stage 3: convert a deterministic shuffle into a target utilization on the
-- final COB. 100 = exactly at the L1 threshold, >100 = breached.
--
-- The status mix is assigned by RANK, not by a random draw, so the proportions
-- are exact rather than approximate. At n=40 a uniform draw is far too lumpy to
-- rely on -- it can easily produce zero L3 lines and undercut the whole demo.
--   65% within limit | 12% near-miss | 12% L1 | 6% L2 | 5% L3
--
-- Targets are expressed RELATIVE TO THE METRIC'S OWN THRESHOLDS rather than as
-- fixed utilization numbers. Utilization maps non-linearly to value for floor
-- ('-') metrics -- u=128 is deep L3 for one metric and only L2 for another --
-- so a fixed number cannot reliably land on an intended breach level.
util_target AS (
    SELECT
        sa.*,
        -- Utilization at which this metric crosses into L2 and L3.
        CASE sa.limit_direction
            WHEN '-' THEN sa.l1_limit / sa.l2_limit * 100
            ELSE          sa.l2_limit / sa.l1_limit * 100
        END::FLOAT AS util_at_l2,
        CASE sa.limit_direction
            WHEN '-' THEN sa.l1_limit / sa.l3_limit * 100
            ELSE          sa.l3_limit / sa.l1_limit * 100
        END::FLOAT AS util_at_l3,
        -- Percentile position within the randomly-assigned metrics only.
        PERCENT_RANK() OVER (
            PARTITION BY IFF(sa.scenario = 'RANDOM', 0, 1)
            ORDER BY sa.r_status
        ) AS status_pct
    FROM scenario_assigned sa
),
util_resolved AS (
    SELECT
        ut.*,
        -- Target utilization on the final COB date.
        CASE ut.metric_key
            WHEN 1 THEN ut.util_at_l3 * 1.06   -- comfortably inside L3
            WHEN 2 THEN 91.0                   -- recovered back inside the limit
            WHEN 3 THEN ut.util_at_l2 * 1.06   -- still in L2
            WHEN 4 THEN 70.0                   -- baseline; jump applied per-day in 03c
            WHEN 5 THEN 101.0                  -- fractionally over L1
            WHEN 6 THEN  85.0                  -- value suppressed on the final COB
            WHEN 37 THEN ut.util_at_l3 * 1.14  -- deviation clearly beyond the L3 tolerance
            ELSE CASE
                -- within limit: 40 .. 85 utilization
                WHEN ut.status_pct < 0.65 THEN 40 + ut.status_pct / 0.65 * 45
                -- near miss: 90 .. 99, approaching but not breaching
                WHEN ut.status_pct < 0.77 THEN 90 + (ut.status_pct - 0.65) / 0.12 * 9
                -- L1: between the L1 and L2 crossings
                WHEN ut.status_pct < 0.89
                    THEN 100 + (ut.util_at_l2 - 100)
                             * (0.18 + (ut.status_pct - 0.77) / 0.12 * 0.64)
                -- L2: between the L2 and L3 crossings
                WHEN ut.status_pct < 0.95
                    THEN ut.util_at_l2 + (ut.util_at_l3 - ut.util_at_l2)
                             * (0.18 + (ut.status_pct - 0.89) / 0.06 * 0.64)
                -- L3: beyond the L3 crossing
                ELSE ut.util_at_l3 * (1.03 + (ut.status_pct - 0.95) / 0.05 * 0.12)
            END
        END::FLOAT AS util_end,
        -- Utilization the NEW_L3 scenario jumps to on the final two COB dates.
        IFF(ut.scenario = 'NEW_L3', ut.util_at_l3 * 1.08, NULL)::FLOAT AS util_jump
    FROM util_target ut
)
SELECT
    metric_key,
    base_idx,
    metric_short,
    metric_name,
    metric_type,
    metric_subtype,
    source_unit,
    reporting_unit,
    limit_direction,
    l1_limit,
    l2_limit,
    l3_limit,
    band_midpoint,
    decimals,
    display_freq,
    display_freq AS source_frequency,
    display_freq AS lookback_period,
    dimension_type_code,
    lob_identifier,
    lob_description,
    legal_entity_identifier,
    legal_entity_description,
    region_name,

    -- Composite metric identifier, mirroring the source system's convention:
    -- source - entity - metric short name - qualifier - legal entity
    LOWER(CONCAT_WS('-',
        'str',
        entity_token,
        metric_short,
        CASE WHEN metric_type = 'Indicator' THEN 'indic' ELSE 'lmt' END,
        COALESCE(legal_entity_identifier, lob_identifier, 'firm')
    )) AS metric_identifier,

    -- Band metrics sit on a stable side of the midpoint for the whole window.
    CASE WHEN r_side < 0.5 THEN -1 ELSE 1 END AS band_side,

    scenario,
    util_end,
    util_jump,
    util_at_l2,
    util_at_l3,

    -- Where the metric started the 20-day window.
    CASE metric_key
        WHEN 1 THEN  92.0                 -- just inside the limit
        WHEN 2 THEN util_at_l3 * 1.03     -- opens in L3, then de-escalates
        WHEN 3 THEN util_at_l2 * 1.02     -- opens in L2 and stays there
        WHEN 4 THEN  70.0
        WHEN 5 THEN 100.0
        WHEN 6 THEN  85.0
        ELSE GREATEST(20, util_end + (r_drift - 0.55) * 30)
    END::FLOAT AS util_start,

    CASE
        WHEN scenario = 'OSCILLATING'                 THEN 7.0
        WHEN scenario IN ('ESCALATING', 'RECEDING')   THEN 1.5
        WHEN scenario = 'PERSISTENT_L2'               THEN 2.0
        ELSE 1.0 + r_noise * 2.5
    END::FLOAT AS noise_amp,

    -- Metrics whose final-COB value is deliberately missing (upstream feed gap).
    (scenario = 'NO_DATA' OR (scenario = 'RANDOM' AND status_pct >= 0.99)) AS is_missing_final,

    'LRI_STR_FEED'                                                  AS context_name,
    'EOD'                                                           AS run_type,
    'STR'                                                           AS metric_source,
    'LRI_BUSINESS_CALENDAR'                                         AS reporting_dates,
    CASE WHEN r_temp < 0.04 THEN 'true' ELSE 'false' END            AS is_temporary_limit,
    'LIQ_RISK_GRP_' || LPAD(1 + (metric_key % 6), 2, '0')           AS user_group,
    metric_key                                                      AS sort_order
FROM util_resolved;
