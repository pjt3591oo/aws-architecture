# dev / prod 환경을 완전히 분리된 리소스 세트로 각각 생성한다.
# (DynamoDB 테이블, SQS 큐, EventBridge 버스, Lambda, API Gateway 모두 환경별로 독립)

module "dev" {
  source = "./modules/pipeline"

  env        = "dev"
  aws_region = var.aws_region
  account_id = var.account_id

  entry_zip_path    = "${path.module}/lambda-src/entry-lambda-placeholder.zip"
  consumer_zip_path = "${path.module}/lambda-src/consumer-lambda-placeholder.zip"
}

module "prod" {
  source = "./modules/pipeline"

  env        = "prod"
  aws_region = var.aws_region
  account_id = var.account_id

  entry_zip_path    = "${path.module}/lambda-src/entry-lambda-placeholder.zip"
  consumer_zip_path = "${path.module}/lambda-src/consumer-lambda-placeholder.zip"
}
