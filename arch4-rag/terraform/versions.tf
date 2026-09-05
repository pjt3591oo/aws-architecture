terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60, < 6.58.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }
}

# ---------------------------------------------------------------------
# floci(로컬 AWS 에뮬레이터)를 가리키는 프로바이더 설정.
# 실제 AWS 계정에 배포하려면 access_key/secret_key, skip_* 옵션,
# endpoints 블록을 모두 제거하면 됩니다.
# ---------------------------------------------------------------------
provider "aws" {
  region = var.aws_region

  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  s3_use_path_style           = true

  endpoints {
    s3         = var.floci_endpoint
    s3vectors  = var.floci_endpoint
    lambda     = var.floci_endpoint
    iam        = var.floci_endpoint
    apigateway = var.floci_endpoint
    sts        = var.floci_endpoint
  }
}
