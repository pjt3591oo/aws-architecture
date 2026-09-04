#!/usr/bin/env bash

set -euo pipefail

source .env

echo "============================================================"
echo "OpenSearch"
echo "============================================================"

echo "Endpoint : https://$OPENSEARCH_ENDPOINT"
echo "Index    : $OPENSEARCH_INDEX"

echo
echo "Waiting for Firehose delivery..."
sleep 70

echo
echo "============================================================"
echo "All Events"
echo "============================================================"

curl -s \
  "https://${OPENSEARCH_ENDPOINT}/${OPENSEARCH_INDEX}/_search?pretty"

echo