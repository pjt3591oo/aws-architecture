# API Gateway → Lambda → EventBridge → SQS → Lambda → DynamoDB

## 실행 순서

```bash
# 0. docker-compose.yml에 FLOCI_HOSTNAME/FLOCI_BASE_URL이 반영돼 있는지 먼저 확인
docker compose up -d

# 1. 프로비저닝
cd serverless
chmod +x provision-serverless.sh
./provision-serverless.sh
```

## 구조

```
[클라이언트]
   │ POST /orders
   ▼
[API Gateway REST API] --AWS_PROXY--> [Lambda: demo-entry-lambda]
                                              │ PutEvents(source=demo.api)
                                              ▼
                                     [EventBridge default bus]
                                              │ Rule: source=demo.api
                                              ▼
                                     [SQS: demo-order-queue]
                                              │ Event Source Mapping
                                              ▼
                                     [Lambda: demo-consumer-lambda]
                                              │ PutItem
                                              ▼
                                     [DynamoDB: Orders 테이블]
```

## 공식 문서/이슈 확인 결과 반영된 것들

1. **Lambda `FLOCI_HOSTNAME`/`FLOCI_BASE_URL` 필수** (GitHub Issue #876) — 이게 없으면 Lambda 컨테이너가 Runtime API로 콜백할 때 `connect ECONNREFUSED`로 실패함. `docker-compose.yml`에 이미 반영해둠.
2. **API Gateway REST API의 path 기반 invoke(`/restapis/{id}/{stage}/_user_request_/{path}`)는 한때 404 버그가 있었지만(Issue #874) 현재는 수정(PR #1032)되어 닫힌 상태** — 그래서 이 스크립트는 그 표준 invoke URL 포맷을 그대로 사용함.
3. **API Gateway 통합 타입은 `AWS_PROXY`만 사용** — 논-프록시(`--type AWS`) VTL 매핑 통합은 아직 버그가 열려있음(Issue #2048, Floci가 Lambda path-style URI를 query-protocol로 잘못 해석). `AWS_PROXY`는 정상 동작 확인됨.
4. **`Authorization` 헤더는 절대 보내지 않음** — Floci REST API 에뮬레이션이 인증 방식과 무관하게 `Authorization` 헤더를 SigV4 시도로 오인해서 거부하는 버그가 열려있음(Issue #2050). 이 스크립트는 `authorization-type NONE`으로 만들고 별도 헤더도 안 보내므로 영향 없음.
5. **SQS 큐에 EventBridge용 리소스 정책을 명시적으로 부여** — 실제 AWS에서도 EventBridge가 SQS로 이벤트를 보내려면 큐의 리소스 기반 정책에 `events.amazonaws.com`의 `sqs:SendMessage`를 허용해둬야 함. 이 스텝을 빼면 EventBridge PutEvents 자체는 성공(202)해도 SQS로 실제 전달은 조용히 실패할 수 있음.

## 검증 방법

```bash
# 1. API 호출
curl -X POST http://localhost:4566/restapis/$API_ID/dev/_user_request_/orders \
  -H "Content-Type: application/json" \
  -d '{"orderId":"order-99","item":"widget"}'

# 2. DynamoDB에 실제로 적재됐는지 확인
aws dynamodb scan --table-name Orders

# 3. 중간 단계별로 문제가 생기면 각 람다 로그를 따로 확인
aws logs tail /aws/lambda/demo-entry-lambda --follow
aws logs tail /aws/lambda/demo-consumer-lambda --follow

# 4. EventBridge -> SQS까지는 왔는데 DynamoDB에 안 쌓이면 큐에 메시지가 남아있는지 확인
aws sqs get-queue-attributes --queue-url $QUEUE_URL --attribute-names ApproximateNumberOfMessages
```

## 트러블슈팅 체크리스트

| 증상 | 원인 후보 |
|---|---|
| API 호출이 `Invalid API id specified` (404) | Floci 버전이 오래돼서 Issue #874 수정 전 버전일 수 있음 → `floci/floci:latest`로 pull 확인 |
| entry-lambda 호출이 아예 안 됨 (타임아웃/500) | `FLOCI_HOSTNAME`/`FLOCI_BASE_URL` 미설정 → docker-compose.yml 확인 후 재기동 |
| EventBridge PutEvents는 성공하는데 DynamoDB에 안 쌓임 | 2-1단계(SQS 리소스 정책) 누락 여부, 또는 event pattern(`source: demo.api`)이 실제 PutEvents의 Source 값과 일치하는지 확인 |
| consumer-lambda가 아예 안 불림 | Event Source Mapping 상태 확인: `aws lambda list-event-source-mappings --function-name demo-consumer-lambda` |

## 정리(teardown)

```bash
aws apigateway delete-rest-api --rest-api-id $API_ID
aws lambda delete-event-source-mapping --uuid <7단계에서 생성된 UUID>
aws lambda delete-function --function-name demo-entry-lambda
aws lambda delete-function --function-name demo-consumer-lambda
aws events remove-targets --rule demo-order-rule --ids 1
aws events delete-rule --name demo-order-rule
aws sqs delete-queue --queue-url $QUEUE_URL
aws dynamodb delete-table --table-name Orders
aws iam detach-role-policy --role-name demo-lambda-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam detach-role-policy --role-name demo-lambda-role --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess
aws iam detach-role-policy --role-name demo-lambda-role --policy-arn arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess
aws iam detach-role-policy --role-name demo-lambda-role --policy-arn arn:aws:iam::aws:policy/AmazonSQSFullAccess
aws iam delete-role --role-name demo-lambda-role
```
