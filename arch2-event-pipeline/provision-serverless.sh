#!/usr/bin/env bash
# ============================================================================
# API Gateway -> Lambda(entry) -> EventBridge -> SQS -> Lambda(consumer) -> DynamoDB
#
# 사전 조건:
#   - docker-compose.yml 에 FLOCI_HOSTNAME=floci / FLOCI_BASE_URL=http://floci:4566
#     가 반영된 상태로 floci가 떠 있어야 함 (안 그러면 Lambda가 Runtime API에
#     ECONNREFUSED로 실패함 - GitHub Issue #876)
#   - 이 스크립트와 같은 위치에 lambda-entry/, lambda-consumer/ 디렉토리가 있어야 함
#     (npm install은 이 스크립트가 알아서 실행함)
#   - zip 커맨드 필요 (없으면: sudo apt-get install -y zip)
#   - Node.js/npm 설치되어 있어야 함
# ============================================================================
set -euo pipefail

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_DEFAULT_REGION=ap-northeast-2
ACCOUNT_ID=000000000000

log() { echo -e "\n\033[1;35m[$(date +%H:%M:%S)] $1\033[0m"; }

log "0. Floci 헬스체크"
curl -sf http://localhost:4566/_floci/health >/dev/null || {
  echo "Floci가 응답하지 않습니다. docker compose up -d 먼저 실행하세요." >&2
  exit 1
}

# ----------------------------------------------------------------------------
# 1. DynamoDB 테이블 (파이프라인의 최종 목적지)
# ----------------------------------------------------------------------------
log "1. DynamoDB 테이블 생성"
aws dynamodb create-table \
  --table-name Orders \
  --attribute-definitions AttributeName=orderId,AttributeType=S \
  --key-schema AttributeName=orderId,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

aws dynamodb wait table-exists --table-name Orders
echo "DynamoDB 테이블 Orders 준비 완료"

# ----------------------------------------------------------------------------
# 2. SQS 큐 (+ EventBridge가 메시지를 보낼 수 있도록 리소스 정책 부여)
# ----------------------------------------------------------------------------
log "2. SQS 큐 생성"
QUEUE_URL=$(aws sqs create-queue --queue-name demo-order-queue --query 'QueueUrl' --output text)
QUEUE_ARN=$(aws sqs get-queue-attributes --queue-url "$QUEUE_URL" \
  --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)
echo "QUEUE_URL=$QUEUE_URL"
echo "QUEUE_ARN=$QUEUE_ARN"

log "2-1. SQS 큐에 EventBridge SendMessage 허용 정책 부여"
cat > sqs-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowEventBridgeSendMessage",
      "Effect": "Allow",
      "Principal": { "Service": "events.amazonaws.com" },
      "Action": "sqs:SendMessage",
      "Resource": "$QUEUE_ARN"
    }
  ]
}
EOF

# shorthand(--attributes Key=Value) 문법은 Value 안에 "나 { 같은 문자가 섞이면
# 파서가 깨진다 (지금 겪은 에러가 정확히 이거). 그래서 Policy를 문자열 필드로
# 감싼 별도 JSON을 만들어서 --attributes file://... 형태로 넘긴다.
python3 -c "
import json
with open('sqs-policy.json') as f:
    policy = f.read()
with open('queue-attrs.json', 'w') as f:
    json.dump({'Policy': policy}, f)
"

aws sqs set-queue-attributes --queue-url "$QUEUE_URL" \
  --attributes file://queue-attrs.json

# ----------------------------------------------------------------------------
# 3. Lambda 실행 IAM 역할
# ----------------------------------------------------------------------------
log "3. Lambda 실행 IAM 역할 생성"
cat > trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "lambda.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role --role-name demo-lambda-role \
  --assume-role-policy-document file://trust-policy.json >/dev/null

aws iam attach-role-policy --role-name demo-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam attach-role-policy --role-name demo-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess
aws iam attach-role-policy --role-name demo-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess
aws iam attach-role-policy --role-name demo-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSQSFullAccess

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/demo-lambda-role"
echo "ROLE_ARN=$ROLE_ARN"
sleep 2  # 역할 전파 대기 (실제 AWS와 동일하게 즉시 create-function 하면 가끔 실패함)

# ----------------------------------------------------------------------------
# 4. entry-lambda 배포 (API Gateway -> EventBridge)
# ----------------------------------------------------------------------------
log "4. entry-lambda 패키징 및 등록"
(cd lambda-entry && npm install --omit=dev --silent && zip -q -r ../entry-lambda.zip index.js node_modules)

aws lambda create-function \
  --function-name demo-entry-lambda \
  --runtime nodejs20.x \
  --handler index.handler \
  --role "$ROLE_ARN" \
  --zip-file fileb://entry-lambda.zip \
  --timeout 10 \
  --environment "Variables={AWS_ENDPOINT_URL=http://floci:4566}"

