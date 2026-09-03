# 원본 bash 스크립트와 동일하게 로컬 Floci 엔드포인트(localhost:4566)를 사용한다.
# 실제 AWS로 옮길 때는 이 provider 블록의 endpoints{} 전체와
# access_key/secret_key, skip_* 옵션들을 제거하면 된다.
provider "aws" {
  access_key = "test"
  secret_key = "test"
  region     = var.aws_region

  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    apigateway = "http://localhost:4566"
    dynamodb   = "http://localhost:4566"
    events     = "http://localhost:4566"
    iam        = "http://localhost:4566"
    lambda     = "http://localhost:4566"
    sqs        = "http://localhost:4566"
    sts        = "http://localhost:4566"
    cloudwatch = "http://localhost:4566"
    logs       = "http://localhost:4566"
  }
}
