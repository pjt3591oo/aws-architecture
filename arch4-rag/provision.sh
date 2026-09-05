#!/usr/bin/env bash
# =====================================================================
# provision.sh
#
# S3 -> S3 Vectors -> Vector Search -> Lambda/API -> LLM(llama.cpp) 아키텍처를
# floci(로컬 AWS 에뮬레이터) 위에 프로비저닝합니다.
#
# 이 스크립트는 floci만 기동합니다. llama.cpp(embedding/chat 서버)는
# 직접 별도로 실행해두세요. 예:
#   llama server --embedding --pooling mean --port 8081
#   llama server --port 8082
#
# Lambda 함수는 Node.js(nodejs20.x)로 작성되어 있습니다.
#
# 사용법:
#   ./provision.sh up        # 전체 인프라 생성 (기본)
#   ./provision.sh down      # 인프라 삭제
#   ./provision.sh status    # 생성된 리소스 확인
#
# 사전 준비물:
#   - docker, docker compose
#   - aws cli v2 (s3vectors 서브커맨드를 지원하는 최신 버전)
#   - jq, zip, node/npm
#   - 로컬에서 직접 실행 중인 llama.cpp 임베딩(:8081) / 채팅(:8082) 서버
# =====================================================================
set -euo pipefail

# ---------------------------------------------------------------------
# 0. 설정값
# ---------------------------------------------------------------------
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${ROOT_DIR}/.build"

export AWS_ENDPOINT_URL="http://localhost:4566"
export AWS_DEFAULT_REGION="ap-northeast-2"
export AWS_ACCESS_KEY_ID="test"
export AWS_SECRET_ACCESS_KEY="test"

AWS_ENDPOINT_URL_ON_CONTAINER="http://host.docker.internal:4566"  # Lambda 환경변수로 전달

DOCS_BUCKET="rag-documents"
VECTOR_BUCKET="rag-vectors"
INDEX_NAME="docs-index"
EMBEDDING_DIM=1024              # 사용하는 임베딩 모델 차원에 맞게 수정하세요 (예: nomic-embed-text=768)

INGEST_FN="ingest-handler"
QUERY_FN="query-handler"
LAMBDA_ROLE_NAME="rag-lambda-role"
LAMBDA_ROLE_ARN="arn:aws:iam::000000000000:role/${LAMBDA_ROLE_NAME}"

API_NAME="rag-query-api"
API_STAGE="dev"

# 로컬에서 직접 실행 중인 llama.cpp 서버 주소
# Lambda는 floci가 띄우는 도커 컨테이너 안에서 실행되므로 호스트 접근 시 host.docker.internal 사용
EMBEDDING_URL="http://host.docker.internal:8081/v1/embeddings"
CHAT_URL="http://host.docker.internal:8082/v1/chat/completions"

ACTION="${1:-up}"

log() { echo -e "\n\033[1;36m[provision]\033[0m $*" >&2; }
err() { echo -e "\n\033[1;31m[error]\033[0m $*" >&2; }

mkdir -p "$BUILD_DIR"

