-- =============================================================================
-- LRI Automated Commentary Demo -- 03a: Shared breach-evaluation UDFs
-- =============================================================================
-- These functions encode the ONLY definition of breach level, utilization, and
-- breach amount in the demo. Both the synthetic data generator (03b) and the
-- fact-derivation view (04) call them, so the report and the AI fact block can
-- never disagree -- which is the whole trust argument of the demo.
--
-- Direction semantics (LIMIT_DIRECTION):
--   '+'   upper bound  -- breach when value rises above the limit
--   '-'   lower bound  -- breach when value falls below the limit
--   '+/-' band         -- L1/L2/L3 are half-widths around P_MIDPOINT;
--                         breach when |value - midpoint| exceeds a half-width
-- =============================================================================

USE SCHEMA LRI_DEMO.LRI_BASE;

-- -----------------------------------------------------------------------------
-- Breach level: 'L3' > 'L2' > 'L1' > 'none'. NULL value returns NULL (no data).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION FN_BREACH_LEVEL(
    P_VALUE     FLOAT,
    P_L1        FLOAT,
    P_L2        FLOAT,
    P_L3        FLOAT,
    P_DIRECTION VARCHAR,
    P_MIDPOINT  FLOAT
)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'Evaluates which threshold level (L1/L2/L3/none) a metric value breaches, respecting limit direction. Returns NULL when the value is NULL.'
AS
$$
    CASE
        WHEN P_VALUE IS NULL THEN NULL
        WHEN P_DIRECTION = '+' THEN
            CASE WHEN P_VALUE >= P_L3 THEN 'L3'
                 WHEN P_VALUE >= P_L2 THEN 'L2'
                 WHEN P_VALUE >= P_L1 THEN 'L1'
                 ELSE 'none' END
        WHEN P_DIRECTION = '-' THEN
            CASE WHEN P_VALUE <= P_L3 THEN 'L3'
                 WHEN P_VALUE <= P_L2 THEN 'L2'
                 WHEN P_VALUE <= P_L1 THEN 'L1'
                 ELSE 'none' END
        WHEN P_DIRECTION = '+/-' THEN
            CASE WHEN ABS(P_VALUE - P_MIDPOINT) >= P_L3 THEN 'L3'
                 WHEN ABS(P_VALUE - P_MIDPOINT) >= P_L2 THEN 'L2'
                 WHEN ABS(P_VALUE - P_MIDPOINT) >= P_L1 THEN 'L1'
                 ELSE 'none' END
        ELSE 'none'
    END
$$;

-- -----------------------------------------------------------------------------
-- Utilization %: 100 = exactly at the L1 threshold, >100 = in breach.
-- Directionally consistent so "higher utilization is always worse".
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION FN_UTILIZATION(
    P_VALUE     FLOAT,
    P_L1        FLOAT,
    P_DIRECTION VARCHAR,
    P_MIDPOINT  FLOAT
)
RETURNS FLOAT
LANGUAGE SQL
COMMENT = 'Utilization of a metric value against its L1 threshold, expressed so that 100 = at the limit and >100 = breached, regardless of limit direction.'
AS
$$
    CASE
        WHEN P_VALUE IS NULL THEN NULL
        WHEN P_DIRECTION = '+'   AND P_L1 <> 0 THEN P_VALUE / P_L1 * 100
        WHEN P_DIRECTION = '-'   AND P_VALUE <> 0 THEN P_L1 / P_VALUE * 100
        WHEN P_DIRECTION = '+/-' AND P_L1 <> 0 THEN ABS(P_VALUE - P_MIDPOINT) / P_L1 * 100
        ELSE NULL
    END
$$;

-- -----------------------------------------------------------------------------
-- Breach amount: signed magnitude past the breached threshold, in metric units.
-- NULL when not breached.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION FN_BREACH_AMOUNT(
    P_VALUE          FLOAT,
    P_BREACHED_LIMIT FLOAT,
    P_DIRECTION      VARCHAR,
    P_MIDPOINT       FLOAT
)
RETURNS FLOAT
LANGUAGE SQL
COMMENT = 'Magnitude by which a metric value exceeds the threshold level it has breached, in the metric unit of measure. NULL when not breached.'
AS
$$
    CASE
        WHEN P_VALUE IS NULL OR P_BREACHED_LIMIT IS NULL THEN NULL
        WHEN P_DIRECTION = '+'   THEN P_VALUE - P_BREACHED_LIMIT
        WHEN P_DIRECTION = '-'   THEN P_BREACHED_LIMIT - P_VALUE
        WHEN P_DIRECTION = '+/-' THEN ABS(P_VALUE - P_MIDPOINT) - P_BREACHED_LIMIT
        ELSE NULL
    END
$$;

-- -----------------------------------------------------------------------------
-- Deterministic pseudo-random uniform [0,1) from integer seeds.
-- Used instead of RANDOM() so every rebuild of the demo data is identical.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION FN_URAND(P_A INT, P_B INT)
RETURNS FLOAT
LANGUAGE SQL
COMMENT = 'Deterministic uniform pseudo-random value in [0,1) derived from two integer seeds. Reproducible across rebuilds, unlike RANDOM().'
AS
$$
    ((ABS(HASH(P_A, P_B)) % 1000000) / 1000000.0)::FLOAT
$$;

-- -----------------------------------------------------------------------------
-- Presentation formatting: same precision as FN_FMT, plus thousands separators.
-- Used when building the AI fact block so that the model copies an already
-- report-ready figure rather than deciding how to punctuate it itself.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION FN_FMT_PRETTY(P_VALUE FLOAT, P_DECIMALS INT)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'Formats a metric value at its display precision with thousands separators, for use in AI prompts and report display.'
AS
$$
    CASE
        WHEN P_VALUE IS NULL THEN NULL
        WHEN P_DECIMALS = 0  THEN TRIM(TO_CHAR(P_VALUE::NUMBER(38,0), '999,999,999,990'))
        WHEN P_DECIMALS = 1  THEN TRIM(TO_CHAR(P_VALUE::NUMBER(38,1), '999,999,999,990.0'))
        ELSE                      TRIM(TO_CHAR(P_VALUE::NUMBER(38,2), '999,999,999,990.00'))
    END
$$;

-- -----------------------------------------------------------------------------
-- Format a numeric value to the metric's display precision as VARCHAR, matching
-- how the source system stores values. Only 0/1/2 decimals occur in this demo.
-- No thousands separators: this mirrors the raw source feed.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION FN_FMT(P_VALUE FLOAT, P_DECIMALS INT)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'Formats a metric value to its display precision as VARCHAR, mirroring how the source report stores numeric values as strings.'
AS
$$
    CASE
        WHEN P_VALUE IS NULL  THEN NULL
        WHEN P_DECIMALS = 0   THEN TO_VARCHAR(P_VALUE::NUMBER(38,0))
        WHEN P_DECIMALS = 1   THEN TO_VARCHAR(P_VALUE::NUMBER(38,1))
        ELSE                       TO_VARCHAR(P_VALUE::NUMBER(38,2))
    END
$$;
