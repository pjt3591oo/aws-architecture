output "bucket" {
  value = aws_s3_bucket.this.bucket
}

output "kinesis_stream" {
  value = aws_kinesis_stream.this.name
}

output "kinesis_arn" {
  value = aws_kinesis_stream.this.arn
}

output "firehose_s3" {
  value = aws_kinesis_firehose_delivery_stream.s3.name
}

output "firehose_opensearch" {
  value = aws_kinesis_firehose_delivery_stream.opensearch.name
}

output "glue_database" {
  value = aws_glue_catalog_database.this.name
}

output "glue_table" {
  value = aws_glue_catalog_table.this.name
}

output "athena_workgroup" {
  value = aws_athena_workgroup.this.name
}

output "opensearch_domain" {
  value = aws_opensearch_domain.this.domain_name
}

output "opensearch_arn" {
  value = aws_opensearch_domain.this.arn
}

output "opensearch_endpoint" {
  value = "https://${aws_opensearch_domain.this.endpoint}"
}

output "opensearch_index" {
  value = var.index_name
}