# =====================================================================
# up
# =====================================================================
if [[ "$ACTION" == "up" ]]; then

  # ---------------------------------------------------------------------
  # 1. 사전 점검
  # ---------------------------------------------------------------------
  log "사전 요구사항 확인 중..."

  for cmd in docker aws jq zip npm; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      err "'$cmd' 명령을 찾을 수 없습니다. 설치 후 다시 실행하세요."
      exit 1
    fi
  done

  if ! docker compose version >/dev/null 2>&1; then
    err "docker compose (v2) 가 필요합니다."
    exit 1
  fi

  if ! aws s3vectors help >/dev/null 2>&1; then
    err "설치된 aws cli가 s3vectors 서브커맨드를 지원하지 않습니다. AWS CLI를 최신 버전으로 업데이트하세요."
    exit 1
  fi

  log "로컬 llama.cpp 서버 확인 중 (embed:8081, chat:8082)..."
  for url in "http://localhost:8081/health" "http://localhost:8082/health"; do
    if ! curl -sf "$url" >/dev/null 2>&1; then
      err "$url 에 접근할 수 없습니다. llama.cpp 서버를 먼저 직접 실행해두세요."
      exit 1
    fi
  done
  log "llama.cpp 서버 확인 완료"

  # ---------------------------------------------------------------------
  # 2. floci 기동 (필요 시 주석 해제)
  # ---------------------------------------------------------------------
  # log "docker compose로 floci 기동 중..."
  # (cd "$ROOT_DIR" && docker compose up -d)
  #
  # log "floci 헬스체크 대기 중..."
  # for i in $(seq 1 60); do
  #   if curl -sf "${AWS_ENDPOINT_URL}/_localstack/health" >/dev/null 2>&1; then
  #     log "floci 준비 완료"
  #     break
  #   fi
  #   sleep 2
  #   if [[ "$i" -eq 60 ]]; then
  #     err "floci가 제한 시간 내에 준비되지 않았습니다. 'docker compose logs floci'로 확인하세요."
  #     exit 1
  #   fi
  # done

  # ---------------------------------------------------------------------
  # 3. S3 원본 문서 버킷
  # ---------------------------------------------------------------------
  log "S3 버킷 생성: s3://${DOCS_BUCKET}"
  aws s3 mb "s3://${DOCS_BUCKET}" 2>/dev/null || log "버킷이 이미 존재합니다."

  # ---------------------------------------------------------------------
  # 4. S3 Vectors 버킷 + 인덱스
  # ---------------------------------------------------------------------
  log "S3 Vectors 버킷 생성: ${VECTOR_BUCKET}"
  aws s3vectors create-vector-bucket \
    --vector-bucket-name "${VECTOR_BUCKET}" 2>/dev/null || log "벡터 버킷이 이미 존재합니다."

  log "S3 Vectors 인덱스 생성: ${INDEX_NAME} (dim=${EMBEDDING_DIM}, metric=cosine)"
  aws s3vectors create-index \
    --vector-bucket-name "${VECTOR_BUCKET}" \
    --index-name "${INDEX_NAME}" \
    --data-type float32 \
    --dimension "${EMBEDDING_DIM}" \
    --distance-metric cosine 2>/dev/null || log "인덱스가 이미 존재합니다."

  # ---------------------------------------------------------------------
  # 5. IAM 역할 (Lambda 실행용)
  # ---------------------------------------------------------------------
  log "Lambda 실행 역할 생성: ${LAMBDA_ROLE_NAME}"
  cat > "${BUILD_DIR}/trust-policy.json" <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Service": "lambda.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  aws iam create-role \
    --role-name "${LAMBDA_ROLE_NAME}" \
    --assume-role-policy-document "file://${BUILD_DIR}/trust-policy.json" \
    >/dev/null 2>&1 || log "역할이 이미 존재합니다."

  aws iam attach-role-policy \
    --role-name "${LAMBDA_ROLE_NAME}" \
    --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess" \
    >/dev/null 2>&1 || true

  # ---------------------------------------------------------------------
  # 6. ingest-handler 패키징 + 배포
  # ---------------------------------------------------------------------
  log "Lambda 패키징: ${INGEST_FN}"
  INGEST_PKG_DIR="${BUILD_DIR}/${INGEST_FN}"
  INGEST_ZIP="${BUILD_DIR}/${INGEST_FN}.zip"

  rm -rf "$INGEST_PKG_DIR" "$INGEST_ZIP"
  mkdir -p "$INGEST_PKG_DIR"

  cp "${ROOT_DIR}/lambda/ingest/index.js" "${ROOT_DIR}/lambda/ingest/package.json" "$INGEST_PKG_DIR/"
  (cd "$INGEST_PKG_DIR" && npm install --omit=dev --silent)
  (cd "$INGEST_PKG_DIR" && zip -qr "$INGEST_ZIP" .)

  INGEST_ENV_JSON="{\"Variables\":{\"VECTOR_BUCKET\":\"${VECTOR_BUCKET}\",\"INDEX_NAME\":\"${INDEX_NAME}\",\"EMBEDDING_URL\":\"${EMBEDDING_URL}\",\"AWS_ENDPOINT_URL\":\"${AWS_ENDPOINT_URL_ON_CONTAINER}\"}}"

  if aws lambda get-function --function-name "$INGEST_FN" >/dev/null 2>&1; then
    log "Lambda 업데이트: ${INGEST_FN}"
    aws lambda update-function-code \
      --function-name "$INGEST_FN" \
      --zip-file "fileb://${INGEST_ZIP}" >/dev/null
    aws lambda update-function-configuration \
      --function-name "$INGEST_FN" \
      --environment "$INGEST_ENV_JSON" >/dev/null
  else
    log "Lambda 생성: ${INGEST_FN}"
    aws lambda create-function \
      --function-name "$INGEST_FN" \
      --runtime nodejs22.x \
      --role "$LAMBDA_ROLE_ARN" \
      --handler index.handler \
      --zip-file "fileb://${INGEST_ZIP}" \
      --timeout 60 \
      --memory-size 512 \
      --environment "$INGEST_ENV_JSON" >/dev/null
  fi

  # ---------------------------------------------------------------------
  # 7. query-handler 패키징 + 배포
  # ---------------------------------------------------------------------
  log "Lambda 패키징: ${QUERY_FN}"
  QUERY_PKG_DIR="${BUILD_DIR}/${QUERY_FN}"
  QUERY_ZIP="${BUILD_DIR}/${QUERY_FN}.zip"

  rm -rf "$QUERY_PKG_DIR" "$QUERY_ZIP"
  mkdir -p "$QUERY_PKG_DIR"

  cp "${ROOT_DIR}/lambda/query/index.js" "${ROOT_DIR}/lambda/query/package.json" "$QUERY_PKG_DIR/"
  (cd "$QUERY_PKG_DIR" && npm install --omit=dev --silent)
  (cd "$QUERY_PKG_DIR" && zip -qr "$QUERY_ZIP" .)

  QUERY_ENV_JSON="{\"Variables\":{\"VECTOR_BUCKET\":\"${VECTOR_BUCKET}\",\"INDEX_NAME\":\"${INDEX_NAME}\",\"EMBEDDING_URL\":\"${EMBEDDING_URL}\",\"CHAT_URL\":\"${CHAT_URL}\",\"AWS_ENDPOINT_URL\":\"${AWS_ENDPOINT_URL_ON_CONTAINER}\"}}"

  if aws lambda get-function --function-name "$QUERY_FN" >/dev/null 2>&1; then
    log "Lambda 업데이트: ${QUERY_FN}"
    aws lambda update-function-code \
      --function-name "$QUERY_FN" \
      --zip-file "fileb://${QUERY_ZIP}" >/dev/null
    aws lambda update-function-configuration \
      --function-name "$QUERY_FN" \
      --environment "$QUERY_ENV_JSON" >/dev/null
  else
    log "Lambda 생성: ${QUERY_FN}"
    aws lambda create-function \
      --function-name "$QUERY_FN" \
      --runtime nodejs22.x \
      --role "$LAMBDA_ROLE_ARN" \
      --handler index.handler \
      --zip-file "fileb://${QUERY_ZIP}" \
      --timeout 60 \
      --memory-size 512 \
      --environment "$QUERY_ENV_JSON" >/dev/null
