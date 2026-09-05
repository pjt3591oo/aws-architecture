data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "rag-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# 원본 스크립트와 동일하게 AdministratorAccess를 부여했지만,
# 실운영 환경에서는 S3 / S3Vectors / CloudWatch Logs 등으로
# 범위를 좁힌 최소 권한 정책 사용을 권장합니다.
resource "aws_iam_role_policy_attachment" "lambda_admin" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
