#!/usr/bin/env bash
#
# Builds the whole demo from an empty account.
#
# Idempotent: every script is CREATE OR REPLACE or TRUNCATE-then-INSERT, and the
# data generator uses FN_URAND (a HASH-based PRNG) rather than RANDOM(), so a
# rebuild reproduces byte-identical data.
#
# Small by design: 10 base metrics x 4 reporting scopes = 40 lines per COB,
# x 5 COB dates = 200 report rows.
#
# Usage:  snowflake/build.sh [connection-name]      # default: DEMO

set -euo pipefail

CONN="${1:-DEMO}"
SQL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for f in 01_setup \
         02_base_table \
         03_udfs \
         04_metric_definitions \
         05_generate_data \
         06_derived_facts \
         07_prompts \
         08_commentary_store \
         09_views \
         10_starter; do
    printf "=== snowflake/%-24s " "${f}.sql"
    snow sql -c "$CONN" -f "$SQL_DIR/${f}.sql" >/dev/null
    echo "ok"
done

echo
echo "Built. Start the app with 'npm run dev' and open http://localhost:5177."
