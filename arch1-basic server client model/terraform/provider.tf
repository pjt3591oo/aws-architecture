terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region     = "ap-northeast-2"
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  # Floci가 AWS API를 로컬(4566)에서 그대로 흉내내므로, 쓰는 서비스마다
  # endpoint를 여기로 돌려준다. (원본 스크립트의 AWS_ENDPOINT_URL=http://localhost:4566 와 동일한 역할)
  endpoints {
    ec2   = "http://localhost:4566"
    ecs   = "http://localhost:4566"
    ecr   = "http://localhost:4566"
    elbv2 = "http://localhost:4566"
    rds   = "http://localhost:4566"
    iam   = "http://localhost:4566"
    sts   = "http://localhost:4566"
  }
}
