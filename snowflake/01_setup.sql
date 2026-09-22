-- =============================================================================
-- LRI Automated Commentary Demo -- 01: Setup
-- =============================================================================
-- Creates the demo database, schema, and a dedicated warehouse so that the
-- compute cost of AI commentary generation is separately attributable when
-- discussing cost during the demo.
-- =============================================================================

CREATE DATABASE IF NOT EXISTS LRI_DEMO
    COMMENT = 'Liquidity Risk Indicators automated commentary demo (Snowflake Cortex)';

CREATE SCHEMA IF NOT EXISTS LRI_DEMO.LRI_BASE
    COMMENT = 'Limits & Indicators report base data, fact derivation, and AI commentary';

-- Dedicated warehouse: keeps AI generation credits isolated and measurable.
CREATE WAREHOUSE IF NOT EXISTS LRI_DEMO_WH
    WAREHOUSE_SIZE      = 'XSMALL'
    AUTO_SUSPEND        = 60
    AUTO_RESUME         = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Compute for LRI commentary demo -- sized XS deliberately to show AI cost is model-driven, not warehouse-driven';

USE WAREHOUSE LRI_DEMO_WH;
USE SCHEMA LRI_DEMO.LRI_BASE;
