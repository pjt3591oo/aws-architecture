#!/usr/bin/env bash

set -euo pipefail

source .env

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_DEFAULT_REGION=ap-northeast-2

AWS_REGION=$AWS_DEFAULT_REGION
ACCOUNT_ID=000000000000

# 기본 쿼리:
# 테이블 이름에 '-'가 포함되어 있으므로 double quote 처리
QUERY="${1:-SELECT * FROM \"${GLUE_TABLE}\" LIMIT 10}"


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
