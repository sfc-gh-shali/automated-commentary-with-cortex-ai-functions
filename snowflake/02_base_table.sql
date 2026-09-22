-- =============================================================================
-- LRI Automated Commentary Demo -- 02: Base report table
-- =============================================================================
-- Faithful recreation of the source LIMITS_INDICATORS_REPORT_DATA structure,
-- retargeted to LRI_DEMO.LRI_BASE.
--
-- NOTE: numeric-looking columns (CURRENT_VALUE, THRESHOLD, BREACH_AMOUNT, all
-- trend values, ...) are intentionally left as VARCHAR to match the real source
-- system. The fact-derivation layer (04) is responsible for safe casting. This
-- is part of the demo narrative: the AI never sees an unvalidated value.
-- =============================================================================

USE SCHEMA LRI_DEMO.LRI_BASE;

CREATE OR REPLACE TABLE LRI_DEMO.LRI_BASE.LIMITS_INDICATORS_REPORT_DATA
  CLUSTER BY (BATCH_IDENTIFIER) (
    RECORD_UNIQUE_IDENTIFIER NUMBER(38,0) NOT NULL AUTOINCREMENT START 1 INCREMENT 1 NOORDER
        COMMENT 'Record Unique Identifier: unique identifier of the record, generated each time appendix records are created',
    DIMENSION_TYPE_CODE VARCHAR(16777216)
        COMMENT 'Metric Scope Dimension Type Code: organizational dimension the metric is evaluated on. Valid values: FIRM, LOB, LE',
    LOB_IDENTIFIER VARCHAR(16777216)
        COMMENT 'Metric Booking Liquidity LOB Identifier: number assigned to a line of business for liquidity reporting',
    LOB_DESCRIPTION VARCHAR(16777216)
        COMMENT 'Metric Booking Liquidity LOB Name: name of the line of business for liquidity reporting',
    LEGAL_ENTITY_IDENTIFIER VARCHAR(16777216)
        COMMENT 'Metric Legal Entity Identifier: identifier of the legal entity the BU-Cost Center belongs to, e.g. 0802, 0743',
    LEGAL_ENTITY_DESCRIPTION VARCHAR(16777216)
        COMMENT 'Metric Booking Legal Entity Long Name: name of the booking legal entity',
    METRIC_NAME VARCHAR(16777216)
        COMMENT 'Metric Name: business-facing label for the metric being monitored against a limit/threshold',
    SOURCE_FREQUENCY VARCHAR(16777216)
        COMMENT 'Metric Frequency Type Code: frequency of data upload. Valid values: daily, weekly, monthly, quarterly',
    SOURCE_UNIT VARCHAR(16777216)
        COMMENT 'Metric Unit Of Measure Type Code: unit-of-measure category. Valid values include %, BPS, CCY, DAYS, SPL%',
    METRIC_TYPE VARCHAR(16777216)
        COMMENT 'Metric Type Code: whether the metric is a Limit or an Indicator. Limit: crossing constitutes a formal breach. Indicator: crossing is a directional/early-warning signal',
    METRIC_COB_DATE DATE
        COMMENT 'Metric Business Effective From Date: COB date from which the metric is valid and evaluable',
    CURRENT_UTILIZATION_LEVEL VARCHAR(16777216)
        COMMENT 'Current Utilization Level Value: utilization of the current metric value relative to the applicable threshold, directionally consistent for min/max/band limits',
    CURRENT_VALUE VARCHAR(16777216)
        COMMENT 'Current Metric Value: most recent metric value used for evaluation as of the metric COB date',
    L1_LIMIT_VALUE VARCHAR(16777216)
        COMMENT 'Metric Limit Level 1 Value. L1 = early warning / operating tolerance',
    L2_LIMIT_VALUE VARCHAR(16777216)
        COMMENT 'Metric Limit Level 2 Value. L2 = material breach needing management escalation',
    L3_LIMIT_VALUE VARCHAR(16777216)
        COMMENT 'Metric Limit Level 3 Value. L3 = critical breach requiring senior/executive escalation',
    THRESHOLD VARCHAR(16777216)
        COMMENT 'Metric Applied Threshold Value: the threshold actually used to evaluate breach/utilization for this record',
    LIMIT_OPERATOR VARCHAR(16777216)
        COMMENT 'Metric Limit Operator Code: comparison operator (>, >=, <, <=, between) used to evaluate value against threshold',
    LIMIT_DIRECTION VARCHAR(16777216)
        COMMENT 'Metric Limit Direction Code: + = upper bound (breach when above); - = lower bound (breach when below); +/- = both, breach when outside range',
    METRIC_IDENTIFIER VARCHAR(16777216)
        COMMENT 'Metric Identifier: composite identifier -- source, entity, metric short name/regulation, methodology qualifiers, legal entity',
    LOOKBACK_PERIOD VARCHAR(16777216)
        COMMENT 'Metric Lookback Period Code: interval for period-over-period comparison. Valid values: daily, weekly, fourWeekly, monthly, quarterly, sixMonthly',
    METRIC_SUBTYPE VARCHAR(16777216)
        COMMENT 'Metric Subtype Code: Internal Indicator (derived from firm internal data/models) vs Market Indicator (derived from external market data)',
    REPORTING_UNIT VARCHAR(16777216)
        COMMENT 'Metric Unit Of Measure Code: specific unit used to express the value, e.g. USD, EUR, %, bps',
    METRIC_SOURCE VARCHAR(16777216)
        COMMENT 'Metric Data Source Type Code: provenance of the value -- STR (strategic feed) vs MDU (manual/user-entered adjustment)',
    REGION_NAME VARCHAR(16777216)
        COMMENT 'Metric Region Name: region associated with the reporting perimeter',
    REPORTING_DATES VARCHAR(16777216)
        COMMENT 'Metric Evaluation Calendar Name: calendar defining the dates on which the metric is evaluated',
    BREACH_LEVEL VARCHAR(16777216)
        COMMENT 'Breach Level Code: which threshold level is currently breached (none/L1/L2/L3)',
    BREACH_AMOUNT VARCHAR(16777216)
        COMMENT 'Breach Amount: magnitude of the breach versus the applicable threshold, in the metric unit of measure; null/blank when not breached',
    SORT_ORDER VARCHAR(16777216)
        COMMENT 'Metric Sort Order Number: ordering value controlling display sequence in reporting outputs',
    DAILY_TREND_DATE1 DATE   COMMENT 'Daily Trend 1 Date: as-of date for the most recent daily trend observation',
    DAILY_TREND_VALUE1 VARCHAR(16777216) COMMENT 'Daily Trend 1 Value: value at DAILY_TREND_DATE1',
    DAILY_TREND_DATE2 DATE   COMMENT 'Daily Trend 2 Date: as-of date one business day earlier',
    DAILY_TREND_VALUE2 VARCHAR(16777216) COMMENT 'Daily Trend 2 Value: value at DAILY_TREND_DATE2',
    DAILY_TREND_DATE3 DATE   COMMENT 'Daily Trend 3 Date: as-of date two days back',
    DAILY_TREND_VALUE3 VARCHAR(16777216) COMMENT 'Daily Trend 3 Value: value at DAILY_TREND_DATE3',
    DAILY_TREND_DATE4 DATE   COMMENT 'Daily Trend 4 Date: as-of date three days back',
    DAILY_TREND_VALUE4 VARCHAR(16777216) COMMENT 'Daily Trend 4 Value: value at DAILY_TREND_DATE4',
    DAILY_TREND_DATE5 DATE   COMMENT 'Daily Trend 5 Date: as-of date four days back',
    DAILY_TREND_VALUE5 VARCHAR(16777216) COMMENT 'Daily Trend 5 Value: value at DAILY_TREND_DATE5',
    WEEKLY_TREND_DATE1 DATE  COMMENT 'Weekly Trend 1 Date: as-of date for the most recent weekly observation',
    WEEKLY_TREND_VALUE1 VARCHAR(16777216) COMMENT 'Weekly Trend 1 Value: value at WEEKLY_TREND_DATE1',
    WEEKLY_TREND_DATE2 DATE  COMMENT 'Weekly Trend 2 Date: as-of date one week earlier',
    WEEKLY_TREND_VALUE2 VARCHAR(16777216) COMMENT 'Weekly Trend 2 Value: value at WEEKLY_TREND_DATE2',
    MONTHLY_TREND_DATE1 DATE COMMENT 'Monthly Trend 1 Date: as-of date for the most recent month-end observation',
    MONTHLY_TREND_VALUE1 VARCHAR(16777216) COMMENT 'Monthly Trend 1 Value: value at MONTHLY_TREND_DATE1',
    MONTHLY_TREND_DATE2 DATE COMMENT 'Monthly Trend 2 Date: as-of date one month earlier',
    MONTHLY_TREND_VALUE2 VARCHAR(16777216) COMMENT 'Monthly Trend 2 Value: value at MONTHLY_TREND_DATE2',
    MONTHLY_TREND_DATE3 DATE COMMENT 'Monthly Trend 3 Date: as-of date two months earlier',
    MONTHLY_TREND_VALUE3 VARCHAR(16777216) COMMENT 'Monthly Trend 3 Value: value at MONTHLY_TREND_DATE3',
    CREATED_BY_USER_IDENTIFIER VARCHAR(16777216)
        COMMENT 'Created By Identifier: process or employee that created the record',
    CREATED_ON_DATE DATE
        COMMENT 'Created On Date: date this record was created',
    METRIC_KEY NUMBER(38,0)
        COMMENT 'Metric Record Unique Identifier: stable internal key uniquely identifying the metric definition',
    IS_TEMPORARY_LIMIT VARCHAR(16777216)
        COMMENT 'Metric Temporary Limit Indicator: flag indicating the limit configuration is a time-bound temporary override',
    HAS_SOURCE_DATA VARCHAR(16777216)
        COMMENT 'Has Source Data Indicator: flag indicating whether an upstream sourced value was available for the relevant COB/run',
    DISPLAY_FREQ VARCHAR(16777216)
        COMMENT 'Metric Display Frequency Code: frequency at which the metric and trend points are presented, may differ from source frequency',
    REPORT_AS_OF_COB_DATE DATE
        COMMENT 'Report As-Of COB Date: reporting cut-off date for the snapshot',
    RUN_TYPE VARCHAR(16777216)
        COMMENT 'Run Type Code: End Of Day (EOD) or End Of Month (EOM) context',
    CONTEXT_NAME VARCHAR(16777216)
        COMMENT 'Supply Context Name: context identifying position data supplied to FRW and LRI',
    USER_GROUP VARCHAR(16777216)
        COMMENT 'Metric User Group Number: owning or entitled user group for the metric/limit',
    LOAD_ID VARCHAR(16777216)
        COMMENT 'Load Identifier: identifies a batch of data ingested via data pipelines',
    BATCH_IDENTIFIER NUMBER(38,0)
        COMMENT 'Batch Identifier: identifier of a set of records created at a point in time'
);