fi

  # ---------------------------------------------------------------------
  # 8. S3 -> ingest Lambda 이벤트 트리거 연결
  # ---------------------------------------------------------------------
  log "S3 이벤트 알림 -> ${INGEST_FN} 연결"

  INGEST_ARN=$(aws lambda get-function --function-name "$INGEST_FN" \
    --query 'Configuration.FunctionArn' --output text)

  aws lambda add-permission \
    --function-name "$INGEST_FN" \
    --statement-id "s3invoke" \
    --action "lambda:InvokeFunction" \
    --principal "s3.amazonaws.com" \
    --source-arn "arn:aws:s3:::${DOCS_BUCKET}" \
    >/dev/null 2>&1 || true

  cat > "${BUILD_DIR}/notification.json" <<EOF
{
  "LambdaFunctionConfigurations": [
    {
      "LambdaFunctionArn": "${INGEST_ARN}",
      "Events": ["s3:ObjectCreated:*"]
    }
  ]
}
EOF

  aws s3api put-bucket-notification-configuration \
    --bucket "${DOCS_BUCKET}" \
    --notification-configuration "file://${BUILD_DIR}/notification.json"

  # ---------------------------------------------------------------------
  # 9. API Gateway -> query Lambda 연결
  # ---------------------------------------------------------------------
  log "API Gateway REST API 생성: ${API_NAME}"

  API_ID=$(aws apigateway create-rest-api --name "${API_NAME}" --query 'id' --output text)

  ROOT_RESOURCE_ID=$(aws apigateway get-resources --rest-api-id "$API_ID" \
    --query 'items[?path==`/`].id | [0]' --output text)

  QUERY_RESOURCE_ID=$(aws apigateway create-resource \
    --rest-api-id "$API_ID" \
    --parent-id "$ROOT_RESOURCE_ID" \
    --path-part "query" \
    --query 'id' --output text)

  aws apigateway put-method \
    --rest-api-id "$API_ID" \
    --resource-id "$QUERY_RESOURCE_ID" \
    --http-method POST \
    --authorization-type NONE >/dev/null

  QUERY_LAMBDA_ARN=$(aws lambda get-function --function-name "$QUERY_FN" \
    --query 'Configuration.FunctionArn' --output text)

  aws apigateway put-integration \
    --rest-api-id "$API_ID" \
    --resource-id "$QUERY_RESOURCE_ID" \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:${AWS_DEFAULT_REGION}:lambda:path/2015-03-31/functions/${QUERY_LAMBDA_ARN}/invocations" \
    >/dev/null

  aws lambda add-permission \
    --function-name "$QUERY_FN" \
    --statement-id "apigwinvoke" \
    --action "lambda:InvokeFunction" \
    --principal "apigateway.amazonaws.com" \
    --source-arn "arn:aws:execute-api:${AWS_DEFAULT_REGION}:000000000000:${API_ID}/*/*/query" \
    >/dev/null 2>&1 || true

  aws apigateway create-deployment \
    --rest-api-id "$API_ID" \
    --stage-name "${API_STAGE}" >/dev/null

  echo "$API_ID" > "${BUILD_DIR}/api_id.txt"

  INVOKE_URL="${AWS_ENDPOINT_URL}/restapis/${API_ID}/${API_STAGE}/_user_request_/query"
  log "API 엔드포인트: ${INVOKE_URL}"
  echo "$INVOKE_URL" > "${BUILD_DIR}/invoke_url.txt"

  # ---------------------------------------------------------------------
  # 10. 완료
  # ---------------------------------------------------------------------
  log "프로비저닝 완료!"
  echo "----------------------------------------------------------------"
  echo " 문서 업로드 (자동 임베딩 트리거):"
  echo "   aws s3 cp ./test_docs/01_architecture_overview.md s3://${DOCS_BUCKET}/architecture_overview.md"
  echo "   aws s3 cp ./test_docs/02_kinesis.md s3://${DOCS_BUCKET}/kinesis.md"
  echo "   aws s3 cp ./test_docs/03_opensearch.md s3://${DOCS_BUCKET}/opensearch.md"
  echo "   aws s3 cp ./test_docs/04_s3_glue_athena.md s3://${DOCS_BUCKET}/s3_glue_athena.md"
  echo "   aws s3 cp ./test_docs/05_scenarios.md s3://${DOCS_BUCKET}/scenarios.md"
  echo "   aws s3 cp ./test_docs/06_design_decisions.md s3://${DOCS_BUCKET}/design_decisions.md"
  echo
  echo " 질의 (RAG API 호출):"
  echo "   curl -X POST \"$(cat "${BUILD_DIR}/invoke_url.txt")\" \\"
  echo "     -H 'Content-Type: application/json' \\"
  echo "     -d '{\"question\": \"Kinesis Data Streams의 역할은 무엇인가?\"}'"
  echo "----------------------------------------------------------------"

