export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_DEFAULT_REGION=ap-northeast-2
ACCOUNT_ID=000000000000

npm install --omit=dev --silent
zip -q -r ./query-handler.zip index.js node_modules

FUNCTION_NAME="query-handler"

if ! aws lambda get-function --function-name "$FUNCTION_NAME" >/dev/null 2>&1; then
  echo "함수 ${FUNCTION_NAME} 가 아직 없습니다." >&2
  echo "이 스크립트는 코드만 업데이트합니다. 먼저 terraform apply로 인프라를 생성하세요." >&2
  exit 1
fi

aws lambda update-function-code \
  --function-name "$FUNCTION_NAME" \
  --zip-file fileb://query-handler.zip >/dev/null

aws lambda wait function-updated --function-name "$FUNCTION_NAME"
echo "${FUNCTION_NAME} 코드 업데이트 완료"
