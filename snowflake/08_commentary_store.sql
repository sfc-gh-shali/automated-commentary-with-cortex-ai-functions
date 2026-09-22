-- =============================================================================
-- LRI Automated Commentary Demo -- 08: Commentary store and generation
-- =============================================================================
-- AI_COMMENTARY holds one row per (report line x approach), so the same line can
-- carry commentary generated three different ways and the results can be diffed.
--
-- Two columns are deliberately kept side by side on every row:
--
--   PROMPT_INPUT  What this approach actually gave the model.
--   FACT_BLOCK    The authoritative derived facts, stored regardless of approach.
--
-- The second is what makes the comparison scorable. A sentence produced from the
-- raw record can be checked against facts that the raw record never contained --
-- which is exactly the question "is the derived table necessary?" made testable.
--
-- SP_GENERATE_COMMENTARY is the single code path. One MERGE serves every caller:
-- the approach selector, the multi-row batch, and the single-line live button.
-- =============================================================================

USE SCHEMA LRI_DEMO.LRI_BASE;

CREATE OR REPLACE TABLE AI_COMMENTARY (
    RECORD_UNIQUE_IDENTIFIER NUMBER(38,0) NOT NULL
        COMMENT 'Report row this commentary belongs to',
    APPROACH                 VARCHAR      NOT NULL
        COMMENT 'How the commentary was produced: GROUNDED (derived fact block), DIRECT_FULL (raw source record including its pre-computed breach columns), DIRECT_RAW (raw record with those columns withheld)',

    REPORT_AS_OF_COB_DATE    DATE         COMMENT 'COB date of the report row',
    BATCH_IDENTIFIER         NUMBER(38,0) COMMENT 'Batch the report row belongs to',
    METRIC_KEY               NUMBER(38,0) COMMENT 'Metric definition key',
    METRIC_NAME              VARCHAR      COMMENT 'Metric name at time of generation',
    STATUS                   VARCHAR      COMMENT 'Derived status the commentary was written against',

    PROMPT_INPUT             VARCHAR      COMMENT 'The exact text supplied to the model under this approach. Retained so any published sentence can be reconciled to what the model was actually given.',
    INPUT_HASH               VARCHAR      COMMENT 'SHA2 of PROMPT_INPUT. Commentary is regenerated only when this changes.',
    FACT_BLOCK               VARCHAR      COMMENT 'The authoritative derived facts for this row, stored on every approach so direct-approach output can be scored against facts it was never given.',

    AI_COMMENTARY            VARCHAR      COMMENT 'The model-generated draft, never overwritten by a human',
    FINAL_COMMENTARY         VARCHAR      COMMENT 'The text that publishes. Defaults to the AI draft; replaced by the analyst on edit.',
    IS_EDITED                BOOLEAN      DEFAULT FALSE COMMENT 'TRUE once an analyst has amended FINAL_COMMENTARY',
    NEEDS_REVIEW             BOOLEAN      DEFAULT FALSE COMMENT 'TRUE when the input moved after an analyst edit, so the published text may now be stale',
    EDITED_BY                VARCHAR      COMMENT 'User who last amended FINAL_COMMENTARY',
    EDITED_AT                TIMESTAMP_LTZ COMMENT 'When FINAL_COMMENTARY was last amended',

    MODEL_NAME               VARCHAR      COMMENT 'Model used for generation',
    PROMPT_VERSION           VARCHAR      COMMENT 'Prompt version in force at generation time',
    GENERATION_METHOD        VARCHAR      COMMENT 'AI (model-generated) or STATIC (fixed no-data template, no model call)',
    GENERATION_SOURCE        VARCHAR      COMMENT 'What triggered generation: MANUAL, BATCH or LIVE_SINGLE',
    GENERATED_AT             TIMESTAMP_LTZ COMMENT 'When the draft was generated',
    GENERATED_BY             VARCHAR      COMMENT 'Role/user that ran generation'
)
COMMENT = 'AI-drafted and analyst-approved commentary, one row per report line per approach, with full generation provenance.';


