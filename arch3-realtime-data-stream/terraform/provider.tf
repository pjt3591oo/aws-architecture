terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

# Floci는 LocalStack과 같은 방식으로 단일 포트(4566)에 모든 서비스를 물려서 동작함.
# 실제 AWS 자격증명 대신 더미 값 사용, endpoints 블록으로 각 서비스 호출을
# Floci 컨테이너로 리다이렉트.
#
# 주의: endpoints 블록의 키 이름은 AWS Provider 버전마다 조금씩 달라질 수 있음.
# `terraform validate` 시 "Unsupported argument"가 뜨면
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs#custom-service-endpoints
# 에서 정확한 키 이름을 확인하고 여기 값을 맞춰줘야 함 (특히 opensearch 관련 키).
provider "aws" {
  region = var.aws_region

  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3         = var.floci_endpoint
    iam        = var.floci_endpoint
    sts        = var.floci_endpoint
    kinesis    = var.floci_endpoint
    firehose   = var.floci_endpoint
    glue       = var.floci_endpoint
    athena     = var.floci_endpoint
    opensearch = var.floci_endpoint
  }
}