# =====================================================================
# down
# =====================================================================
elif [[ "$ACTION" == "down" ]]; then

  log "리소스 정리 및 컨테이너 종료"

  API_ID_FILE="${BUILD_DIR}/api_id.txt"
  if [[ -f "$API_ID_FILE" ]]; then
    aws apigateway delete-rest-api --rest-api-id "$(cat "$API_ID_FILE")" >/dev/null 2>&1 || true
  fi

  aws lambda delete-function --function-name "$INGEST_FN" >/dev/null 2>&1 || true
  aws lambda delete-function --function-name "$QUERY_FN" >/dev/null 2>&1 || true

  aws iam detach-role-policy \
    --role-name "$LAMBDA_ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess" >/dev/null 2>&1 || true
  aws iam delete-role --role-name "$LAMBDA_ROLE_NAME" >/dev/null 2>&1 || true

  (cd "$ROOT_DIR" && docker compose down)

  rm -rf "$BUILD_DIR"

# =====================================================================
# status
# =====================================================================
elif [[ "$ACTION" == "status" ]]; then

  echo "== S3 buckets ==";      aws s3 ls || true
  echo "== S3 Vectors ==";      aws s3vectors list-vector-buckets || true
  echo "== Lambda ==";          aws lambda list-functions --query 'Functions[].FunctionName' || true
  echo "== API Gateway ==";     aws apigateway get-rest-apis --query 'items[].{id:id,name:name}' || true

else

  echo "사용법: $0 {up|down|status}"
  exit 1

fi