-- =============================================================================
-- SP_GENERATE_COMMENTARY
-- -----------------------------------------------------------------------------
--   P_COB_DATE    COB to generate for. NULL = the latest COB present, unless
--                 P_RECORD_IDS names rows, in which case their own COB is used.
--   P_APPROACH    GROUNDED | DIRECT_FULL | DIRECT_RAW.
--   P_RECORD_IDS  Comma-separated RECORD_UNIQUE_IDENTIFIER list, or NULL for
--                 every pending line on the COB. Comma-separated rather than an
--                 ARRAY because the SQL REST API binds typed scalars cleanly and
--                 arrays awkwardly.
--   P_FORCE       TRUE regenerates even when the input is unchanged.
--   P_SOURCE      Label recorded against the run.
-- =============================================================================
CREATE OR REPLACE PROCEDURE SP_GENERATE_COMMENTARY(
    P_COB_DATE   DATE,
    P_APPROACH   VARCHAR,
    P_RECORD_IDS VARCHAR,
    P_FORCE      BOOLEAN,
    P_SOURCE     VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'Generates AI commentary under one of three approaches. Idempotent: only rows whose model input or prompt version has changed are sent to the model.'
AS
$$
DECLARE
    v_model      VARCHAR DEFAULT 'claude-sonnet-5';
    v_cob        DATE;
    v_approach   VARCHAR DEFAULT UPPER(COALESCE(:P_APPROACH, 'GROUNDED'));
    v_source     VARCHAR DEFAULT COALESCE(:P_SOURCE, 'MANUAL');
    v_candidates INTEGER DEFAULT 0;
    v_pending    INTEGER DEFAULT 0;
    v_new        INTEGER DEFAULT 0;
    v_regen      INTEGER DEFAULT 0;
    v_ai         INTEGER DEFAULT 0;
    v_static     INTEGER DEFAULT 0;
    v_protected  INTEGER DEFAULT 0;
BEGIN
    IF (:v_approach NOT IN ('GROUNDED', 'DIRECT_FULL', 'DIRECT_RAW')) THEN
        RETURN 'Unknown approach ' || :v_approach
            || '. Expected GROUNDED, DIRECT_FULL or DIRECT_RAW.';
    END IF;

    -- Resolve the COB. When specific rows are named, take their own COB: a caller
    -- holding record ids should not also have to know which batch they belong to.
    IF (:P_RECORD_IDS IS NOT NULL AND :P_COB_DATE IS NULL) THEN
        SELECT MAX(REPORT_AS_OF_COB_DATE) INTO :v_cob
        FROM LIMITS_INDICATORS_REPORT_DATA
        WHERE RECORD_UNIQUE_IDENTIFIER IN (
            SELECT TRY_TO_NUMBER(TRIM(value))
            FROM TABLE(SPLIT_TO_TABLE(:P_RECORD_IDS, ','))
        );
    ELSEIF (:P_COB_DATE IS NULL) THEN
        SELECT MAX(REPORT_AS_OF_COB_DATE) INTO :v_cob
        FROM LIMITS_INDICATORS_REPORT_DATA;
    ELSE
        v_cob := :P_COB_DATE;
    END IF;

    IF (:v_cob IS NULL) THEN
        RETURN 'No report data found -- nothing to generate.';
    END IF;

    -- Every row in scope for this run, before idempotence.
    SELECT COUNT(*) INTO :v_candidates
    FROM V_PROMPT_ALL
    WHERE approach = :v_approach
      AND requires_commentary
      AND REPORT_AS_OF_COB_DATE = :v_cob
      AND ( :P_RECORD_IDS IS NULL
            OR RECORD_UNIQUE_IDENTIFIER IN (
                 SELECT TRY_TO_NUMBER(TRIM(value))
                 FROM TABLE(SPLIT_TO_TABLE(:P_RECORD_IDS, ','))
               ) );

    -- -----------------------------------------------------------------------
    -- Stage the rows that actually need a model call. Deliberately a separate
    -- statement containing NO AI_COMPLETE: it guarantees the model is invoked
    -- exactly once per pending row rather than relying on the optimiser to
    -- filter before projecting an expensive function.
    -- -----------------------------------------------------------------------
    CREATE OR REPLACE TEMPORARY TABLE TMP_PENDING_COMMENTARY AS
    SELECT
        p.RECORD_UNIQUE_IDENTIFIER, p.REPORT_AS_OF_COB_DATE, p.BATCH_IDENTIFIER,
        p.METRIC_KEY, p.METRIC_NAME, p.status, p.approach,
        p.prompt_input, p.input_hash, p.fact_block, p.prompt_version,
        p.prompt, p.static_commentary, p.has_data,
        (c.RECORD_UNIQUE_IDENTIFIER IS NULL) AS is_new,
        COALESCE(c.IS_EDITED, FALSE)         AS prior_edited
    FROM V_PROMPT_ALL p
    LEFT JOIN AI_COMMENTARY c
           ON c.RECORD_UNIQUE_IDENTIFIER = p.RECORD_UNIQUE_IDENTIFIER
          AND c.APPROACH                 = p.approach
    WHERE p.approach = :v_approach
      AND p.requires_commentary
      AND p.REPORT_AS_OF_COB_DATE = :v_cob
      AND ( :P_RECORD_IDS IS NULL
            OR p.RECORD_UNIQUE_IDENTIFIER IN (
                 SELECT TRY_TO_NUMBER(TRIM(value))
                 FROM TABLE(SPLIT_TO_TABLE(:P_RECORD_IDS, ','))
               ) )
      AND ( :P_FORCE
            OR c.RECORD_UNIQUE_IDENTIFIER IS NULL        -- never generated
            OR c.INPUT_HASH     <> p.input_hash          -- the input moved
            OR c.PROMPT_VERSION <> p.prompt_version );   -- the prompt moved

    SELECT COUNT(*), COUNT_IF(is_new), COUNT_IF(NOT is_new),
           COUNT_IF(has_data), COUNT_IF(NOT has_data), COUNT_IF(prior_edited)
      INTO :v_pending, :v_new, :v_regen, :v_ai, :v_static, :v_protected
    FROM TMP_PENDING_COMMENTARY;

    IF (:v_pending = 0) THEN
        RETURN :v_approach || ' / COB ' || TO_VARCHAR(:v_cob) || ': '
            || :v_candidates || ' rows in scope, all already current'
            || ' -- 0 model calls, no cost incurred.';
    END IF;

    -- -----------------------------------------------------------------------
    -- Generate and upsert. Rows with no sourced value take the fixed template
    -- and never reach the model, so no tokens are spent narrating an absent
    -- number -- and no approach gains an advantage from them.
    -- -----------------------------------------------------------------------
    MERGE INTO AI_COMMENTARY t
    USING (
        SELECT
            RECORD_UNIQUE_IDENTIFIER, approach, REPORT_AS_OF_COB_DATE,
            BATCH_IDENTIFIER, METRIC_KEY, METRIC_NAME, status,
            prompt_input, input_hash, fact_block, prompt_version,
            TRIM(AI_COMPLETE(:v_model, prompt), ' "' || CHR(10) || CHR(13)) AS commentary,
            'AI' AS generation_method
        FROM TMP_PENDING_COMMENTARY
        WHERE has_data

        UNION ALL

        SELECT
            RECORD_UNIQUE_IDENTIFIER, approach, REPORT_AS_OF_COB_DATE,
            BATCH_IDENTIFIER, METRIC_KEY, METRIC_NAME, status,
            prompt_input, input_hash, fact_block, prompt_version,
            static_commentary AS commentary,
            'STATIC' AS generation_method
        FROM TMP_PENDING_COMMENTARY
        WHERE NOT has_data
    ) s
    ON  t.RECORD_UNIQUE_IDENTIFIER = s.RECORD_UNIQUE_IDENTIFIER
    AND t.APPROACH                 = s.approach
    WHEN MATCHED THEN UPDATE SET
        t.STATUS            = s.status,
        t.PROMPT_INPUT      = s.prompt_input,
        t.INPUT_HASH        = s.input_hash,
        t.FACT_BLOCK        = s.fact_block,
        t.AI_COMMENTARY     = s.commentary,
        -- An analyst's wording survives an input change; the row is flagged for
        -- re-review rather than being quietly replaced.
        t.FINAL_COMMENTARY  = IFF(t.IS_EDITED, t.FINAL_COMMENTARY, s.commentary),
        t.NEEDS_REVIEW      = t.IS_EDITED,
        t.MODEL_NAME        = IFF(s.generation_method = 'AI', :v_model, NULL),
        t.PROMPT_VERSION    = s.prompt_version,
        t.GENERATION_METHOD = s.generation_method,
        t.GENERATION_SOURCE = :v_source,
        t.GENERATED_AT      = CURRENT_TIMESTAMP(),
        t.GENERATED_BY      = CURRENT_USER()
    WHEN NOT MATCHED THEN INSERT (
        RECORD_UNIQUE_IDENTIFIER, APPROACH, REPORT_AS_OF_COB_DATE, BATCH_IDENTIFIER,
        METRIC_KEY, METRIC_NAME, STATUS, PROMPT_INPUT, INPUT_HASH, FACT_BLOCK,
        AI_COMMENTARY, FINAL_COMMENTARY, IS_EDITED, NEEDS_REVIEW,
        MODEL_NAME, PROMPT_VERSION, GENERATION_METHOD, GENERATION_SOURCE,
        GENERATED_AT, GENERATED_BY
    ) VALUES (
        s.RECORD_UNIQUE_IDENTIFIER, s.approach, s.REPORT_AS_OF_COB_DATE, s.BATCH_IDENTIFIER,
        s.METRIC_KEY, s.METRIC_NAME, s.status, s.prompt_input, s.input_hash, s.fact_block,
        s.commentary, s.commentary, FALSE, FALSE,
        IFF(s.generation_method = 'AI', :v_model, NULL), s.prompt_version,
        s.generation_method, :v_source, CURRENT_TIMESTAMP(), CURRENT_USER()
    );

    RETURN :v_approach || ' / COB ' || TO_VARCHAR(:v_cob) || ' [' || :v_source || ']: '
        || :v_candidates || ' rows in scope; '
        || :v_pending   || ' generated ('
        || :v_new       || ' new, '
        || :v_regen     || ' refreshed); '
        || :v_ai        || ' model calls, '
        || :v_static    || ' no-data templates; '
        || (:v_candidates - :v_pending) || ' skipped as unchanged'
        || IFF(:v_protected > 0,
               '; ' || :v_protected || ' analyst-edited rows preserved and flagged for review', '')
        || '.';
END;
$$;
