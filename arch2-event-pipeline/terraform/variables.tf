variable "aws_region" {
  description = "리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "account_id" {
  description = "Floci/LocalStack 계정 ID (원본 스크립트와 동일하게 고정값 사용)"
  type        = string
  default     = "000000000000"
}
