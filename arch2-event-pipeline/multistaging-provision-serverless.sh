#!/usr/bin/env bash
set -euo pipefail

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_DEFAULT_REGION=ap-northeast-2
ACCOUNT_ID=000000000000

STAGES=("dev" "prod")

log() { echo -e "\n\033[1;35m[$(date +%H:%M:%S)] $1\033[0m"; }

log "0. Floci 헬스체크"
curl -sf http://localhost:4566/_floci/health >/dev/null || {
  echo "Floci가 응답하지 않습니다. docker compose up -d 먼저 실행하세요." >&2
  exit 1
}

# ----------------------------------------------------------------------------
# 1. 공통 Lambda IAM 역할 생성 (이미 존재하면 예외 처리 및 재사용)
# ----------------------------------------------------------------------------
log "1. Lambda 실행 IAM 역할 생성"
cat << 'EOF' > trust-policy.json
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

# || true 를 통해 이미 역사가 존재해도 스크립트가 멈추지 않도록 설정
aws iam create-role --role-name demo-lambda-role \
  --assume-role-policy-document file://trust-policy.json 2>/dev/null || true

aws iam attach-role-policy --role-name demo-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
aws iam attach-role-policy --role-name demo-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess 2>/dev/null || true
aws iam attach-role-policy --role-name demo-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess 2>/dev/null || true
aws iam attach-role-policy --role-name demo-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSQSFullAccess 2>/dev/null || true

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/demo-lambda-role"
sleep 2

# ----------------------------------------------------------------------------
# 2. Lambda 소스 코드 패키징 (변경사항 감지 조건부 빌드)
# ----------------------------------------------------------------------------
log "2. Lambda 소스 코드 패키징"

build_lambda_if_changed() {
  local DIR="$1"
  local ZIP_NAME="$2"
  local HASH_FILE="${DIR}/.build_hash"

  local CURRENT_HASH
  CURRENT_HASH=$(find "$DIR" -maxdepth 2 -type f \( -name "*.js" -o -name "*.json" \) ! -name ".build_hash" -exec md5sum {} + | sort | md5sum | awk '{print $1}')

  if [ ! -f "$ZIP_NAME" ] || [ ! -f "$HASH_FILE" ] || [ "$CURRENT_HASH" != "$(cat "$HASH_FILE" 2>/dev/null)" ]; then
    echo "  -> [$DIR] 변경 사항 감지. 빌드 및 압축 진행..."
    (
      cd "$DIR"
      npm install --omit=dev --silent
      zip -q -r "../$ZIP_NAME" index.js node_modules
    )
    echo "$CURRENT_HASH" > "$HASH_FILE"
  else
    echo "  -> [$DIR] 변경 사항 없음. 기존 $ZIP_NAME 사용"
  fi
}

build_lambda_if_changed "lambda-entry" "entry-lambda.zip"
build_lambda_if_changed "lambda-consumer" "consumer-lambda.zip"

# ----------------------------------------------------------------------------
# 3. 환경별(dev, prod) 리소스 생성 루프
# ----------------------------------------------------------------------------
for STAGE in "${STAGES[@]}"; do
  log "=== [$STAGE] 환경 인프라 프로비저닝 시작 ==="

  # 3-1. DynamoDB 테이블 (이미 존재할 수 있으므로 실패 무시)
  aws dynamodb create-table \
    --table-name "Orders-${STAGE}" \
    --attribute-definitions AttributeName=orderId,AttributeType=S \
    --key-schema AttributeName=orderId,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST 2>/dev/null || true

  aws dynamodb wait table-exists --table-name "Orders-${STAGE}"

  # 3-2. SQS 큐 생성 및 정책 부여
  Q_URL=$(aws sqs create-queue --queue-name "demo-order-queue-${STAGE}" --query 'QueueUrl' --output text)
  Q_ARN=$(aws sqs get-queue-attributes --queue-url "$Q_URL" \
    --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)

  POLICY_JSON=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowEventBridgeSendMessage",
      "Effect": "Allow",
      "Principal": { "Service": "events.amazonaws.com" },
      "Action": "sqs:SendMessage",
      "Resource": "$Q_ARN"
    }
  ]
}
EOF
)

  # jq / python 없이 JSON 이스케이프 후 SQS 속성에 적용
  python3 -c "import json; print(json.dumps({'Policy': '''$POLICY_JSON'''}))" > "queue-attrs-${STAGE}.json"
  aws sqs set-queue-attributes --queue-url "$Q_URL" --attributes "file://queue-attrs-${STAGE}.json"

  # 3-3. entry-lambda 생성 (이미 있으면 update-function-code 실행)
  if aws lambda get-function --function-name "demo-entry-lambda-${STAGE}" >/dev/null 2>&1; then
    aws lambda update-function-code \
      --function-name "demo-entry-lambda-${STAGE}" \
      --zip-file fileb://entry-lambda.zip >/dev/null
  else
    aws lambda create-function \
      --function-name "demo-entry-lambda-${STAGE}" \
      --runtime nodejs20.x \
      --handler index.handler \
      --role "$ROLE_ARN" \
      --zip-file fileb://entry-lambda.zip \
      --timeout 10 \
      --environment "Variables={AWS_ENDPOINT_URL=http://floci:4566,STAGE=${STAGE},EVENT_SOURCE=demo.api.${STAGE}}" >/dev/null
  fi
  aws lambda wait function-active --function-name "demo-entry-lambda-${STAGE}"

  # 3-4. consumer-lambda 생성 (이미 있으면 update-function-code 실행)
  if aws lambda get-function --function-name "demo-consumer-lambda-${STAGE}" >/dev/null 2>&1; then
    aws lambda update-function-code \
      --function-name "demo-consumer-lambda-${STAGE}" \
      --zip-file fileb://consumer-lambda.zip >/dev/null
  else
    aws lambda create-function \
      --function-name "demo-consumer-lambda-${STAGE}" \
      --runtime nodejs20.x \
      --handler index.handler \
      --role "$ROLE_ARN" \
      --zip-file fileb://consumer-lambda.zip \
      --timeout 10 \
      --environment "Variables={AWS_ENDPOINT_URL=http://floci:4566,TABLE_NAME=Orders-${STAGE}}" >/dev/null
  fi
  aws lambda wait function-active --function-name "demo-consumer-lambda-${STAGE}"

  # 3-5. EventBridge 규칙
  aws events put-rule \
    --name "demo-order-rule-${STAGE}" \
    --event-pattern "{\"source\":[\"demo.api.${STAGE}\"]}" \
    --state ENABLED >/dev/null

  aws events put-targets \
    --rule "demo-order-rule-${STAGE}" \
    --targets "Id=1,Arn=$Q_ARN" >/dev/null

  # 3-6. Event Source Mapping (SQS -> Consumer Lambda)
  if ! aws lambda list-event-source-mappings --function-name "demo-consumer-lambda-${STAGE}" --query "EventSourceMappings[?EventSourceArn=='$Q_ARN'].UUID" --output text | grep -q .; then
    aws lambda create-event-source-mapping \
      --function-name "demo-consumer-lambda-${STAGE}" \
      --event-source-arn "$Q_ARN" \
      --batch-size 5 >/dev/null
  fi
