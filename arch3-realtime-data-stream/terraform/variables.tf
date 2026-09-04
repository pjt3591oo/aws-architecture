variable "project" {
  description = "리소스 이름 접두사"
  type        = string
  default     = "kinesis-analytics-demo"
}

variable "aws_region" {
  description = "리전 (Floci는 리전 검증 안 하지만 ARN 조립에 사용됨)"
  type        = string
  default     = "ap-northeast-2"
}

variable "account_id" {
  description = "Floci 고정 계정 ID"
  type        = string
  default     = "000000000000"
}

variable "floci_endpoint" {
  description = "Floci 컨테이너 엔드포인트"
  type        = string
  default     = "http://localhost:4566"
}

variable "index_name" {
  description = "OpenSearch 인덱스 이름"
  type        = string
  default     = "events"
}

locals {
  bucket = "${var.project}-${var.account_id}"

  kinesis_stream = "${var.project}-stream"

  firehose_s3   = "${var.project}-to-s3"
  firehose_os   = "${var.project}-to-os"
  firehose_role = "${var.project}-firehose-role"

  glue_database = "${var.project}_db"
  glue_table    = "${var.project}_events"
  glue_role     = "${var.project}-glue-role"

  athena_workgroup = "${var.project}-workgroup"

  opensearch_domain = "${var.project}-os"

  raw_prefix        = "raw/"
  athena_prefix      = "athena-results/"
  os_backup_prefix   = "opensearch-backup/"
}
