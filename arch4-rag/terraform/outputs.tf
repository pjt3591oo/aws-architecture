output "docs_bucket" {
  value = aws_s3_bucket.docs.bucket
}

output "vector_bucket" {
  value = aws_s3vectors_vector_bucket.rag.vector_bucket_name
}

output "index_name" {
  value = aws_s3vectors_index.docs.index_name
}

output "ingest_function_name" {
  value = aws_lambda_function.ingest.function_name
}

output "query_function_name" {
  value = aws_lambda_function.query.function_name
}

output "invoke_url" {
  description = "RAG 질의 API 엔드포인트 (curl -X POST 대상)"
  value       = "${var.floci_endpoint}/restapis/${aws_api_gateway_rest_api.rag.id}/${aws_api_gateway_stage.dev.stage_name}/_user_request_/query"
}
