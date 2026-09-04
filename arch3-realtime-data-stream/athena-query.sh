#!/usr/bin/env bash

set -euo pipefail

source .env

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_DEFAULT_REGION=ap-northeast-2

AWS_REGION=$AWS_DEFAULT_REGION
ACCOUNT_ID=000000000000

if [ -z "${GLUE_DATABASE:-}" ]; then
    echo "ERROR: GLUE_DATABASE is not set"
    exit 1
fi

if [ -z "${GLUE_TABLE:-}" ]; then
    echo "ERROR: GLUE_TABLE is not set"
    exit 1
fi

if [ -z "${ATHENA_WORKGROUP:-}" ]; then
    echo "ERROR: ATHENA_WORKGROUP is not set"
    exit 1
fi

# 기본 쿼리:
# 테이블 이름에 '-'가 포함되어 있으므로 double quote 처리
QUERY="${1:-SELECT * FROM \"${GLUE_TABLE}\" LIMIT 10}"

echo
echo "============================================================"
echo "Athena Query"
echo "============================================================"

echo "$QUERY"

echo
echo "Database : $GLUE_DATABASE"
echo "Table    : $GLUE_TABLE"
echo "Workgroup: $ATHENA_WORKGROUP"

QUERY_ID=$(aws athena start-query-execution \
    --query-string "$QUERY" \
    --query-execution-context "Database=$GLUE_DATABASE" \
    --work-group "$ATHENA_WORKGROUP" \
    --query 'QueryExecutionId' \
    --output text)

echo
echo "Query ID: $QUERY_ID"

while true; do

    STATUS=$(aws athena get-query-execution \
        --query-execution-id "$QUERY_ID" \
        --query 'QueryExecution.Status.State' \
        --output text)

    echo "Status: $STATUS"

    case "$STATUS" in
        SUCCEEDED)
            break
            ;;

        FAILED)
            echo
            echo "Query failed."

            aws athena get-query-execution \
                --query-execution-id "$QUERY_ID"

            exit 1
            ;;

        CANCELLED)
            echo "Query cancelled."
            exit 1
            ;;

        *)
            sleep 2
            ;;
    esac

done

echo
echo "============================================================"
echo "Result"
echo "============================================================"

aws athena get-query-results \
    --query-execution-id "$QUERY_ID"
