```sh
aws s3api list-objects-v2 \
  --bucket "$BUCKET" \
  --prefix raw/ \
  --region "$AWS_REGION"

```

```sh
aws firehose list-delivery-streams --region ap-northeast-2
```

```sh
aws firehose describe-delivery-stream \
  --delivery-stream-name kinesis-analytics-demo-to-s3 --query 'DeliveryStreamDescription.DeliveryStreamARN'
```

```sh
aws firehose describe-delivery-stream \
  --delivery-stream-name kinesis-analytics-demo-to-s3 \
  --query 'DeliveryStreamDescription.Destinations[0].ExtendedS3DestinationDescription'
```

```sh
aws firehose describe-delivery-stream \
  --delivery-stream-name kinesis-analytics-demo-to-s3 \
  --query 'DeliveryStreamDescription.Source'
```

```sh
EVENT='{"event_id":"firehose-test-1","event_type":"order_created","user_id":"user-firehose","product_id":"product-1","amount":12345,"timestamp":"2026-09-04T05:00:00Z"}'

DATA=$(printf '%s' "$EVENT" | base64 -w 0)

aws firehose put-record \
  --delivery-stream-name kinesis-analytics-demo-to-s3 \
  --record "Data=$DATA"
```

```sh
EVENT='{"event_id":"firehose-test-1","event_type":"order_created","user_id":"user-firehose","product_id":"product-1","amount":12345,"timestamp":"2026-09-04T05:00:00Z"}'

DATA=$(printf '%s' "$EVENT" | base64 -w 0)

aws firehose put-record \
  --delivery-stream-name kinesis-analytics-demo-to-os \
  --record "Data=$DATA"
```

```sh
 aws kinesis get-shard-iterator \
  --stream-name "$KINESIS_STREAM" \
  --shard-id shardId-000000000000 \
  --shard-iterator-type TRIM_HORIZON
```

```sh
 aws kinesis get-records \
  --shard-iterator "a2luZXNpcy1hbmFseXRpY3MtZGVtby1zdHJlYW18c2hhcmRJZC0wMDAwMDAwMDAwMDB8VFJJTV9IT1JJWk9OfHwwfA=="
```

### athena

* 전체 이벤트 조회

```sh
./athena-query.sh 'SELECT * FROM "kinesis-analytics-demo_events" LIMIT 20'
./athena-query.sh 'SELECT * FROM "kinesis-analytics-demo_events" LIMIT 20'
```

* 이벤트 종류별 집계

```sh
./athena-query.sh \
'SELECT event_type, COUNT(*) AS count
 FROM "kinesis-analytics-demo_events"
 GROUP BY event_type
 ORDER BY count DESC'
```

* 매출분석

```sh
./athena-query.sh \
"SELECT
    user_id,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount
FROM \"kinesis-analytics-demo_events\"
WHERE event_type = 'order_created'
GROUP BY user_id
ORDER BY total_amount DESC"
```

### opensearch

* 특정 이벤트 검색

```sh
curl -s \
  -X POST \
  "http://${OPENSEARCH_ENDPOINT}/${OPENSEARCH_INDEX}/_search?pretty" \
  -H "Content-Type: application/json" \
  -d '
{
  "query": {
    "term": {
      "event_type.keyword": "order_created"
    }
  }
}
'
```

* 사용자별 이벤트 검색

```sh
curl -s \
  -X POST \
  "http://${OPENSEARCH_ENDPOINT}/${OPENSEARCH_INDEX}/_search?pretty" \
  -H "Content-Type: application/json" \
  -d '
{
  "query": {
    "match": {
      "user_id": "user-3"
    }
  }
}
'
```

* 최근 주문 이벤트

```sh
curl -s \
  -X POST \
  "http://${OPENSEARCH_ENDPOINT}/${OPENSEARCH_INDEX}/_search?pretty" \
  -H "Content-Type: application/json" \
  -d '
{
  "size": 10,
  "query": {
    "match": {
      "event_type": "order_created"
    }
  },
  "sort": [
    {
      "timestamp": {
        "order": "desc"
      }
    }
  ]
}
'
```