aws lambda wait function-active --function-name demo-entry-lambda

# ----------------------------------------------------------------------------
# 5. consumer-lambda 배포 (SQS -> DynamoDB)
# ----------------------------------------------------------------------------
log "5. consumer-lambda 패키징 및 등록"
(cd lambda-consumer && npm install --omit=dev --silent && zip -q -r ../consumer-lambda.zip index.js node_modules)

aws lambda create-function \
  --function-name demo-consumer-lambda \
  --runtime nodejs20.x \
  --handler index.handler \
  --role "$ROLE_ARN" \
  --zip-file fileb://consumer-lambda.zip \
  --timeout 10 \
  --environment "Variables={AWS_ENDPOINT_URL=http://floci:4566}"

aws lambda wait function-active --function-name demo-consumer-lambda

# ----------------------------------------------------------------------------
# 6. EventBridge 규칙: source=demo.api -> target=SQS
# ----------------------------------------------------------------------------
log "6. EventBridge 규칙 생성 및 SQS 타겟 연결"
aws events put-rule \
  --name demo-order-rule \
  --event-pattern '{"source":["demo.api"]}' \
  --state ENABLED

aws events put-targets \
  --rule demo-order-rule \
  --targets "Id=1,Arn=$QUEUE_ARN"

# ----------------------------------------------------------------------------
# 7. Event Source Mapping: SQS -> consumer-lambda
# ----------------------------------------------------------------------------
log "7. SQS -> consumer-lambda 이벤트 소스 매핑"
aws lambda create-event-source-mapping \
  --function-name demo-consumer-lambda \
  --event-source-arn "$QUEUE_ARN" \
  --batch-size 5

# ----------------------------------------------------------------------------
# 8. API Gateway REST API -> entry-lambda (AWS_PROXY)
# ----------------------------------------------------------------------------
log "8. API Gateway REST API 생성"
API_ID=$(aws apigateway create-rest-api --name demo-api --query 'id' --output text)
ROOT_ID=$(aws apigateway get-resources --rest-api-id "$API_ID" --query 'items[0].id' --output text)
RES_ID=$(aws apigateway create-resource --rest-api-id "$API_ID" \
  --parent-id "$ROOT_ID" --path-part orders --query 'id' --output text)

aws apigateway put-method --rest-api-id "$API_ID" --resource-id "$RES_ID" \
  --http-method POST --authorization-type NONE

ENTRY_LAMBDA_ARN="arn:aws:lambda:${AWS_DEFAULT_REGION}:${ACCOUNT_ID}:function:demo-entry-lambda"

aws apigateway put-integration --rest-api-id "$API_ID" --resource-id "$RES_ID" \
  --http-method POST --type AWS_PROXY --integration-http-method POST \
  --uri "arn:aws:apigateway:${AWS_DEFAULT_REGION}:lambda:path/2015-03-31/functions/${ENTRY_LAMBDA_ARN}/invocations"

log "8-1. API Gateway가 entry-lambda를 호출할 수 있도록 권한 부여"
aws lambda add-permission \
  --function-name demo-entry-lambda \
  --statement-id apigw-invoke \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${AWS_DEFAULT_REGION}:${ACCOUNT_ID}:${API_ID}/*/POST/orders"

log "8-2. dev 스테이지로 배포"
aws apigateway create-deployment --rest-api-id "$API_ID" --stage-name dev

INVOKE_URL="http://localhost:4566/restapis/${API_ID}/dev/_user_request_/orders"

# ----------------------------------------------------------------------------
# 9. 검증
# ----------------------------------------------------------------------------
log "9. 엔드투엔드 호출 테스트"
echo "POST $INVOKE_URL"
curl -s -X POST "$INVOKE_URL" \
  -H "Content-Type: application/json" \
  -d '{"orderId":"test-order-1","item":"widget","qty":3}'
echo

log "   EventBridge -> SQS -> Lambda -> DynamoDB 전파 대기 (5초)"
sleep 5

echo
echo "DynamoDB 적재 결과:"
aws dynamodb scan --table-name Orders --output table

cat <<EOF

==========================================
완료
==========================================
API 호출 URL : $INVOKE_URL
SQS Queue    : $QUEUE_URL
DynamoDB     : Orders 테이블

재테스트:
  curl -X POST $INVOKE_URL -H "Content-Type: application/json" -d '{"orderId":"order-2","item":"gadget"}'
  aws dynamodb scan --table-name Orders

CloudWatch Logs로 각 람다 실행 로그도 확인 가능:
  aws logs tail /aws/lambda/demo-entry-lambda --follow
  aws logs tail /aws/lambda/demo-consumer-lambda --follow
EOF