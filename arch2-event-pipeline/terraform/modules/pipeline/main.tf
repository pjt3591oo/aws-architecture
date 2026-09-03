# ----------------------------------------------------------------------------
# DynamoDB 테이블
# ----------------------------------------------------------------------------
resource "aws_dynamodb_table" "orders" {
  name         = "Orders-${var.env}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "orderId"

  attribute {
    name = "orderId"
    type = "S"
  }
}

# ----------------------------------------------------------------------------
# SQS 큐 (+ EventBridge SendMessage 허용 정책)
# ----------------------------------------------------------------------------
resource "aws_sqs_queue" "order_queue" {
  name = "demo-order-queue-${var.env}"
}

resource "aws_sqs_queue_policy" "allow_eventbridge" {
  queue_url = aws_sqs_queue.order_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventBridgeSendMessage"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.order_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.order_rule.arn
          }
        }
      }
    ]
  })
}

# ----------------------------------------------------------------------------
# Lambda 실행 IAM 역할 (환경별로 분리)
# ----------------------------------------------------------------------------
resource "aws_iam_role" "lambda_role" {
  name = "demo-lambda-role-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "basic_exec" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "dynamodb" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "eventbridge" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess"
}

resource "aws_iam_role_policy_attachment" "sqs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
}

# ----------------------------------------------------------------------------
# EventBridge: 환경별 커스텀 버스 + 규칙 + SQS 타겟
# ----------------------------------------------------------------------------
resource "aws_cloudwatch_event_bus" "order_bus" {
  name = "demo-order-bus-${var.env}"
}

resource "aws_cloudwatch_event_rule" "order_rule" {
  name           = "demo-order-rule-${var.env}"
  event_bus_name = aws_cloudwatch_event_bus.order_bus.name

  event_pattern = jsonencode({
    source = ["demo.api"]
  })
}

resource "aws_cloudwatch_event_target" "to_sqs" {
  rule           = aws_cloudwatch_event_rule.order_rule.name
  event_bus_name = aws_cloudwatch_event_bus.order_bus.name
  arn            = aws_sqs_queue.order_queue.arn
}

# ----------------------------------------------------------------------------
# Event Source Mapping: SQS -> consumer-lambda
# ----------------------------------------------------------------------------
resource "aws_lambda_event_source_mapping" "sqs_to_consumer" {
  event_source_arn = aws_sqs_queue.order_queue.arn
  function_name    = aws_lambda_function.consumer.arn
  batch_size       = 5
}
