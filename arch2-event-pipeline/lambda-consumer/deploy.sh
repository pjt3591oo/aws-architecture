#!/usr/bin/env bash
# entry-lambda 코드 배포. 함수 자체는 terraform이 생성/관리하므로
# 이 스크립트는 절대 create-function을 하지 않는다 (terraform state와
# 충돌하는 걸 막기 위함 - modules/pipeline/lambda.tf의 lifecycle.ignore_changes
# 는 "terraform이 만든 함수의 코드를 CI가 갱신하는 것"만 전제한다).
set -euo pipefail

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_DEFAULT_REGION=ap-northeast-2
ACCOUNT_ID=000000000000


STAGE=${1:-dev}
FUNCTION_NAME="demo-entry-lambda-${STAGE}"

npm install --omit=dev --silent
zip -q -r ./consumer-lambda.zip index.js node_modules

if ! aws lambda get-function --function-name "$FUNCTION_NAME" >/dev/null 2>&1; then
  echo "함수 ${FUNCTION_NAME} 가 아직 없습니다." >&2
  echo "이 스크립트는 코드만 업데이트합니다. 먼저 terraform apply로 인프라를 생성하세요." >&2
  exit 1
fi

aws lambda update-function-code \
  --function-name "$FUNCTION_NAME" \
  --zip-file fileb://consumer-lambda.zip >/dev/null

aws lambda wait function-updated --function-name "$FUNCTION_NAME"
echo "${FUNCTION_NAME} 코드 업데이트 완료"

