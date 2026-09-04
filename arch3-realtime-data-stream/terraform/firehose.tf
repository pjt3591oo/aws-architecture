# Kinesis -> Firehose -> S3
resource "aws_kinesis_firehose_delivery_stream" "s3" {
  name        = local.firehose_s3
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.this.arn
    role_arn            = aws_iam_role.firehose.arn
  }

  extended_s3_configuration {
    role_arn             = aws_iam_role.firehose.arn
    bucket_arn           = aws_s3_bucket.this.arn
    prefix               = local.raw_prefix
    error_output_prefix  = "errors/"

    buffering_size     = 1
    buffering_interval = 60

    compression_format = "GZIP"
  }

  depends_on = [aws_iam_role_policy.firehose]
}

# Kinesis -> Firehose -> OpenSearch
resource "aws_kinesis_firehose_delivery_stream" "opensearch" {
  name        = local.firehose_os
  destination = "opensearch"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.this.arn
    role_arn            = aws_iam_role.firehose.arn
  }

  opensearch_configuration {
    domain_arn             = aws_opensearch_domain.this.arn
    role_arn                = aws_iam_role.firehose.arn
    index_name              = var.index_name
    index_rotation_period   = "OneDay"

    buffering_interval = 60
    buffering_size     = 1

    s3_backup_mode = "FailedDocumentsOnly"

    s3_configuration {
      role_arn            = aws_iam_role.firehose.arn
      bucket_arn          = aws_s3_bucket.this.arn
      prefix              = local.os_backup_prefix
      compression_format  = "GZIP"
    }
  }

  depends_on = [
    aws_iam_role_policy.firehose,
    aws_opensearch_domain_policy.this,
  ]
}
