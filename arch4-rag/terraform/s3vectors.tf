resource "aws_s3vectors_vector_bucket" "rag" {
  vector_bucket_name = var.vector_bucket
}

resource "aws_s3vectors_index" "docs" {
  vector_bucket_name = aws_s3vectors_vector_bucket.rag.vector_bucket_name
  index_name         = var.index_name
  data_type          = "float32"
  dimension          = var.embedding_dim
  distance_metric    = "cosine"
}
