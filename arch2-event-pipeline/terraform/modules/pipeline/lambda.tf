# ----------------------------------------------------------------------------
# entry-lambda (API Gateway -> EventBridge)
# ----------------------------------------------------------------------------
resource "aws_lambda_function" "entry" {
  function_name = "demo-entry-lambda-${var.env}"
  runtime       = "nodejs20.x"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_role.arn
  timeout       = 10

  # 최초 생성 시에만 쓰이는 placeholder 코드.
  filename         = var.entry_zip_path
  source_code_hash = filebase64sha256(var.entry_zip_path)

  environment {
    variables = {
      AWS_ENDPOINT_URL = "http://floci:4566"
      EVENT_BUS_NAME    = aws_cloudwatch_event_bus.order_bus.name
    }
  }

  # 실제 코드는 CI/CD가 `aws lambda update-function-code`로 배포한다.
  # filename/source_code_hash를 무시하지 않으면, 다음 terraform apply 때
  # CI/CD가 올린 실제 코드를 이 placeholder zip으로 되돌려버린다.
  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}

# ----------------------------------------------------------------------------
# consumer-lambda (SQS -> DynamoDB)
# ----------------------------------------------------------------------------
resource "aws_lambda_function" "consumer" {
  function_name = "demo-consumer-lambda-${var.env}"
  runtime       = "nodejs20.x"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_role.arn
  timeout       = 10

  filename         = var.consumer_zip_path
  source_code_hash = filebase64sha256(var.consumer_zip_path)

  environment {
    variables = {
      AWS_ENDPOINT_URL = "http://floci:4566"
      TABLE_NAME        = aws_dynamodb_table.orders.name
    }
  }

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}
