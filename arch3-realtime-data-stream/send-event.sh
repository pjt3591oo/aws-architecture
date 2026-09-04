#!/usr/bin/env bash

set -euo pipefail

source .env

echo "Sending events to Kinesis..."
echo

for i in $(seq 1 100); do

  EVENT_TYPE=$(shuf -e \
    order_created \
    payment_completed \
    product_view \
    login \
    order_cancelled \
    -n 1)

  USER_ID="user-$((RANDOM % 10 + 1))"

  PRODUCT_ID="product-$((RANDOM % 5 + 1))"

  AMOUNT=$((RANDOM % 100000 + 1000))

  EVENT_ID="evt-$i"

  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  EVENT=$(cat <<EOF
{
  "event_id": "$EVENT_ID",
  "event_type": "$EVENT_TYPE",
  "user_id": "$USER_ID",
  "product_id": "$PRODUCT_ID",
  "amount": $AMOUNT,
  "timestamp": "$TIMESTAMP"
}
EOF
)

  echo "$EVENT"

  aws kinesis put-record \
    --stream-name "$KINESIS_STREAM" \
    --partition-key "$USER_ID" \
    --data "$(echo -n "$EVENT" | base64)"

  sleep 0.2

done

echo
echo "100 events sent."