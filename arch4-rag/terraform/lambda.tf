# =====================================================================
# ingest-handler
# =====================================================================
resource "aws_lambda_function" "ingest" {
  function_name    = "ingest-handler"
  role             = aws_iam_role.lambda.arn
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  timeout          = 60
  memory_size      = 512
  filename         = "lambda-src/ingest-lambda-placeholder.zip"
  source_code_hash = filebase64sha256("lambda-src/ingest-lambda-placeholder.zip")

  environment {
    variables = {
      VECTOR_BUCKET    = aws_s3vectors_vector_bucket.rag.vector_bucket_name
      INDEX_NAME       = aws_s3vectors_index.docs.index_name
      EMBEDDING_URL    = var.embedding_url
      AWS_ENDPOINT_URL = "http://host.docker.internal:4566"
    }
  }

  # scripts/deploy-lambdas.sh 로 배포한 실제 코드를 apply가 되돌리지 않도록 무시
  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}

resource "aws_lambda_permission" "ingest_s3" {
  statement_id  = "s3invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.docs.arn
}

# =====================================================================
# query-handler
# =====================================================================
resource "aws_lambda_function" "query" {
  function_name    = "query-handler"
  role             = aws_iam_role.lambda.arn
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  timeout          = 60
  memory_size      = 512
  filename         = "lambda-src/query-lambda-placeholder.zip"
  source_code_hash = filebase64sha256("lambda-src/query-lambda-placeholder.zip")

  environment {
    variables = {
      VECTOR_BUCKET    = aws_s3vectors_vector_bucket.rag.vector_bucket_name
      INDEX_NAME       = aws_s3vectors_index.docs.index_name
      EMBEDDING_URL    = var.embedding_url
      CHAT_URL         = var.chat_url
      AWS_ENDPOINT_URL = "http://host.docker.internal:4566"
    }
  }

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}
