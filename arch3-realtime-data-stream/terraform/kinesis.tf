resource "aws_kinesis_stream" "this" {
  name        = local.kinesis_stream
  shard_count = 1
}
