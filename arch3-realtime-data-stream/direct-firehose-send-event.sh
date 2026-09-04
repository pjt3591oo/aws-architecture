#!/usr/bin/env bash

source .env

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_DEFAULT_REGION=ap-northeast-2

AWS_REGION=$AWS_DEFAULT_REGION
ACCOUNT_ID=000000000000

echo "Sending events directly to Firehose..."


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

  # Firehose Record.Data는 Base64 인코딩된 데이터를 사용
  DATA=$(printf '%s' "$EVENT" | base64 -w 0)

  aws firehose put-record \
    --delivery-stream-name "$FIREHOSE_S3" \
    --record "Data=$DATA"

  aws firehose put-record \
    --delivery-stream-name "$FIREHOSE_OS" \
    --record "Data=$DATA"

  sleep 0.2

done

echo
echo "100 events sent to Firehose."