done

# ----------------------------------------------------------------------------
# 4. API Gateway 설정
# ----------------------------------------------------------------------------
log "4. API Gateway 생성 및 스테이지 변수 매핑"
API_ID=$(aws apigateway create-rest-api --name demo-api --query 'id' --output text)
ROOT_ID=$(aws apigateway get-resources --rest-api-id "$API_ID" --query 'items[0].id' --output text)
RES_ID=$(aws apigateway create-resource --rest-api-id "$API_ID" \
  --parent-id "$ROOT_ID" --path-part orders --query 'id' --output text)

aws apigateway put-method --rest-api-id "$API_ID" --resource-id "$RES_ID" \
  --http-method POST --authorization-type NONE >/dev/null

# --uri 값 전체를 작은따옴표로 감싸서 ${stageVariables.functionName} 문자열을 그대로 전달
INTEGRATION_URI="arn:aws:apigateway:${AWS_DEFAULT_REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:${AWS_DEFAULT_REGION}:${ACCOUNT_ID}:function:\${stageVariables.functionName}/invocations"
INTEGRATION_URI=$(echo "$INTEGRATION_URI" | tr -d '\\') # 역슬래시 완전 제거

aws apigateway put-integration --rest-api-id "$API_ID" --resource-id "$RES_ID" \
  --http-method POST --type AWS_PROXY --integration-http-method POST \
  --uri "arn:aws:apigateway:${AWS_DEFAULT_REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:${AWS_DEFAULT_REGION}:${ACCOUNT_ID}:function:"'${stageVariables.functionName}'"/invocations" >/dev/null

for STAGE in "${STAGES[@]}"; do
  FUNC_NAME="demo-entry-lambda-${STAGE}"

  aws apigateway create-deployment \
    --rest-api-id "$API_ID" \
    --stage-name "$STAGE" \
    --variables "functionName=${FUNC_NAME}" >/dev/null

  aws lambda add-permission \
    --function-name "$FUNC_NAME" \
    --statement-id "apigw-invoke-${STAGE}" \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:${AWS_DEFAULT_REGION}:${ACCOUNT_ID}:${API_ID}/${STAGE}/POST/orders" 2>/dev/null || true
done

# ----------------------------------------------------------------------------
# 5. 검증 테스트
# ----------------------------------------------------------------------------
INVOKE_URL_DEV="http://localhost:4566/restapis/${API_ID}/dev/_user_request_/orders"
INVOKE_URL_PROD="http://localhost:4566/restapis/${API_ID}/prod/_user_request_/orders"

log "5-1. [DEV] API 호출 테스트"
curl -s -X POST "$INVOKE_URL_DEV" \
  -H "Content-Type: application/json" \
  -d '{"orderId":"dev-order-1","item":"dev-widget","qty":1}'
echo

log "5-2. [PROD] API 호출 테스트"
curl -s -X POST "$INVOKE_URL_PROD" \
  -H "Content-Type: application/json" \
  -d '{"orderId":"prod-order-1","item":"prod-widget","qty":10}'
echo

log "파이프라인 처리 대기 (5초)..."
sleep 5

echo -e "\n=== DynamoDB Orders-dev 테이블 결과 ==="
aws dynamodb scan --table-name Orders-dev --output table

echo -e "\n=== DynamoDB Orders-prod 테이블 결과 ==="
aws dynamodb scan --table-name Orders-prod --output table

echo -e "\n=========================================="
echo "배포 완료!"
echo "DEV  URL : $INVOKE_URL_DEV"
echo "PROD URL : $INVOKE_URL_PROD"
echo "=========================================="