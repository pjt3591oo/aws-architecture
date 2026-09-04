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
